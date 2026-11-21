"""Matched orthographic texture-on/texture-off plates for character geometry QA.

The projected image is the user's own front lineup, unlit where it applies. The
pure-color plates are separately lit, so the texture cannot disguise the sculpt.
"""
from argparse import ArgumentParser
import json
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
from anatomy_geometry import CAST,PROFILES
from anatomy_projection import HEIGHT,HALF,reference_mask
from tripo_surface_preview import NAMES,font,raster


def bilinear(image,u,v):
    u=np.clip(u,0,image.shape[1]-1.00001);v=np.clip(v,0,image.shape[0]-1.00001)
    x,y=u.astype(int),v.astype(int)
    a,b=(u-x)[:,None],(v-y)[:,None]
    return (1-b)*((1-a)*image[y,x]+a*image[y,x+1])+b*((1-a)*image[y+1,x]+a*image[y+1,x+1])


def projector(image,profile):
    img=np.asarray(image,dtype='float32')
    p=profile;scale=p.foot-p.crown
    mask=reference_mask(image,p).astype('float32')[...,None]
    def shade(name,xyz,normal,base):
        if name.startswith(('Eye','Brow','Moustache','Goatee')):
            # Review eyes and actual separate groom remain selectable. The
            # body/garment photograph only projects onto visible front faces.
            eligible=np.ones(len(xyz))
        else:eligible=np.clip((-normal[:,1]-.06)/.34,0,1)
        x,_,z=xyz.T
        col=bilinear(img,p.center+x*scale,p.foot-z*scale)
        m=bilinear(mask,HALF+x*HEIGHT,(1-z)*HEIGHT)[:,0]
        a=(m*eligible)[:,None]
        return col*a+base*(1-a)
    return shade


def export_projection_map(image,p,out):
    mask=reference_mask(image,p)
    y,x=np.mgrid[:HEIGHT+1,:2*HALF+1]
    scale=(p.foot-p.crown)/HEIGHT
    rgb=bilinear(np.asarray(image,dtype='float32'),(p.center+(x-HALF)*scale).ravel(),(p.crown+y*scale).ravel())
    rgb=np.round(rgb).astype('uint8').reshape((*mask.shape,3))
    Image.fromarray(np.dstack([rgb,255*mask])).save(out)


def load(path):
    return [(o['name'],np.asarray(o['v']),o['f'],np.asarray(o['color'])) for o in json.loads(path.read_text(encoding='utf-8'))]


def target_crop(im,p,sz,view,idx=0):
    w,h=sz; hh=(.216 if idx==1 else .196) if view=='head' else 1.095
    mid=.924 if view=='head' else .5
    u,w0=p.center,hh*(p.foot-p.crown)*w/h/2
    v,h0=p.foot-mid*(p.foot-p.crown),hh*(p.foot-p.crown)/2
    return im.transform(sz,Image.Transform.EXTENT,(u-w0,v-h0,u+w0,v+h0),Image.Resampling.BICUBIC)


def image_pairs(image,base,mesh,idx,sz,view):
    p=PROFILES[idx];pro=projector(image,p)
    body_angle=0 if view=='full' else 22
    x=[target_crop(image,p,sz,view,idx),raster(mesh,0,sz,view,level=idx,shader=pro),
       raster(base,body_angle,sz,view,level=idx),raster(mesh,body_angle,sz,view,level=idx),
       raster(mesh,35 if view=='full' else 46,sz,view,level=idx,shader=pro),
       raster(mesh,35 if view=='full' else 46,sz,view,level=idx)]
    return x


def make_plates(image,old,folder,out,slugs):
    n=len(slugs); w,h=256,459; head=(256,244); pad=12
    wcol=w+6
    plate=Image.new('RGB',(n*wcol+20,2*h+140),'#171d25');photo=ImageDraw.Draw(plate)
    photo.text((pad,10),'参考图直投  /  身体',font=font(25,True),fill='#f1e7d0')
    photo.text((pad,54),'上：原图。下：贴到实际网格的同机位投影。观察剪影、眼位、衣缘、手脚对位。',font=font(16),fill='#bdc8d4')
    face=Image.new('RGB',(n*wcol+20,3*head[1]+131),'#171d25');fg=ImageDraw.Draw(face)
    fg.text((pad,10),'参考图直投  /  脸和耳',font=font(25,True),fill='#f1e7d0')
    fg.text((pad,53),'从上到下：原图、正面贴图、斜侧纯色。贴图层仅用于对位检查。',font=font(16),fill='#bdc8d4')
    for j,slug in enumerate(slugs):
        idx=CAST.index(slug);name=NAMES[idx]
        export_projection_map(image,PROFILES[idx],out/f'{slug}-front-rgba.png')
        base=load(old/f'{slug}-sculpt.json');mesh=load(folder/f'{slug}-sculpt.json')
        vs=image_pairs(image,base,mesh,idx,(w,h),'full')
        hs=image_pairs(image,base,mesh,idx,head,'head')
        x=pad+j*wcol; photo.text((x,86),name,font=font(17,True),fill='#e0e8f0');fg.text((x,86),name,font=font(17,True),fill='#e0e8f0')
        for k in range(2):plate.paste(vs[k],(x,110+k*(h+6)))
        for r,k in enumerate((0,1,5)):face.paste(hs[k],(x,110+r*(head[1]+6)))
        wide=Image.new('RGB',(6*wcol+20,h+head[1]+143),'#171d25');g=ImageDraw.Draw(wide)
        g.text((pad,10),name+'  /  投影与几何的分离检查',font=font(25,True),fill='#f1e7d0')
        g.text((pad,51),'全身和脸均用同一参考变换。纯色栏直接检查面转折，投影栏核对贴图在网格上的位置。',font=font(16),fill='#bdc8d4')
        for k,label in enumerate(('原图','正投影贴图','前版 · 纯色','本轮 · 纯色','斜侧 · 贴图','斜侧 · 纯色')):
            x=pad+k*wcol;g.text((x,82),label,font=font(17,True),fill='#e0e8f0');wide.paste(vs[k],(x,108));wide.paste(hs[k],(x,116+h))
        wide.save(out/f'{slug}-photo-sculpt.jpg',quality=94)
        print('Compared',slug,flush=True)
    plate.save(out/'cast-photo-projection.jpg',quality=94)
    face.save(out/'cast-photo-faces.jpg',quality=94)


if __name__=='__main__':
    a=ArgumentParser(description=__doc__)
    a.add_argument('reference',type=Path);a.add_argument('baseline',type=Path);a.add_argument('geometry',type=Path);a.add_argument('out',type=Path)
    a.add_argument('--cast',nargs='+',choices=CAST,default=CAST)
    x=a.parse_args();x.out.mkdir(parents=True,exist_ok=True)
    make_plates(Image.open(x.reference).convert('RGB'),x.baseline,x.geometry,x.out,x.cast)
