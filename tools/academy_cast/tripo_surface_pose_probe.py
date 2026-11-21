"""Temporary one-sided hinge probes for the detective review cage, not skin weights."""
from argparse import ArgumentParser
from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageDraw
from tripo_surface import tris, unit
from tripo_surface_preview import CAST, font, panels, raster


def ss(lo, hi, val):
    x = np.clip((val-lo)/(hi-lo),0,1)
    return x*x*(3-2*x)


def rotate(v, pivot, axis, angle):
    q=v-pivot; a=np.asarray(angle)[...,None]
    return pivot+q*np.cos(a)+np.cross(axis,q)*np.sin(a)+np.sum(q*axis,axis=-1,keepdims=True)*axis*(1-np.cos(a))


def section_center(v,f,h,branch):
    qa=v[np.array(list({(min(a,b),max(a,b)) for g in f for a,b in zip(g,g[1:]+g[:1])}))]
    a,b=qa[(qa[:,0,2]<h)!=(qa[:,1,2]<h)].transpose(1,0,2)
    q=a+(b-a)*((h-a[:,2])/(b[:,2]-a[:,2]))[:,None]
    s=q[q[:,0]>branch]
    if len(s)<4:raise ValueError('section is too sparse for the review probe')
    return (s.max(0)+s.min(0))*.5


def move(v, joints, mode):
    sh, el, wr, hip, knee = joints
    x,_,z=v.T
    if mode=='arm':
        axis=np.array([0.,1.,0.]); shoulder=np.radians(-38)
        cut=.102+.30*(.77-z)
        sel=ss(-.020,.021,x-cut)*ss(.31,.40,z)*(1-ss(.782,.813,z))
        u=rotate(v,sh,axis,sel*shoulder)
        el0=rotate(el,sh,axis,shoulder);wr0=rotate(wr,sh,axis,shoulder)
        ax=unit(np.cross(wr0-el0,[0,-1,0]))
        along=(v-el)@unit(wr-el)
        return rotate(u,el0,ax,np.radians(64)*ss(-.030,.030,along)*ss(.75,.99,sel))
    axis=np.array([1.,0.,0.]); angle=np.radians(-34)
    sel=ss(-.005,.035,x)*(1-ss(.455,.57,z))
    u=rotate(v,hip,axis,sel*angle);k0=rotate(knee,hip,axis,angle)
    return rotate(u,k0,axis,np.radians(68)*(1-ss(.251,.313,z))*ss(-.005,.035,x))


def run(output):
    data=json.loads((output/f'{CAST[0]}.json').read_text(encoding='utf-8'))
    v=np.asarray(data['v']);f=data['f']
    el=section_center(v,f,.659,.163);wr=section_center(v,f,.534,.224)
    sh=section_center(v,f,.770,.085);sh[0]-=.014
    hip=section_center(v,f,.509,.016);hip[0]=.057
    knee=section_center(v,f,.282,.012); J=(sh,el,wr,hip,knee)
    src=list(panels(data,0)); t=tris(f)
    def areas(v):
        a,b,c=v[t].transpose(1,0,2)
        return np.linalg.norm(np.cross(b-a,c-a),axis=1)
    ar=areas(v)
    res={}; w,h=320,522
    canvas=Image.new('RGB',(w*3+40,h*2+121),'#171d25');p=ImageDraw.Draw(canvas)
    p.text((15,13),'侦探  /  关节折弯试姿',font=font(25,True),fill='#f3e6cc')
    p.text((15,50),'用临时关节枢轴测试同一底模；上排纯色，下排实际网格。',font=font(16),fill='#bac8d6')
    for i,(mode,title) in enumerate([('neutral','中性'),('arm','抬臂 / 屈肘'),('leg','屈髋 / 屈膝')]):
        parts=[(k,move(u,J,mode) if mode!='neutral' else u,fs,c) for k,u,fs,c in src]
        ratio=areas(parts[0][1])/np.maximum(ar,1e-12)
        res[mode]={'triangles_below_half_rest_area':int(np.count_nonzero(ratio<.5)),
                   'triangles_above_double_rest_area':int(np.count_nonzero(ratio>2))}
        x=13+i*(w+7);p.text((x,81),title,font=font(16,True),fill='#e1e9f0')
        canvas.paste(raster(parts,44,(w,h)),(x,108))
        canvas.paste(raster([p for p in parts if p[0] in ('body','eye0','eye1')],44,(w,h),wire=True),(x,111+h))
    canvas.save(output/'01-detective-hinge-probes.jpg',quality=94)
    (output/'01-detective-hinge-probes.json').write_text(json.dumps({'pivots_normalized':[q.tolist() for q in J],'probes':res},indent=2),encoding='utf-8')

if __name__=='__main__':
    ap=ArgumentParser(description=__doc__);ap.add_argument('output',type=Path);run(ap.parse_args().output)
