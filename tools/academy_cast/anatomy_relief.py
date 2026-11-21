"""Bounded, anatomical front relief. Inputs: normalized Body only, front = -Y.
Reference luminance modulates anatomical planes, never supplies vertex depths.
"""
from pathlib import Path
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, map_coordinates
from anatomy_geometry import FACE, surface_normals
from tripo_surface import tris


def apply_relief(verts, faces, image, profile, index, strength=1., *, locked=(), report=None):
    v = np.asarray(verts, dtype=float); q = profile
    im = np.asarray(Image.open(image).convert('RGB') if isinstance(image,(str,Path)) else image, dtype=float)[...,:3]
    x,y,z = v.T; h = q.foot-q.crown; px=q.center+x*h; py=q.foot-z*h
    # Fit the strength of each anatomical primitive from bilateral, broad-scale
    # skin contrast. Reject ink, neutral cloth, hard occlusion and background.
    r,g,b = im.transpose(2,0,1); l=.299*r+.587*g+.114*b
    skin=(r-b>14)&(r>100)&(g>68)&(r>g)&(l<250)
    def blur(s):
        mass=gaussian_filter(skin.astype(float),s); return gaussian_filter(l*skin,s)/np.maximum(.001,mass),mass
    fine,m=blur(2.3); broad,_=blur(7); band=np.clip(abs(fine-broad)/20,0,1)*np.clip((m-.62)/.3,0,1)
    pupil,other,lip,lipw,nose=FACE[index]; e=(pupil[1]+other[1])/2; eye=abs(other[0]-pupil[0])/2
    d=np.zeros(len(v)); ax=abs(px-q.center); sh=q.shoulder_x-q.center; k=q.knee_x-q.center
    def plane(cx,cy,wx,wy,amp,slope=0):
        xx=ax-cx; zz=py-cy-slope*xx
        offsets=np.array([-0.55,0,.55]); samples=[(cy+j*wy,q.center+side*(cx+i*wx)) for side in (-1,1) for i in offsets for j in offsets]
        contrast=map_coordinates(band,np.array(samples).T,order=1).mean(); d[:]+=amp*(.40+contrast)*np.exp(-(xx/wx)**2-(zz/wy)**2)
    plane(eye,e-6,eye*.85,2.6,.0032,-.13); plane(eye,e-12,eye,5,.0018); plane(eye*1.45,nose-1,4,3,.0038,-.32); plane(eye*1.25,q.chin-5,4,3,.0028,-.6)
    plane(sh*.47,q.pit-2,sh*.39,10,.008,-.10); plane(sh*.53,q.pit+8,sh*.34,3,-.0045,-.14); plane(sh*.97,q.shoulder+7,9,12,.006,.40)
    plane(sh*.45,(q.pit+q.waist)*.5,8,6,.004,-.55); plane(sh*.22,q.waist-8,5,12,.003); plane(sh*.61,q.waist-8,6,11,.0035,-.7)
    plane(k,q.knee,5,6,.005); plane(k-3,q.knee-10,5,8,.004,-.35); plane(k+1,(q.knee*2+q.ankle)/3,3.5,17,.0038,.4)
    # Forearm follows the actual A-pose outline independently of shoulder width.
    arm=(py>q.pit+8)&(py<q.crotch-3)&(ax>sh+4)
    if arm.any():
        levels=np.linspace(q.pit+12,q.crotch-7,6); centers=[]
        for level in levels:
            row=ax[arm&(abs(py-level)<6)]; centers.append(np.median(row) if len(row)>5 else np.nan)
        ok=np.isfinite(centers)
        for cy,cx in zip(levels[ok][1:-1],np.asarray(centers)[ok][1:-1]): plane(cx,cy,5,9,.0028,.7)
    normals=surface_normals(v,faces); front=np.clip((-normals[:,1]-.12)/.65,0,1)
    # Conservative safety windows include eyelids, brow attachment and lip rings.
    freeze=(abs(py-e)<4.5)&(ax<eye+6) | ((abs(py-lip)<4)&(ax<lipw*.6+4))
    freeze|=(py>q.waist-2)&(py<q.crotch+8)&(ax<q.hip_x-q.center+5)
    if index==5:
        # Keep the interior of Qingyue's separate sports-top coverage intact.
        a=abs(x)
        top=.795+.047*np.clip((a-.017)/.061,0,1)+.019*np.clip(y/.050,0,1)
        width=.122-.047*np.clip((z-.715)/.130,0,1)
        freeze|=(z>.656)&(z<top+.003)&(a<width+.003)
    freeze[np.asarray(locked,dtype=int)]=True
    dy=-strength*[.92,.78,1.16,.83,1.22,.48,.90][index]*front*d; dy[freeze]=0
    t=np.asarray(tris(faces)); orig=np.cross(v[t[:,1]]-v[t[:,0]],v[t[:,2]]-v[t[:,0]])
    area=(orig*orig).sum(1); valid=area>1e-20
    tt=t[valid]; org=orig[valid]; denom=area[valid]
    if not len(tt):
        raise ValueError('No nonzero triangles in relief input')
    out=v.copy(); weight=np.ones(len(v)); scale=1.
    def orientation():
        out[:,1]=y+dy*weight*scale
        n=np.cross(out[tt[:,1]]-out[tt[:,0]],out[tt[:,2]]-out[tt[:,0]])
        return (n*org).sum(1)/denom
    # A skinny quad under an eyelid or shoulder seam must not throttle the
    # whole body. Limit the vertex displacement around its local 1-ring.
    for _ in range(21):
        relative=orientation()
        if relative.min()>=.35:break
        bad=np.unique(tt[relative<.35]); selected=np.zeros(len(v),dtype=bool);selected[bad]=True
        touching=np.any(selected[tt],axis=1)
        nearby=np.unique(tt[touching]);weight[nearby]*=.91;weight[bad]*=.65
    for _ in range(24):
        relative=orientation()
        if relative.min()>=.35:break
        scale*=.75
    else: raise ValueError('relief triangle orientation check failed')
    if report is not None:
        report.update(scale=scale, peak_pct_height=float(abs(out[:,1]-y).max()*100),
                      moved=int((abs(out[:,1]-y)>1e-5).sum()), min_projected_area_ratio=float(relative.min()),
                      locally_limited=int((weight<1).sum()), frozen=int(freeze.sum()))
    return out
