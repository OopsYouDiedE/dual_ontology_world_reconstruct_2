"""Anatomical surface modelling in local limb and trunk cross-sections.

Each vertex stays on its own character. Individual muscle envelopes move the
actual cage on front, lateral and rear planes, then taper into joint landmarks.
All coordinates are normalized by bare height; front is -Y.
"""
import numpy as np
from anatomy_geometry import G, cross_section, smooth, surface_normals
from tripo_surface import adjacency, tris

# upper-arm muscularity, waist definition, leg muscularity
SHAPE=[(.79,.83,.87),(.64,.78,.78),(1.28,1.13,1.24),(.91,.47,.85),(1.32,1.10,1.27),(.50,.48,.60),(.83,.84,.86)]
ARM_Z=[(.675,.548),(.683,.550),(.695,.555),(.686,.545),(.684,.547),(.680,.543),(.685,.543)]


def limb_sections(v,f,levels,side,arm):
    """Section centroids and half-widths, measured on the actual left/right cage."""
    result=[]; edge=v[np.array(list(adjacency(f)))]
    for z in levels:
        p=cross_section(edge,z)
        if not len(p):continue
        x=side*p[:,0]
        if arm:
            reach=x.max(); width=.074 if z>.73 else .057
            if reach<.113:continue
            use=p[x>reach-width]
        else:
            use=p[(x>.006)&(x<.153)]
        if len(use)<4:continue
        xx=side*use[:,0];yy=use[:,1]
        minx,maxx=np.quantile(xx,[.06,.94]);miny,maxy=np.quantile(yy,[.06,.94])
        result.append([z,(maxx+minx)*.5,(maxy+miny)*.5,max(.012,(maxx-minx)*.5),max(.012,(maxy-miny)*.5)])
    return np.asarray(result)


def axis_points(u,axis,side,n):
    x,y,z=u.T;ax=x*side
    cx,cy,rx,ry=[np.interp(z,axis[:,0],axis[:,i]) for i in range(1,5)]
    a=(ax-cx)/rx;b=(y-cy)/ry; theta=np.arctan2(b,a)
    # Limit application to the selected limb. Angular measures on the front,
    # back and side remain valid for an asymmetric A-pose and sculpt.
    gate=(x*side>0)*(1-smooth(1.15,1.65,np.sqrt(a*a+b*b)))
    plane=n.copy();plane[:,2]*=.19
    return theta,gate,plane


def arc(theta,direction,width):
    return np.exp((np.cos(theta-direction)-1)/(width*width))


def envelope(z,lower,upper,peak,width):
    return G((z-peak)/width)*smooth(lower,lower+width*.62,z)*(1-smooth(upper-width*.45,upper,z))


def local_safety(v,u,f):
    """Back off only badly folded triangles. Then Blender checks real self-contact."""
    t=tris(f);a,b,c=v[t].transpose(1,0,2); old=np.cross(b-a,c-a)
    w=(old*old).sum(1); valid=w>1e-18;t=t[valid];old=old[valid];w=w[valid]
    d=u-v; weight=np.ones(len(v)); q=v.copy()
    for _ in range(20):
        q=v+d*weight[:,None];a,b,c=q[t].transpose(1,0,2)
        ratio=(np.cross(b-a,c-a)*old).sum(1)/w
        bad=ratio<.33
        if not bad.any():return q,int(np.count_nonzero(weight<1))
        ids=np.unique(t[bad]);flag=np.zeros(len(v),dtype=bool);flag[ids]=True
        near=np.unique(t[np.any(flag[t],axis=1)]);weight[near]*=.91;weight[ids]*=.63
    # Recheck adjacent triangles each time we revert a remaining sliver.
    # Every pass freezes at least one vertex; with the original coordinates,
    # every valid face has area ratio 1, so the process terminates.
    while True:
        ids=np.unique(t[bad])
        weight[ids]=0.
        q[ids]=v[ids]
        a,b,c=q[t].transpose(1,0,2)
        bad=(np.cross(b-a,c-a)*old).sum(1)<.33*w
        if not bad.any():return q,int(np.count_nonzero(weight<1))


def build_body(v,f,p,idx,strength=1.):
    u=np.array(v,copy=True);x,y,z=u.T;ax=np.abs(x)
    n=surface_normals(v,f); front=smooth(.07,.75,-n[:,1]);back=smooth(.08,.78,n[:,1]);sidewall=smooth(.12,.80,abs(n[:,0]))
    upper,waist,legs=SHAPE[idx];sh=p.z(p.shoulder);cl=p.z(p.notch);pit=p.z(p.pit);wa=p.z(p.waist)
    hip=p.z(p.crotch);knee=p.z(p.knee);ank=p.z(p.ankle);span=p.x(p.shoulder_x)
    a=ax/span
    d=np.zeros_like(v)
    # Pectoral mass is a fan from sternum / medial clavicle to humeral
    # insertion. Oblique lower fibers form an anterior axillary fold.
    shelf=pit-.015+.046*np.minimum(a,1.18)**1.82+.012*G(ax/.022)
    zmax=cl-.011-.027*a
    pec_gate=smooth(.013,.037,ax)*(1-smooth(.86,1.19,a))*smooth(-.006,.013,z-shelf)*(1-smooth(zmax-.027,zmax+.003,z))
    pec_full=G((a-.52)/.51)*G((z-shelf-.021)/.050)
    if idx!=5:
        # Trim inherited point-like protrusions before laying in the plane.
        # The nearest upper and lower slices give a reference depth relative
        # to this individual's ribcage, rather than a shared torso thickness.
        edge=v[np.array(list(adjacency(f)))]; rim_depth=[]
        for t in (pit-.062,cl-.036):
            pane=cross_section(edge,t)
            yy=pane[(np.abs(pane[:,0])>span*.21)&(np.abs(pane[:,0])<span*.70),1]
            rim_depth.append(float(np.quantile(yy,.20)) if len(yy)>3 else -.05)
        t=np.clip((z-(pit-.062))/(cl-.036-(pit-.062)),0,1)
        rib_plane=(1-t)*rim_depth[0]+t*rim_depth[1]
        delta=rib_plane-y
        broad=G((a-.50)/.35)*G((z-pit+.005)/.036)
        d[:,1]+= np.minimum(.019,np.maximum(0,delta-.015)*.87)*broad*front
        d[:,1]-=.0085*upper*pec_gate*pec_full*front
        d[:,1]+=.0025*upper*G((z-shelf+.006)/.015)*G((a-.55)/.43)*front
    else:
        # A broad chest plane and side wrap support the existing soft-tissue
        # volume without copying the strong male pectoral crease.
        d[:,1]-=.0030*pec_gate*pec_full*front
        d[:,1]-=.0028*G((a-.58)/.35)*G((z-(pit-.039))/.045)*front
    # Deltopectoral groove runs obliquely inward as the arm descends.
    slit=span*(.74+(.87*(z-(pit+.015))))+.48*np.maximum(sh-.021-z,0)
    dg=G((ax-slit)/.008)*G((z-(sh-.040))/.052)
    d[:,1]+=.0048*upper*dg*front
    # Serratus/obliques share a diagonal plane rather than rows of pasted blobs.
    rib_end=wa+.085+.039*G((a-.29)/.4)
    rib=G((z-rib_end)/.012)*G((a-.61)/.37)
    d[:,1]-=.0055*waist*rib*front
    x_waist=p.x(p.waist_x)
    oblique_axis=x_waist-.024+.29*(z-wa+.028)
    waistplane=G((ax-oblique_axis)/.013)*G((z-(wa+.012))/.067)
    d[:,1]-=.0065*waist*waistplane*front
    # Pelvis has a crest, then a sidewall dip before the upper thigh.
    crest=wa-.036+.018*smooth(.05,.105,ax)
    iliac=G((z-crest)/.012)*smooth(.043,.065,ax)*(1-smooth(.104,.125,ax))
    side=np.sign(x)
    d[:,0]+=side*sidewall*.0063*waist*iliac
    d[:,0]-=side*sidewall*.0041*waist*G((z-crest+.022)/.014)*G((ax-.089)/.027)
    d[:,1]-=.0035*waist*front*G((ax-.066)/.017)*G((z-crest)/.014)
    abdominal=G((z-(wa+.040))/.06)*G((a-.24)/.32)
    d[:,1]-=.0037*waist*abdominal*front
    # Lats flare below the rear armhole; lumbar mass narrows toward the pelvis.
    lat=G((ax-(span*.72-.252*np.maximum(sh-z,0)))/.024)*G((z-(pit-.05))/.074)
    d[:,1]+=.0107*upper*lat*back
    d[:,0]+=side*.0040*upper*lat*back*sidewall
    spinal=G((ax-.025)/.015)*G((z-(wa+.041))/.080)
    d[:,1]+=.0076*waist*spinal*back
    # Posterior pelvic mass and off-centre hip insertion of the lateral thigh.
    glute=G((ax-.059)/.037)*G((z-(hip+.052))/.049)
    d[:,1]+=.0073*legs*glute*back
    e,wrist=ARM_Z[idx]
    for sn in (-1,1):
        arm=limb_sections(v,f,np.linspace(wrist-.025,sh,22),sn,True)
        if len(arm)>6:
            th,g,plane=axis_points(v,arm,sn,n);reach=sn*x
            arm_gate=g*smooth(span*.89,span*1.17,reach)*smooth(wrist-.020,wrist+.006,z)*(1-smooth(sh-.006,sh+.018,z))
            # The deltoid wraps over the humeral head and tapers into the arm.
            delt=envelope(z,e+.044,sh+.023,sh-.035,.040)*arc(th,-.07,.97)
            biceps=envelope(z,e-.008,sh-.046,e+.062,.053)*arc(th,-1.73,.70)
            triceps=envelope(z,e-.007,sh-.039,e+.074,.061)*(arc(th,1.33,.62)+.36*arc(th,2.50,.55))
            # Brachioradialis crosses the transition from lateral elbow to front wrist.
            u_fore=np.clip((z-wrist)/(e-wrist),0,1)
            brachio=envelope(z,wrist-.003,e+.026,e-.045,.057)*arc(th,-1.15+1.58*u_fore,.57)
            flex=envelope(z,wrist+.005,e+.012,e-.052,.048)*arc(th,-2.14,.65)
            ext=envelope(z,wrist+.012,e+.038,e-.049,.054)*arc(th,1.44,.66)
            joint=G((z-e)/.017)*arc(th,1.64,.52)
            notch=G((z-e-.002)/.011)*arc(th,-1.3,.64)
            amount=.0103*delt+.0124*biceps+.0096*triceps+.0108*brachio+.0054*flex+.0050*ext+.0050*joint-.0040*notch
            d+=plane*(upper*amount*arm_gate)[:,None]
        leg=limb_sections(v,f,np.linspace(ank-.004,hip+.065,28),sn,False)
        if len(leg)>8:
            th,g,plane=axis_points(v,leg,sn,n)
            g*=smooth(ank-.005,ank+.015,z)*(1-smooth(hip+.059,hip+.098,z))
            # Medial quad forms the teardrop lower than the lateral quad.
            med=envelope(z,knee-.008,hip+.020,knee+.041,.041)*arc(th,-2.30,.54)
            out=envelope(z,knee+.007,hip+.046,knee+.107,.094)*arc(th,-.61,.66)
            rect=envelope(z,knee+.016,hip+.044,knee+.115,.084)*arc(th,-1.51,.52)
            ham=envelope(z,knee-.001,hip+.039,knee+.094,.075)*(arc(th,1.08,.65)+.65*arc(th,2.27,.62))
            pat=G((z-knee)/.016)*arc(th,-1.56,.56)
            crease=G((z-knee+.022)/.010)*arc(th,-1.57,.47)
            shin=envelope(z,ank+.011,knee-.008,knee-.083,.071)*arc(th,-1.45,.35)
            gast_m=envelope(z,ank+.022,knee-.017,knee-.090,.052)*arc(th,2.00,.65)
            gast_l=envelope(z,ank+.030,knee-.014,knee-.071,.048)*arc(th,.83,.58)
            ach=envelope(z,ank-.001,knee-.126,ank+.057,.037)*arc(th,1.54,.34)
            total=.0090*med+.0108*out+.0095*rect+.0094*ham+.0070*pat-.0034*crease+.0082*shin+.0102*gast_m+.0089*gast_l+.0048*ach
            d+=plane*(g*legs*total)[:,None]
    # Keep the silhouette readable on slim characters; do not move head, fingers or soles.
    d*=((1-smooth(cl+.009,cl+.031,z))*smooth(.035,.059,z))[:,None]
    # Fade out around the medial branch where the legs and pelvis join.
    # Independent limb section axes are unstable close to that branch.
    medial=(1-smooth(.030,.052,ax))*smooth(hip-.046,hip-.027,z)*(1-smooth(hip+.040,hip+.072,z))
    d*=(1-medial)[:,None]
    # The existing outline is already registered to the concept sheet. Sculpt
    # depth freely; taper excessive lateral expansion to keep the character's
    # front-view widths and the distinct spacing of limbs.
    d[:,0]=.0045*np.tanh(d[:,0]/.0056)
    u,limited=local_safety(v,v+strength*d,f)
    disp=np.linalg.norm(u-v,axis=1)
    return u,dict(peak_pct_h=float(100*disp.max()),p95_pct_h=float(100*np.quantile(disp,.95)),
                  vertices_over_002h=int((disp>.002).sum()),locally_limited=limited)
