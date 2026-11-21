"""False-color solid and topology previews of the mesh JSON produced by tripo_surface.py."""
from argparse import ArgumentParser
from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from tripo_surface import CAST, tris, unit, main_component

NAMES = ('侦探', '诗人 · 卢西安', '律师 · 沃德', '厨师 · 沈鼎', '工程师 · 霍铎', '棋手 · 阮清月', '恶魔 · 代管者')
SKIN = [(190,151,129),(166,131,115),(182,141,117),(185,142,109),(173,134,114),(199,164,142),(162,130,120)]
CLOTH = [(61,65,73),(57,64,74),(63,66,70),(62,62,65),(57,63,65),(67,70,83),(70,65,74)]
EYE = np.asarray([(205,194,174), (222,211,192),(91,67,51),(22,22,24)])
WAIST = [(.580,.443),(.597,.478),(.568,.441),(.576,.434),(.576,.449),(.565,.457),(.591,.472)]


def clothes(v,f,idx):
    """Independent simple review clothing. Clip the body triangulation to seams, then offset.

    Pure color only. The unmasked base is retained, including all underlying skin polygons.
    """
    t=tris(f); a,b,c=v[t].transpose(1,0,2); normals=np.cross(b-a,c-a); vn=np.zeros_like(v)
    for k in range(3):np.add.at(vn,t[:,k],normals)
    x,y,z=v.T
    waist, hem=WAIST[idx]
    band_top=waist + .026*np.abs(x)/.13 + .009*np.clip(y/.07,-1,1)
    specs=[('Underwear', [band_top-z,z-hem,.190-np.abs(x)], .0023)]
    if idx==5:
        # Armholes and broad shoulder straps; cut the front neckline lower than the back.
        up=.795+.047*np.clip((np.abs(x)-.017)/.061,0,1)+.019*np.clip(y/.050,0,1)
        spec=[z-.659, up-z, (.122-.047*np.clip((z-.715)/.130,0,1))-np.abs(x)]
        specs.append(('Sports top',spec,.0024))
    out={}
    for name, signs, offset in specs:
        vv = v+unit(vn)*offset
        points=[];lookup={};polys=[]; seen=set()
        s=np.stack(signs,axis=-1)
        for ids in t:
            if np.any(np.all(s[ids]<0,axis=0)):continue
            poly=list(zip(vv[ids],s[ids]))
            for j in range(s.shape[1]):
                clipped=[]
                for (a,sa),(b,sb) in zip(poly,poly[1:]+poly[:1]):
                    t1,t2=sa[j],sb[j]
                    if t1>=0:clipped.append((a,sa))
                    if (t1>=0)!=(t2>=0):
                        w=t1/(t1-t2);clipped.append((a+(b-a)*w,sa+(sb-sa)*w))
                poly=clipped
                if len(poly)<3:break
            face=[]
            for p,_ in poly:
                k=tuple(np.round(p,7));i=lookup.setdefault(k,len(points))
                if i==len(points):points.append(p)
                face.append(i)
            key=tuple(sorted(face))
            if len(face)>=3 and len(set(face))==len(face) and key not in seen:
                polys.append(face);seen.add(key)
        pos,polys,_=main_component(np.array(points),polys)
        out[name]=pos,polys
    return out


def panels(data, idx, with_cloth=True):
    v=np.asarray(data['v']); f=data['f']
    skin=np.tile(SKIN[idx],(len(f),1))
    if '2' in data['loops']:
        mouth=set(data['loops']['2']['inside'])
        for j,g in enumerate(f):
            if len(mouth.intersection(g))>=2:skin[j]=(62,34,32)
    yield 'body',v,f,skin
    if with_cloth:
        for n,(v,f) in clothes(v,f,idx).items():yield n,v,f,np.tile(CLOTH[idx],(len(f),1))
    for i,e in enumerate(data['eyes']):
        yield f'eye{i}',np.array(e['v']),e['f'],EYE[e['mat']]


def raster(meshes, angle, size, view='full', wire=False, level=0):
    w,h=size; zoom=1.4; ww,hh=round(w*zoom),round(h*zoom)
    phi=np.radians(angle); co,si=np.cos(phi),np.sin(phi)
    # Body vertices are source normalized, correct world scale is selected in Blender.
    M=np.array([[co,si,0],[0,0,1],[si,-co,0]]).T
    center=(0,.50); screen_h=1.095
    if view=='head':center=(0,.924);screen_h=.196 if level!=1 else .216
    pix=hh/screen_h
    canvas=np.empty((hh,ww,3),dtype=np.uint8); canvas[:]=[34,41,50]
    depth=np.full((hh,ww),-np.inf)
    for name,v,faces,color in meshes:
        xyz=v@M; p=xyz.copy(); p[:,0]=(p[:,0]-center[0])*pix+ww/2; p[:,1]=(center[1]-p[:,1])*pix+hh/2
        # Smooth normals mix only for solid color view. Edges always use the base mesh.
        vn=np.zeros_like(v)
        for f in faces:
            q=xyz[f]*[1,-1,1];n=np.cross(q[1]-q[0],q[2]-q[0]);vn[f]+=n
        vn=unit(vn)
        for fi,f in enumerate(faces):
            af=p[f]; material=np.array(color[fi]);
            for t in range(1,len(f)-1):
                ii=np.array([0,t,t+1]);face=np.array(f)[ii]; a,b,c=af[ii]
                lo=np.maximum(np.floor(np.min([a,b,c],axis=0)).astype(int)[:2],[0,0]);hi=np.minimum(np.ceil(np.max([a,b,c],axis=0)).astype(int)[:2],[ww-1,hh-1]);
                if np.any(lo>hi):continue
                s,b1,c1=af[ii];d=b1-s;e=c1-s;det=d[0]*e[1]-d[1]*e[0]
                if abs(det)<1e-10:continue
                X,Y=np.meshgrid(np.arange(lo[0],hi[0]+1)+.5-s[0],np.arange(lo[1],hi[1]+1)+.5-s[1]);
                B=(X*e[1]-Y*e[0])/det;C=(d[0]*Y-d[1]*X)/det;A=1-B-C
                Z=s[2]+B*d[2]+C*e[2];tile=np.s_[lo[1]:hi[1]+1,lo[0]:hi[0]+1];dep=depth[tile];goal=canvas[tile]
                m=(np.minimum(np.minimum(A,B),C)>=-1e-7)&(Z>dep)
                if not m.any():continue
                a=np.column_stack([A[m],B[m],C[m]]);n=unit(a@vn[face]); shade=.66+.34*np.clip(n@np.array([-.43,.60,-.67]),-.82,1.)
                base=shade[:,None]*material
                if wire:
                    color_line=np.array([29,43,56]);density=np.zeros(len(a));
                    if name=='body':base=shade[:,None]*[204,209,215]
                    for k,(j,l) in enumerate(((t,t+1),(t+1,0),(0,t))):
                        if (l-j)%len(f)!=1:continue
                        gap=a[:,k]*abs(det)/max(np.linalg.norm(af[j,:2]-af[l,:2]),1e-6)
                        density=np.maximum(density,np.clip(1.23-gap,0,.94))
                    base=base*(1-density[:,None])+color_line*density[:,None]
                dep[m]=Z[m]; goal[m]=np.clip(base,0,255)
    return Image.fromarray(canvas).resize(size,Image.Resampling.LANCZOS)


def font(n, bold=False):
    return ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc' if bold else 'C:/Windows/Fonts/msyh.ttc', n)


def draw(output):
    # Solid column followed by actual quad wires. Cloth is hidden in wire-only views.
    result=json.loads((output/'metrics.json').read_text(encoding='utf-8')); cards=[]
    for stats in result:
        slug=stats['character'];idx=CAST.index(slug); d=json.loads((output/f'{slug}.json').read_text(encoding='utf-8'))
        all_parts=list(panels(d,idx)); topo=list(panels(d,idx,with_cloth=False))
        geometry = [dict(name=n, v=v.tolist(), f=f, color=color.tolist()) for n,v,f,color in all_parts]
        (output/f'{slug}-parts.json').write_text(json.dumps(geometry),encoding='utf-8')
        w,h=300,510; sheet=Image.new('RGB',(4*w+42,h+134),'#171d25'); g=ImageDraw.Draw(sheet)
        g.text((18,11),f'{NAMES[idx]}  /  原模表面局部重布线',font=font(24,True),fill='#f0e5cd')
        cg=stats['surface_centroid_shift']['distance_pct_h'];vol=stats['closed_volume_centroid_shift'];vol_s=f'{vol["distance_pct_h"]:.3f}%' if vol is not None else '—'
        g.text((18,49),f'底模+眼球 {stats["total_triangle_equivalent"]:,} 折三角    ｜    表面积中心偏差 {cg:.3f}% H    ｜    封闭体估算重心偏差 {vol_s} H',font=font(15),fill='#aebbc8')
        for j,(label,mesh,angle,wire) in enumerate([('纯色与独立内衣',all_parts,13,False),('正面网格',topo,0,True),('侧前网格',topo,39,True),('背面网格',topo,170,True)]):
            x=12+j*(w+6);g.text((x,82),label,font=font(15,True),fill='#dce4ed');im=raster(mesh,angle,(w,h),wire=wire);sheet.paste(im,(x,106))
        sheet.save(output/f'{slug}-review.jpg',quality=94)
        cards.append((idx,all_parts,topo,stats))
    w,h=242,408; W=w*len(cards)+32; H=2*h+136
    grid=Image.new('RGB',(W,H),'#171d25'); g=ImageDraw.Draw(grid)
    g.text((16,11),'学院人物底模  /  纯色 + 实际网格',font=font(25,True),fill='#f3e6cc')
    g.text((16,49),'按各角色自己的 Tripo 网格修整；衣件为独立纯色对象。线框只显示身体与眼球。每人单独归一，排版不比较身高。',font=font(15),fill='#aebbc8')
    fm=Image.new('RGB',(W,2*248+112),'#171d25'); fg=ImageDraw.Draw(fm)
    fg.text((16,11),'头面局部  /  纯色与眼睑、唇缘线框',font=font(25,True),fill='#f3e6cc')
    for j,(idx,all_parts,topo,s) in enumerate(cards):
        x=16+j*w; g.text((x+2,81),NAMES[idx],font=font(17,True),fill='#e0e7ef'); fg.text((x+2,63),NAMES[idx],font=font(17,True),fill='#e0e7ef')
        grid.paste(raster(all_parts,10,(w-4,h)),(x,111));grid.paste(raster(topo,39,(w-4,h),wire=True),(x,113+h));
        fg0=raster(all_parts,12,(w-4,246),'head',False,idx);fg1=raster(topo,20,(w-4,246),'head',True,idx)
        fm.paste(fg0,(x,94));fm.paste(fg1,(x,343));
    grid.save(output/'cast-solid-wire.jpg',quality=95);fm.save(output/'cast-face-wire.jpg',quality=95)

if __name__=='__main__':
    a=ArgumentParser(description=__doc__);a.add_argument('output',type=Path);args=a.parse_args();draw(args.output)
