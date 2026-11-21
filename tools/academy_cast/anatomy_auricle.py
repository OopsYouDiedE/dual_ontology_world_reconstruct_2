"""Build closed auricle patches directly into the original scalp."""
import numpy as np
from tripo_surface import adjacency, borders

EAR_Y = [.017,.017,.017,.014,.003,.007,.010]
EAR_H = [.0205,.0188,.020,.0202,.0192,.0185,.020]
EAR_W = [.0107,.0094,.0115,.0106,.010,.0096,.0108]


def angular_order(yz, cy, cz):
    y,z=yz.T; z=z-cz; y=y-cy+z*.18
    raw=np.unwrap(np.arctan2(z/.033,y/.018))
    direction=1 if raw[-1]>raw[0] else -1
    angle=direction*raw
    gaps=np.diff(np.r_[angle,angle[0]+2*np.pi])
    steps=np.maximum(.028,gaps);steps*=2*np.pi/steps.sum()
    theta=direction*(angle[0]+np.r_[0,np.cumsum(steps[:-1])])
    return theta,max(0.,-float(gaps.min())),float(gaps.max())


def bases(v,f,cy,cz,side,high,protected):
    centers=np.array([v[g].mean(0) for g in f]); near=side*centers[:,0]>.023
    for dy,dz in ((0,0),(.003,0),(-.003,0),(0,.003),(0,-.003)):
        for radius in (.87,1.,1.14,1.26,1.39):
            yy,zz=cy+dy,cz+dz
            d2=((centers[:,1]-yy+.18*(centers[:,2]-zz))/.018)**2+((centers[:,2]-zz)/.033)**2
            ids=np.flatnonzero((d2<radius*radius)&near)
            patch=[f[i] for i in ids]; rr=borders(adjacency(patch))
            if len(rr)!=1:continue
            rim=rr[0];n=len(rim)
            if n%2 or n<8 or n>(44 if high else 24):continue
            hit={k for face in patch for k in face}
            if hit.intersection(protected):continue
            w=v[rim];theta,back,gap=angular_order(w[:,1:],yy,zz)
            if gap>2 or back>.50 or np.ptp(w[:,2])<.039:continue
            score=back*5+gap*.56+(.018 if high else .052)*n+52*(abs(dy)+abs(dz))+.26*abs(radius-1.12)
            yield score,ids,rim,theta,hit,yy,zz


def ear_rings(v,f,idx,side,high,record):
    _,ids,rim,theta,hits,cy,cz=record
    old=v[rim];z0=cz+.001
    t=np.sin(theta);a=np.cos(theta)
    zr=EAR_H[idx]*np.where(t<0,1.04,1.)*t
    yr=EAR_W[idx]*(.98+.23*np.maximum(t,0)-.20*np.maximum(-t,0))*a+.16*zr
    root=np.quantile(side*old[:,0],.40)
    prior=np.quantile(side*v[sorted(hits),0],.94)
    peak=np.clip(prior+.003,root+.011,root+.018)
    # The thick superior helix and posterior rim stand away from the head.
    # The low, anterior attachment leads into a small tragus and off-center bowl.
    attachment=.0042*a+.0022*t
    fork=np.exp(-((t-.48)/.38)**2)*(.25+.75*np.maximum(a,0))
    tragus=np.exp(-((t+.21)/.34)**2)*np.maximum(-a,0)**3
    lobule=np.exp(-((t+.99)/.22)**2)
    # Retaining a third ring at low resolution makes the inner ridge real geometry.
    steps=[(.98,0.,0.),(.74,-.003,.001),(.48,-.0018,.0024),(.25,-.0083,.0005)] if high else [(.98,0.,0.),(.68,-.0055,.0012),(.37,-.0028,.0017)]
    ext=[];patch=[];prev=rim;n=len(rim)
    for j,(r,offset,bump) in enumerate(steps):
        y=cy+r*yr-.0023*(1-r); z=z0+r*zr-.0041*(1-r)
        lift=peak+offset+attachment+bump*fork+.0044*tragus*(j>0)
        if j==0:lift+=.0018*lobule-.0030*np.maximum(-a,0)
        else:lift-=.0017*lobule
        ring=list(range(len(v)+len(ext),len(v)+len(ext)+n))
        ext.extend(np.c_[side*lift,y,z].tolist())
        patch.extend([[prev[k],prev[(k+1)%n],ring[(k+1)%n],ring[k]] for k in range(n)])
        prev=ring
    concha=len(v)+len(ext)
    ext.append([side*(peak-.0096),cy-.0025,z0-.0049])
    patch.extend([[prev[k],prev[(k+1)%n],prev[(k+2)%n],concha] for k in range(0,n,2)])
    selected=set(ids.tolist()); keep=[i for i in range(len(f)) if i not in selected]
    stat=dict(side=side,root_loop=n,rings=len(steps),removed_faces=len(ids),new_quads=len(patch))
    return np.vstack([v,ext]),[f[i] for i in keep]+patch,keep,stat,list(range(len(v),len(v)+len(ext)))


def candidates(v,f,profile,face_data,idx,side,high,protected=()):
    z=profile.z(face_data[0][1])-.015
    options=sorted(bases(v,f,EAR_Y[idx],z,side,high,protected),key=lambda a:a[0])
    for record in options[:16]:
        yield ear_rings(v,f,idx,side,high,record)
