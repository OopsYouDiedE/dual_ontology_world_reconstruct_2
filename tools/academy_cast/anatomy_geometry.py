"""Landmark-led anatomy sculpt over each character's own cage, without a donor mesh.

X left/right, -Y front, Z up. All distances normalized by crown-to-sole height.
Reference pixels are measured on the supplied 1248x1082 character lineup.
"""
from pathlib import Path
from dataclasses import dataclass
import sys,json
import numpy as np
from scipy.interpolate import PchipInterpolator
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/academy_cast'))
from tripo_surface import tris, unit, silhouette, CAST
from anatomy_projection import apply_warp, front_warp, iou, mesh_mask, overlay, reference_mask

@dataclass
class Profile:
    center:int; crown:int; foot:int; chin:int; notch:int; shoulder:int; pit:int; waist:int; crotch:int; knee:int; ankle:int
    shoulder_x:int; waist_x:int; hip_x:int; knee_x:int; calf_x:int; ankle_x:int
    crop:tuple; upper:float; definition:float; chin_width:float; brow_angle:float
    def z(self,pix):return (self.foot-pix)/(self.foot-self.crown)
    def x(self,pix):return (pix-self.center)/(self.foot-self.crown)

# Landmarks taken per character, rather than imposing a lineup-wide head or body ratio.
PROFILES=[
 Profile(162,95,486,155,173,180,207,257,305,359,462,202,192,198,186,187,193,(19,92,307,489),.88,.80,.99,.071),
 Profile(469,103,487,149,165,173,202,246,295,348,460,507,495,505,491,495,498,(332,99,608,489),.78,.79,.94,.114),
 Profile(779,92,487,137,153,165,194,245,302,357,460,827,814,822,807,806,813,(636,88,922,489),1.36,1.23,1.11,.025),
 Profile(161,609,986,655,670,682,713,757,805,865,959,207,203,207,191,192,195,(28,605,297,989),.94,.82,1.04,.032),
 Profile(469,585,986,632,650,663,691,739,799,850,958,518,504,512,498,501,504,(326,581,616,989),1.31,1.24,1.08,.088),
 Profile(778,631,987,675,689,696,721,761,811,865,961,811,803,814,797,802,807,(649,626,908,989),.43,.50,.92,.036),
 Profile(1085,589,987,638,655,667,693,741,791,846,958,1128,1116,1123,1108,1111,1117,(945,584,1228,989),.97,.92,.91,.103),
]
# Pixel annotations from the supplied lineup. At this scale pupil/crease picks
# carry roughly +/- 1px of uncertainty. No sagittal depth is inferred here.
# left & right pupils, lip line height, lip width, nose tip height.
FACE=[
    ((152,123),(171,123),143,11,136),
    ((462,123),(477,123),139,9,135),
    ((770,113),(788,113),127,11,122),
    ((153,632),(169,632),644,12,639),
    ((461,606),(477,606),619,10,614),
    ((770,651),(787,651),665,9,661),
    ((1077,615),(1093,615),629,10,624),
]

# Old cage annotations from the source-orthographic ruler. Absolute widths below
# come from slicing each individual old cage, never from a shared silhouette.
SOURCE=[(.790,.770,.738,.583,.452,.307,.077),(.827,.802,.749,.603,.475,.314,.074),
        (.825,.799,.741,.574,.456,.311,.076),(.830,.802,.750,.578,.444,.295,.076),
        (.835,.806,.761,.581,.455,.311,.077),(.828,.805,.752,.572,.462,.303,.074),
        (.830,.802,.758,.598,.478,.316,.077)]


def smooth(a,b,x):
    t=np.clip((x-a)/(b-a),0,1);return t*t*(3-2*t)


def G(t):return np.exp(-np.minimum(t*t,100))


def lerp(a,b,t):return a+(b-a)*t


def arms_gate(ax,z,sh):
    return smooth(.13,.18,ax)*smooth(.38,.48,z)*(1-smooth(sh,sh+.045,z))


def cross_section(edges,z):
    e=edges[(edges[:,0,2]<z)!=(edges[:,1,2]<z)]
    a,b=e.transpose(1,0,2)
    if len(a)==0:return np.empty((0,3))
    return a+(b-a)*((z-a[:,2])/(b[:,2]-a[:,2]))[:,None]


def surface_normals(v,f):
    t=tris(f);a,b,c=v[t].transpose(1,0,2);n=np.cross(b-a,c-a);out=np.zeros_like(v)
    for j in range(3):np.add.at(out,t[:,j],n)
    return unit(out)


class Build:
    def __init__(self,d,idx):
        self.i=idx;self.p=PROFILES[idx];self.d=d
        self.v=np.array(d['v']);self.f=d['f']
        head_chin=d['report']['chin_height_pct_h']/100
        q=self.p
        self.target_chin=(1-1/6.5) if idx==0 else q.z(q.chin)
        self.s=np.array(SOURCE[idx]);self.neck,self.sh,self.pit,self.wa,self.cr,self.kn,self.an=self.s
        target=np.array([q.z(k) for k in (q.notch,q.shoulder,q.pit,q.waist,q.crotch,q.knee,q.ankle)])
        self.t=target;self.tn,self.ts,self.tp,self.tw,self.tc,self.tk,self.ta=target
        # Enforce crown, annotated chin and ankle/knee/hip landmarks smoothly. The arm
        # uses an independent monotone Z map so leg adjustments cannot move hands.
        self.z=PchipInterpolator(np.r_[0,self.s[::-1],head_chin,1],np.r_[0,target[::-1],self.target_chin,1])
        self.armz=PchipInterpolator([.32,.45,.55,self.sh,.88,1],[.32,.45,.55,self.ts,.88,1])
        E=list({(min(a,b),max(a,b)) for g in self.f for a,b in zip(g,g[1:]+g[:1])})
        self.edges=self.v[E]
        # Torso curves from intersections, sampled far enough below the armpit that the limb is disconnected.
        wnodes=[self.cr-.025,self.cr+.055,self.wa,self.pit-.025,self.sh+.005,self.neck,head_chin,1.]
        spans=[]
        for z,limit in [(self.cr+.060,.154),(self.wa,.138),(self.pit-.025,.142)]:
            pts=cross_section(self.edges,z);ax=np.abs(pts[:,0]); candidates=ax[ax<limit]
            spans.append(float(candidates.max()))
        waist=np.clip(q.x(q.waist_x)/spans[1],.76,1.12)
        hip=np.clip(q.x(q.hip_x)/spans[0],.80,1.16)
        chest=np.clip((q.x(q.shoulder_x)*.93)/spans[2],.83,1.16)
        self.width=PchipInterpolator(wnodes,[hip,hip,waist,chest,1.,.92,.89,1.]).__call__
        # Shape the leg widths and adjust stance with independent knee, calf and ankle alignment.
        self.legz=np.array([0,self.an,self.kn-.078,self.kn,self.cr-.042,self.cr+.075])
        self.old_center=[];self.old_width=[]
        for z in self.legz[:-1]:
            P=cross_section(self.edges,max(.009,z));Q=P[(P[:,0]>.008)&(P[:,0]<.164)]
            self.old_center.append(float((Q[:,0].min()+Q[:,0].max())*.5));self.old_width.append(float(np.ptp(Q[:,0])*.5))
        self.old_center.append(self.old_center[-1]);self.old_width.append(self.old_width[-1]);
        self.center=PchipInterpolator(self.legz,self.old_center)
        ac,kc,cc=[q.x(k) for k in (q.ankle_x,q.knee_x,q.calf_x)]
        center=np.array([ac+.004,ac,cc,kc,kc*.89,self.old_center[-1]])
        self.wantc=PchipInterpolator(self.legz,lerp(self.old_center,center,.82))
        # Narrow toward ankle and knee; keep the actual strength of this person's quadriceps.
        calf= [.86,.96,.89,.94,.93,.95,.93][idx]
        kfactor=[.97,.94,.93,.90,.91,.94,.92][idx]
        self.widthleg=PchipInterpolator(self.legz,[.9,.88,calf,kfactor,1.,1.])
        ec=np.array([np.array(e['v'])[-2:].mean(0) for e in d['eyes']])
        self.old_eye_z=float(ec[:,2].mean())
        self.eyes0=ec; self.base_eyes=self.proportions(ec)
        r=np.array(d['loops']['2']['rim']); rim=self.proportions(self.v[r])
        self.base_lip=rim.mean(0)
        l,e,m,span,nose=FACE[idx]
        self.paint_eyes=np.array([[q.x(xx),q.z(zz)] for xx,zz in (l,e)])
        # Use a monotone facial height mapping anchored at the preserved chin and crown.
        self.face_z=PchipInterpolator([self.target_chin,self.base_lip[2],self.base_eyes[:,2].mean(),1],
                                      [self.target_chin,q.z(m),self.paint_eyes[:,1].mean(),1])
        self.mouth_scale=np.clip(span/(q.foot-q.crown)/np.ptp(rim[:,0]),.84,1.26)
        self.nasal_tip=q.z(nose)
        self.eye_r=np.array([np.linalg.norm(np.array(e['v'])[-1]-np.array(e['v'])[-2])/1.72 for e in d['eyes']])
        self.eyes=self.face_proportions(self.base_eyes)
        self.lip=self.face_proportions(self.base_lip[None,:])[0]

    def face_proportions(self,u):
        p=u.copy(); x,y,z=u.T
        frontal=(1-smooth(-.018,.018,y))*(1-smooth(.042,.056,abs(x)))
        plane=smooth(self.target_chin-.015,self.target_chin+.010,z)
        # The original side/rear skull does not move to follow image features.
        low_lip=(1-smooth(.026,.038,abs(x-self.base_lip[0])))*G((z-self.base_lip[2])/.012)
        p[:,0]+=(x-self.base_lip[0])*(self.mouth_scale-1)*low_lip*frontal
        p[:,2]=lerp(z,self.face_z(np.clip(z,self.target_chin,1)),frontal*plane)
        for j,(cx,_,zz) in enumerate(self.base_eyes):
            px=self.paint_eyes[j,0]
            xz=G((x-cx)/.013)*G((z-zz)/.015)*frontal
            p[:,0]+=np.clip(px-cx,-.007,.007)*xz
            # Ward and Shen had tiny squint-like apertures in the base mesh.
            amount=[.05,.12,.34,.28,.22,.14,.13][self.i]
            p[:,2]+=(z-zz)*amount*xz
        return p

    def proportions(self,v):
        u=v.copy();x,y,z=v.T; ax=np.abs(x)
        # Region boundary tracks the empty gap below the arm pit. No hip vertices
        # can be swept by the arm mapping. Foot and hand tips remain attributed.
        cut=.118+.21*np.clip(self.sh-z,0,.37)
        arms=smooth(-.015,.026,ax-cut)*smooth(.29,.40,z)*(1-smooth(self.sh+.012,self.sh+.052,z))
        u[:,2]=lerp(self.z(z),self.armz(z),arms)
        torso=smooth(self.cr-.065,self.cr+.06,z)*(1-smooth(self.neck+.007,self.target_chin+.030,z))
        u[:,0]*=lerp(1.,self.width(np.clip(z,self.cr-.025,1.)),torso*(1-arms))
        # Reduce lower neck trapezius breadth subtly, before placing clavicles.
        narrow=G((z-(self.neck+.019))/.022)*smooth(.805,self.neck+.021,z)
        u[:,0]*=(1-narrow*(.052 if self.i in (2,3,4) else .03))
        leg=(1-smooth(self.cr-.035,self.cr+.053,z))*(1-arms)
        zz=np.clip(z,self.legz[0],self.legz[-1]);a=self.center(zz); b=self.wantc(zz); w=self.widthleg(zz)
        n=np.sign(x)*(b+(ax-a)*w)
        u[:,0]=lerp(u[:,0],n,leg)
        # Different jaw profiles. Cranial silhouette stays broad above the orbit.
        head=smooth(self.d['report']['chin_height_pct_h']/100-.011,self.old_eye_z-.012,z)*(1-smooth(self.old_eye_z-.025,self.old_eye_z+.008,z))
        u[:,0]*=lerp(1.,self.p.chin_width,head)
        return u

    def sculpt(self,u,f):
        """Layer the visible bones and muscle masses as actual vertex coordinates."""
        v=u.copy();x,y,z=u.T; ax=np.abs(x); ny=surface_normals(u,f)[:,1]
        wf=smooth(.04,.78,-ny); wb=smooth(.07,.83,ny)
        s=surface_normals(u,f)
        n,sh,pit,wa,cr,knee,ank=self.t
        prof=self.p; chestc=prof.x(prof.shoulder_x); shoulder_amp=.52*prof.upper
        # Primary plane of the sternum and pecs, with the outer lower edge running to the humeral insertion.
        axc=ax/max(.083,chestc)
        lower=sh-.079+.048*np.minimum(axc,1.3)**2+.010*G(ax/.022)
        patch=smooth(-.006,.008,z-lower)*G((z-lower-.017)/.038)
        lateral=smooth(.009,.028,ax)*(1-smooth(chestc*.86,chestc*1.13,ax))
        pec=.0148*prof.upper*patch*lateral*wf
        if self.i==5:pec*=.18
        if self.i in (2,4):pec*=.76
        v[:,1]-=pec
        v[:,1]+=.0032*prof.definition*G((z-lower+.009)/.012)*lateral*wf*(self.i!=5)
        # Sternoclavicular notch rises outward. A compact ridge above a shallow
        # infraclavicular hollow reveals the plane turn with the same material.
        c_z=n-.005+ax*.116-.012*(ax/max(.083,chestc))**2
        c_x=smooth(.006,.014,ax)*(1-smooth(chestc*.79,chestc*1.03,ax)); cl=G((z-c_z)/.0075)
        v[:,1]-= (.0061*cl-.0025*G((z-c_z+.011)/.009))*c_x*wf
        v[:,1]+= .0040*G(ax/.014)*G((z-n+.003)/.011)*wf
        # Sternocleidomastoid: wide at the ear side, narrow at the sternum.
        nt=np.clip((z-n)/max(self.target_chin+.021-n,.028),0,1)
        scm_x=lerp(.013,.034,nt)
        v[:,1]-=.0042*G((ax-scm_x)/.010)*np.sin(np.pi*nt)*wf
        # Iliac crest is a side-facing plane, with a soft inclination into the waist.
        il=G((z-(wa-.038+(.045*(ax-.045))))/.014)*G((ax-.076)/.021)
        v+=s*(.0054*prof.definition*il*(1-arms_gate(ax,z,sh)))[:,None]
        # Deltoid cap fades to a tapered insertion on the lateral upper arm.
        dz=sh-.016; delx=chestc*1.04+.53*np.maximum(sh-z,0)
        delt=G((ax-delx)/.033)*G((z-dz)/.048)*smooth(chestc*.67,chestc*.96,ax)
        v+=s*(.0093*shoulder_amp*delt)[:,None]
        # Biceps and forearm are shaped as tapering masses with the wrist defined by a constriction.
        upper_gate=smooth(.115,.178,ax)
        biceps=G((z-(sh-.116))/.051)*G((ax-(chestc+.054+.48*np.maximum(sh-.12-z,0)))/.058)*upper_gate
        v[:,1]-= .0077*prof.upper*biceps*wf
        wrist=G((z-.536)/.022)*smooth(.184,.233,ax)
        v-=s*(.0030*wrist)[:,None]
        fore=G((z-(sh-.211))/.047)*G((ax-(chestc+.103))/.045)*arms_gate(ax,z,sh)
        v+=s*(.0052*prof.upper*fore)[:,None]
        # Rib cage arch, outer obliques and a soft rectus plane. No transverse 'six pack' engraving.
        arc=sh-.145+.033*G(ax/.039); rib=G((z-arc)/.012)*smooth(.017,.038,ax)*(1-smooth(.071,.101,ax));
        v[:,1]-= .0040*prof.definition*rib*wf
        abd=G((z-(wa+.052))/.069)*(1-smooth(.044,.076,ax))
        v[:,1]-= .0045*prof.definition*abd*wf
        v[:,1]+= .0028*prof.definition*G(ax/.010)*G((z-(wa+.065))/.070)*wf
        flank=G((ax-(.052-.009*G((z-wa)/.035)))/.012)*G((z-wa-.025)/.055)
        nav=G(ax/.0045)*G((z-wa-.044)/.0042)
        v[:,1]+=wf*(.0038*prof.definition*flank+.0054*nav)
        # Reflected-light boundary below the rib cage: only on the sturdier builds.
        if self.i in (2,4):
            row=wa+.080+.016*G(ax/.033)
            ab_sep=G((z-row)/.007)*G((ax-.035)/.020)
            v[:,1]+=wf*.0035*ab_sep
        # Shoulder blade and lat planes on the back, subtler than the frontal relief.
        v[:,1]+= wb*(.0048*prof.upper*G((ax-.064)/.025)*G((z-(sh-.07-ax*.12))/.044)+
                     .0039*prof.upper*G((ax-.076)/.026)*G((z-(sh-.14))/.077))
        # Knee cap, tibial crest, and the different heights of the ankle bones.
        leg_x=np.interp(z,[0,ank,knee-.075,knee,cr],[prof.x(prof.ankle_x),prof.x(prof.ankle_x),prof.x(prof.calf_x),prof.x(prof.knee_x),prof.x(prof.knee_x)*.88]);lx=ax-leg_x
        pat=G((lx+.003)/.0145)*G((z-knee)/.018)
        tib=G((lx+.002)/.0105)*smooth(ank+.023,ank+.065,z)*(1-smooth(knee-.044,knee-.013,z))
        # The V above the kneecap comes from quadriceps masses, and the
        # calf sits behind the shin. Keep their peaks off the same height.
        med=G((lx+.014)/.012)*G((z-knee-.036)/.032)
        lat=G((lx-.018)/.017)*G((z-knee-.058)/.049)
        v[:,1]-= wf*prof.definition*(.0120*pat+.0060*tib+.0105*med+.0080*lat)
        v[:,1]+= wb*prof.definition*.0068*G(lx/.035)*G((z-knee+.082)/.055)
        v[:,1]+= wb*.0047*G(lx/.011)*G((z-ank-.018)/.039)
        v[:,1]+= wf*prof.definition*(.0041*G((lx-.022)/.010)*G((z-knee)/.021)+.0034*G((lx+.020)/.009)*G((z-knee)/.017))
        bone_hi=G((z-ank-.007)/.010)*G((lx+.019)/.014)
        bone_lo=G((z-ank+.006)/.012)*G((lx-.015)/.014)
        v[:,0]+=np.sign(x)*(.0046*bone_lo-.0035*bone_hi)
        # Raise the inside plantar arch, between the forefoot and heel.
        # Use each foot's own sagittal range (tips differ by pose). Wedge
        # height drops across the metatarsals and steps up into the instep.
        for sign in (-1,1):
            q=(x*sign>0)&(z<.031)
            if q.sum()<4: continue
            a,b=np.quantile(y[q],[.05,.93]); span=max(b-a,.032)
            foot=np.clip((y-a)/span,0,1)
            arch=(1-smooth(.014,.041,z))*G((foot-.49)/.23)*G((lx+.014)/.020)*smooth(0,.006,z)
            v[q,2]+=(.014*arch)[q]
            local=(x*sign>0)*(1-smooth(.025,.066,z))
            v[:,2]-=local*.0080*G((foot-.14)/.16)*smooth(.006,.032,z)
            v[:,2]+=local*.0060*G((foot-.49)/.19)*smooth(.009,.035,z)
            v[:,1]+=(x*sign>0)*.004*smooth(.014,.034,z)*(1-smooth(.043,.071,z))*G((foot-.88)/.15)
            # Carve toe creases only on the distal forefoot, fading before joints.
            # The original cage still determines which digits are individually separable.
            toe=(1-smooth(.067,.24,foot))*(1-smooth(.018,.037,z))*(x*sign>0)
            toe_marks=sum(G((lx-pos)/.0030) for pos in [-.010,.002,.012,.020])
            v[:,1]+=.0055*toe*toe_marks
        v[:,2]=np.maximum(v[:,2],0)
        # Existing wrists are slightly asymmetric. Estimate the local palm
        # axes separately from each last hand region; sculpt the metacarpal
        # plane, knuckle row and thenar mass without joining digit islands.
        for sign in (-1,1):
            reach=sign*x
            hand=(reach>.215)&(z>.40)&(z<.60)
            if hand.sum()<12:continue
            pts=u[hand]; anchor=np.quantile(pts[:,2],.76)
            mid=pts[(pts[:,2]>=anchor-.024)&(pts[:,2]<=anchor+.004)]
            if len(mid)<4:continue
            center=np.median(mid,axis=0)
            hand_span=max(.045,float(center[2]-np.quantile(pts[:,2],.04)))
            d=np.clip((center[2]-z)/hand_span,0,1.45)
            lat=reach-sign*center[0]-.49*(center[2]-z)
            pad=smooth(.204,.238,reach)*smooth(.39,.44,z)*(1-smooth(center[2]+.005,center[2]+.025,z))
            mound=.0037*G((lat+.007)/.012)*G((d-.27)/.29)
            knuckles=.0031*G((d-.57-lat*3)/.14)*G(lat/.023)
            tendon=.0022*G((lat-.007)/.006)*G((d-.28)/.27)
            v[:,1]+=pad*(wb*(mound+.76*knuckles)-wf*(knuckles+tendon))
        # Orbital shelf, cheekbone, malar slope, and nasal bridge. Bound the
        # corrections outside the eyelid rim, so eyeballs stay independent.
        for j,eye in enumerate(self.eyes):
            cx,_,zz=eye;r=self.eye_r[j]; ex=x-cx
            rad=np.sqrt((ex/(r*1.27))**2+((z-zz)/(r*.93))**2); fence=smooth(.70,1.45,rad)
            ridge=G(ex/(r*1.45))*G((z-(zz+r*1.09-prof.brow_angle*ex*np.sign(cx)))/(.0068 if self.i!=5 else .006))
            suborbit=G(ex/(r*1.12))*G((z-zz-r*.45)/.0063)
            cheek=G((ex-np.sign(cx)*r*.48)/(r*1.22))*G((z-zz+r*1.54)/.014)
            v[:,1]-= wf*fence*(.0078*prof.definition*ridge-.0035*suborbit+.0070*prof.definition*cheek)
            malar=G((ex-np.sign(cx)*r*.70)/(r*1.38))*G((z-zz+r*2.04)/.010)
            v[:,1]+=.0047*prof.definition*wf*fence*malar
        ey=float(self.eyes[:,2].mean()); n_tip=self.nasal_tip
        bridge_width=.0108 if self.i not in (1,6) else .0088
        nose=G(ax/bridge_width)*smooth(n_tip-.006,n_tip+.008,z)*(1-smooth(ey+.003,ey+.030,z))
        tip=G(ax/(bridge_width*1.16))*G((z-n_tip)/.009)
        v[:,1]-=wf*(.0090*nose+.0062*tip)
        alar=G((ax-bridge_width*.95)/.006)*G((z-n_tip+.0025)/.006)
        v[:,1]-=wf*.0044*alar
        v[:,1]+=wf*.0048*G((ax-bridge_width*.64)/.0036)*G((z-n_tip+.007)/.0037)
        # Lip relief is traced from the preserved opening, not by darkening the outside skin.
        x0,_,z0=self.lip
        dx=x-x0
        w=(1-smooth(.011,.023,abs(dx)))
        cupid=z0+.0052+.0016*G((abs(dx)-.007)/.003)
        upper_lip=w*G((z-cupid)/.0035)
        lower_lip=w*G((z-z0+.0051)/.0042)
        fold=w*G((z-z0+.014)/.006)
        v[:,1]-=wf*(.0030*upper_lip+.0037*lower_lip-.0027*fold)
        # Ear turns around the maxillary plane. Work only on the existing lateral shell.
        ear_h=ey-.021; ear_x=.042 if self.i!=0 else .052
        ear=smooth(ear_x-.008,ear_x+.006,ax)*G((z-ear_h)/.017)*G((y+.001)/.025)
        # Outer helix and inner concha in the sagittal plane, keeping the
        # pre-existing ear attached to the head with its own profile.
        ey_local=[.018,.016,.017,.014,.002,.007,.010][self.i]
        ez=ey-.015
        es=np.sqrt(((y-ey_local+(z-ez)*.19)/.011)**2+((z-ez)/.022)**2)
        outer=smooth(ear_x-.007,ear_x+.003,ax)
        helix=.0050*G((es-1)/.29)-.0064*G(es/.70)
        v[:,0]+=np.sign(x)*(outer*helix+.0014*ear)
        # A shallow groove in front of the root gives the front view its
        # cheek-to-tragus boundary without painting a line on the skin.
        v[:,1]+=.0046*outer*G((y-ey_local+.013)/.009)*G((z-ez+.002)/.020)
        v[:,1]-=.0016*ear*G((z-ear_h-.007)/.008)
        # Two larger jaw planes before small chin detail; keep the jaw width from the reference.
        chin_z=self.target_chin+.021
        jaw=G((z-chin_z)/.021)*G((ax-(.038 if self.i in (2,4) else .029))/.015)
        v[:,1]-=wf*.0044*prof.definition*jaw
        # The underside of the mandibular body recedes, separating head and neck in side light.
        jaw_edge=self.target_chin+.052*np.clip(ax/.047,0,1)**1.35
        trough=G((z-jaw_edge+.004)/.009)*smooth(.014,.026,ax)*(1-smooth(.048,.061,ax))
        v[:,1]+=.0048*prof.definition*trough*wf
        chin=G((z-self.target_chin-.008)/.011)*G(ax/.015)
        v[:,1]-=wf*.0031*chin
        return v

    def eyebrows(self,v,f):
        meshes=[]
        for i,eye in enumerate(self.eyes):
            cx,_,zz=eye;r=self.eye_r[i]; sg=np.sign(cx)
            ctrl=np.array([-1.,-.74,-.34,.12,.57,1.05]); t=np.linspace(-1.,1.05,11)
            xx=cx+sg*t*r*1.29
            arch=([.0020,.0017,.0010,.0013,.0014,.0035,.0016][self.i])*G((t+.15)/.73)-self.p.brow_angle*(xx-cx)*sg
            mid=zz+r*[1.04,.94,1.04,1.14,1.04,1.04,.98][self.i]+arch
            thickness=np.interp(t,ctrl,[.0010,.0030,.00355,.0028,.0017,.00045])*[1.39,1.18,1.49,1.60,1.33,1.12,1.31][self.i]
            pts=np.vstack([np.c_[xx,mid+thickness*.55],np.c_[xx,mid-thickness*.55]])
            depth=silhouette(f,v,pts);vv=np.c_[pts[:,0],depth-.00315,pts[:,1]]
            if np.isfinite(vv).all():
                n=len(t); fs=[[j,j+1,j+n+1,j+n][::(-1 if sg>0 else 1)] for j in range(n-1)]
                meshes.append((vv,fs))
        return meshes


def subdivide(v,f,features=()):
    """One baked Catmull–Clark step. Partial creasing keeps eyelid and lip rims.

    Existing vertex IDs stay stable so facial landmark anchors carry forward.
    """
    from collections import defaultdict
    center=np.array([v[g].mean(0) for g in f]);links=defaultdict(list);vf=defaultdict(list)
    for i,g in enumerate(f):
        for a,b in zip(g,g[1:]+g[:1]):
            links[min(a,b),max(a,b)].append(i);vf[a].append(i)
    hard={tuple(sorted((a,b))) for r in features for a,b in zip(r,r[1:]+r[:1])}
    ee=list(links);ei={e:i for i,e in enumerate(ee)}; E=np.array(ee);mid=v[E].mean(1)
    epos=mid.copy(); vr=defaultdict(list); crease=defaultdict(list)
    for ix,(a,b) in enumerate(ee):
        es=links[a,b];vr[a].append(ix);vr[b].append(ix)
        if len(es)==2:
            p=(v[a]+v[b]+center[es[0]]+center[es[1]])*.25
            epos[ix]=lerp(p,mid[ix],.72) if (a,b) in hard else p
        if len(es)==1 or (a,b) in hard:crease[a].append(b);crease[b].append(a)
    base=v.copy()
    for i,es in vr.items():
        n=len(es);R=mid[es].mean(0);F=center[vf[i]].mean(0)
        pos=(F+2*R+(n-3)*v[i])/n
        if len(crease[i])==2:
            a,b=v[crease[i]];pos=lerp(pos,(6*v[i]+a+b)/8,.74)
        base[i]=pos
    nextf=[];nn=len(v); so=nn+len(ee)
    for i,g in enumerate(f):
        prev=g[-1]; nxt=g[1:]+g[:1]
        for a,b in zip(g,nxt):
            nextf.append([a,nn+ei[min(a,b),max(a,b)],so+i,nn+ei[min(a,prev),max(a,prev)]])
            prev=a
    rings=[[w for a,b in zip(r,r[1:]+r[:1]) for w in [a,nn+ei[min(a,b),max(a,b)]]] for r in features]
    return np.vstack([base,epos,center]),nextf,rings,np.repeat(np.arange(len(f)),[len(g) for g in f])


def mouth_faces(f,loops):
    inner=set(loops['2']['inside'])
    return np.array([len(inner.intersection(g))>=2 for g in f],dtype=bool)


def labeled_parts(v,f,build,mouth=None):
    from tripo_surface_preview import SKIN,CLOTH,EYE,clothes
    idx=build.i; colors=np.tile(SKIN[idx],(len(f),1))
    colors[mouth_faces(f,build.d['loops']) if mouth is None else mouth]=[79,51,45]
    yield 'Body',v,f,colors
    wpx,hpx=[(261,312),(251,303),(252,311),(764,821),(747,806),(771,824),(747,802)][idx]
    w,h=build.p.z(wpx),build.p.z(hpx)
    for name,(verts,faces) in clothes(v,f,idx,waist_and_hem=(w,h)).items():
        yield name,verts,faces,np.tile(CLOTH[idx],(len(faces),1))
    for j,e in enumerate(build.d['eyes']):
        st=build.eyes0[j];tar=build.eyes[j];p=np.asarray(e['v'])
        # Eye spheres keep their own readable proportions and rotatable object origins.
        # Gentle inset helps the sharp plane of the lid cover the peripheral sclera.
        shift=tar-st;shift[1]+=.00055
        palette=EYE.copy()
        palette[2]=[(82,62,48),(76,58,47),(81,67,47),(78,55,39),(81,81,75),(74,50,39),(166,123,63)][idx]
        yield f'Eye {j+1}',p+shift,e['f'],palette[e['mat']]
    for j,(points,faces) in enumerate(build.eyebrows(v,f)):
        c=[54,42,36] if idx in (0,3,5,6) else [64,50,40]
        yield f'Brow {j+1}',points,faces,np.tile(c,(len(faces),1))
    if idx==3:
        # Shen Ding's reference has a very short mustache and beard. Keep the
        # groom removable for fitting; the bald scalp and skin cage are intact.
        x0,_,z0=build.lip
        def strip(x,top,bottom):
            r=np.vstack([np.c_[x0+x,top],np.c_[x0+x,bottom]])
            depth=silhouette(f,v,r)-.0024
            n=len(x)
            if np.isfinite(depth).all():
                faces=[[k,k+n,k+n+1,k+1] for k in range(n-1)]
                return np.c_[r[:,0],depth,r[:,1]],faces
        q=np.linspace(-1,1,15); a=abs(q)
        designs=[('Moustache',.024*q,z0+.009+.0047*G((a-.32)/.42),z0+.008-.005*a+.0014*G((a-.34)/.32)),
                 ('Goatee',.024*q,z0-.017+.009*a**1.65,z0-.026+.018*a**2)]
        for name,x,top,bottom in designs:
            top=np.maximum(top,bottom+.0005)
            made=strip(x,top,bottom)
            if made is not None:
                pos,fs=made
                yield name,pos,fs,np.tile([71,55,40],(len(fs),1))


def write_json(filename,parts):
    filename.write_text(json.dumps([dict(name=n,v=v.tolist(),f=f,color=c.tolist()) for n,v,f,c in parts],separators=(',',':')),encoding='utf-8')


def warp_parts(parts, fields):
    for n,v,f,c in parts:
        if n.startswith('Eye'):
            center=v[-2:].mean(0,keepdims=True)
            vv=v+apply_warp(center,fields)-center
        else:
            vv=apply_warp(v,fields)
        yield n,vv,f,c


def body_measurement(v,f):
    from tripo_surface import masses
    # The shell is geometrically closed at eye sockets and oral cavity. Only
    # report volume-weighted centroid when the actual edge incidence confirms it.
    from collections import Counter
    edges=Counter(tuple(sorted((i,j))) for g in f for i,j in zip(g,g[1:]+g[:1]))
    return masses(v,f,all(n==2 for n in edges.values()))


def build_one(base,out,idx,levels,image,relief_strength=0.):
    from tripo_surface import reduce_strips, packed
    from tripo_surface_preview import panels
    s=CAST[idx]; d=json.loads((base/f'{s}.json').read_text(encoding='utf-8')); b=Build(d,idx)
    ref=reference_mask(image,b.p)
    p=b.face_proportions(b.proportions(b.v)); low=b.sculpt(p,b.f)
    rings=[r for g in d['loops'].values() for r in g.values() if r]
    loopv={x for r in rings for x in r}
    eye_count=sum(len(g)-2 for e in d['eyes'] for g in e['f'])
    low,lowf,removed,_=reduce_strips(low,b.f,5000-eye_count-40,loopv)
    lvl0=list(labeled_parts(low,lowf,b))
    ntri=lambda fs:sum(len(x)-2 for x in fs)
    editable=sum(ntri(fs) for n,_,fs,_ in lvl0 if n=='Body' or n.startswith(('Eye','Brow')))
    if editable>5000:
        raise ValueError(f'{s}: body, eyes and brows total {editable} triangles')
    v=b.v;f=b.f;creases=[g['rim'] for g in d['loops'].values()]; inner=mouth_faces(f,d['loops'])
    for _ in range(levels):
        v,f,creases,parents=subdivide(v,f,creases)
        inner=inner[parents]
    stage=b.face_proportions(b.proportions(v)); u=b.sculpt(stage,f)
    sculpt=list(labeled_parts(u,f,b,inner)); src=list(panels(d,idx))
    def mask(parts):
        ma=np.zeros_like(ref)
        for name,v,fs,_ in parts:
            if name.lower()=='body' or name in ('Underwear','Sports top'):
                ma|=mesh_mask(v,fs)
        return ma
    before=mask(src); unfit=mask(sculpt)
    # Two pass alignment; accept each correction only when the measured overlap
    # improves. Local axes, depth and mesh connectivity remain independent.
    trials=[]
    for strength in [.91,.66,.48]:
        start=mask(sculpt); fields=front_warp(start,ref,strength)
        next_sculpt=list(warp_parts(sculpt,fields)); nxt=mask(next_sculpt)
        next_low=list(warp_parts(lvl0,fields))
        scores=(iou(start,ref),iou(nxt,ref),iou(mask(lvl0),ref),iou(mask(next_low),ref))
        accepted=scores[1]>scores[0] and scores[3]>scores[2]
        if accepted:sculpt=next_sculpt; lvl0=next_low
        trials.append({'amount':strength,'accepted':accepted,'sculpt_iou_before_after':scores[:2],'low_iou_before_after':scores[2:]})
    relief_report={}
    if relief_strength:
        # Astra-authored contrast-guided pass. Run after frontal registration,
        # so the image landmarks and the material-free sculpt share coordinates.
        from anatomy_relief import apply_relief
        def apply(parts,name,locks):
            body,v,fs,c=parts[0]
            report={};dv=apply_relief(v,fs,image,profile=b.p,index=idx,strength=relief_strength,locked=locks,report=report)
            relief_report[name]=report
            res=[(body,dv,fs,c)]
            for n,vv,ff,cc in parts[1:]:
                if n.startswith(('Brow','Goatee','Moustache')):
                    probe=vv[:,[0,2]]
                    old_y=silhouette(fs,v,probe);new_y=silhouette(fs,dv,probe)
                    dvv=vv.copy(); ok=np.isfinite(old_y)&np.isfinite(new_y)
                    dvv[ok,1]+=new_y[ok]-old_y[ok]; vv=dvv
                res.append((n,vv,ff,cc))
            return res
        lvl0=apply(lvl0,'low',sorted(loopv));sculpt=apply(sculpt,'sculpt',sorted(loopv))
    def pack(parts):
        return [(n,*packed(v,fs),c) if n=='Body' else (n,v,fs,c) for n,v,fs,c in parts]
    lvl0=pack(lvl0);sculpt=pack(sculpt)
    q=b.p; new_low=lvl0[0][1]; newf=lvl0[0][2]
    c0,c1=body_measurement(b.v,b.f),body_measurement(new_low,newf)
    used=np.unique(np.concatenate(lowf));lookup={int(k):i for i,k in enumerate(used)}
    kept_rings={k:{n:[lookup[j] for j in ring] for n,ring in g.items()} for k,g in d['loops'].items()}
    (out/f'{s}-loops.json').write_text(json.dumps(kept_rings),encoding='utf-8')
    stats={
        'character':s,'reference_bounds_px':q.crop,'crown_y_px':q.crown,'chin_y_px':q.chin,'sole_y_px':q.foot,
        'reference_head_ratio':(q.foot-q.crown)/(q.chin-q.crown),'target_head_ratio':1/(1-b.target_chin),
        'reference_knee_height_pct_h':100*q.z(q.knee),'source_knee_anchor_pct_h':100*b.kn,
        'low_body_eye_brow_triangles':editable,'low_body_quads':sum(len(g)==4 for g in newf),
        'low_body_other_faces':sum(len(g)!=4 for g in newf),'preview_sculpt_body_quads':len(f),
        'front_silhouette_iou':dict(previous=iou(before,ref),before_fit=iou(unfit,ref),sculpt=iou(mask(sculpt),ref),low=iou(mask(lvl0),ref)),
        'fit_trials':trials,'relief_strength':relief_strength,'relief':relief_report,
        'sculpt_depth_displacement_p95_pct_h':100*float(np.quantile(np.abs(u[:,1]-stage[:,1]),.95)),
        'sculpt_depth_displacement_max_pct_h':100*float(np.max(np.abs(u[:,1]-stage[:,1]))),
        'sculpt_geometry_max_displacement_pct_h':100*float(np.max(np.linalg.norm(u-stage,axis=1))),
        'cage_quads_removed':sum(removed),
        'surface_centroid_shift_pct_h':float(np.linalg.norm(np.subtract(c1['surface_centroid'],c0['surface_centroid']))*100),
        'volume_centroid_shift_pct_h':float(np.linalg.norm(np.subtract(c1['volume_centroid'],c0['volume_centroid']))*100) if 'volume_centroid' in c0 and 'volume_centroid' in c1 else None,
        'centroids_before_after':{'previous':c0, 'low':c1}}
    print(s,'ratio',round(stats['target_head_ratio'],2),'low',editable,'sculpt',len(f),'IoU',stats['front_silhouette_iou'],flush=True)
    write_json(out/f'{s}-low.json',lvl0);write_json(out/f'{s}-sculpt.json',sculpt)
    overlay(ref,mask(sculpt)).save(out/f'{s}-outline-check.png')
    return b,src,lvl0,sculpt,stats


def render_card(b,src,low,sculpt,im,out):
    from PIL import Image,ImageDraw
    from tripo_surface_preview import raster,font,NAMES
    p=b.p;w=300;h=530
    sheet=Image.new('RGB',(5*w+48,h+126),'#171d25');g=ImageDraw.Draw(sheet)
    g.text((16,14),f'{NAMES[b.i]}  /  比例与解剖体块重建',font=font(25,True),fill='#f1e7d0')
    g.text((16,53),'同高正投影：参考、上一版和现版  ｜  右侧检验体块转折与前后厚度',font=font(16),fill='#bdc8d4')
    fx=1.095*(p.foot-p.crown)/h; full=int(round(1.095*(p.foot-p.crown)));cw=int(w*fx)
    ref=im.crop((p.center-cw//2,p.crown-(full-(p.foot-p.crown))//2,p.center+cw//2,p.foot+(full-(p.foot-p.crown))//2))
    panels=[('你给的参考',ref.resize((w,h),Image.Resampling.LANCZOS)),('上一版 · 正面',raster(src,0,(w,h))),
            ('雕刻审阅 · 正面',raster(sculpt,0,(w,h))),('雕刻审阅 · 斜侧',raster(sculpt,32,(w,h))),
            ('雕刻审阅 · 侧面',raster(sculpt,90,(w,h)))]
    for l,(title,img) in enumerate(panels):
        x=12+l*(w+6);g.text((x,81),title,font=font(17,True),fill='#e0e8f0');sheet.paste(img,(x,107))
    sheet.save(out/f'{CAST[b.i]}-comparison.jpg',quality=94)
    return panels


def fitted_review(base,out,idx,image,stats):
    from tripo_surface_preview import panels
    slug=CAST[idx]
    d=json.loads((base/f'{slug}.json').read_text(encoding='utf-8'));b=Build(d,idx)
    def read(parts):
        return [(o['name'],np.array(o['v']),o['f'],np.array(o['color'])) for o in json.loads(parts.read_text(encoding='utf-8'))]
    low=read(out/'fitted'/f'{slug}-low.json');sculpt=read(out/'fitted'/f'{slug}-sculpt.json')
    ref=reference_mask(image,b.p)
    for n,p in [('low',low),('sculpt',sculpt)]:
        mask=np.zeros_like(ref)
        for name,v,f,_ in p:
            if name in ('Body','Underwear','Sports top'):mask|=mesh_mask(v,f)
        stats['front_silhouette_iou'][n]=iou(mask,ref)
        if n=='sculpt':overlay(ref,mask).save(out/f'{slug}-outline-check.png')
    st=stats['centroids_before_after']; v,f=low[0][1:3]
    st['low']=body_measurement(v,f)
    stats['low_body_eye_brow_triangles']=sum(len(g)-2 for n,_,fs,_ in low if n=='Body' or n.startswith(('Eye','Brow')) for g in fs)
    stats['low_body_quads']=sum(len(g)==4 for g in f)
    stats['low_body_other_faces']=sum(len(g)!=4 for g in f)
    stats['preview_sculpt_body_quads']=sum(len(g)==4 for g in sculpt[0][2])
    for name,key in [('surface','surface_centroid'),('volume','volume_centroid')]:
        a,c=st['previous'].get(key),st['low'].get(key)
        stats[f'{name}_centroid_shift_pct_h']=(100*float(np.linalg.norm(np.subtract(c,a))) if a is not None and c is not None else None)
    return b,list(panels(d,idx)),low,sculpt,stats


def main():
    from argparse import ArgumentParser
    from PIL import Image,ImageDraw
    from tripo_surface_preview import NAMES,font,raster
    q=ArgumentParser(description=__doc__);q.add_argument('base',type=Path);q.add_argument('reference',type=Path);q.add_argument('out',type=Path);q.add_argument('--cast',nargs='+',choices=CAST,default=CAST);q.add_argument('--levels',type=int,default=1,choices=[1,2]);q.add_argument('--fitted-review',action='store_true');q.add_argument('--relief',type=float,default=0.);q.add_argument('--geometry-only',action='store_true');args=q.parse_args()
    args.out.mkdir(exist_ok=True,parents=True);im=Image.open(args.reference).convert('RGB');assert im.size==(1248,1082),im.size
    stats=[];cards=[]
    previous=json.loads((args.out/'anatomy-metrics.json').read_text(encoding='utf-8')) if args.fitted_review else []
    rows={row['character']:row for row in previous}
    for s in args.cast:
        idx=CAST.index(s)
        if args.fitted_review:b,src,low,sculpt,stats0=fitted_review(args.base,args.out,idx,im,rows[s])
        else:b,src,low,sculpt,stats0=build_one(args.base,args.out,idx,args.levels,im,args.relief)
        if args.geometry_only:
            stats.append(stats0);continue
        views=render_card(b,src,low,sculpt,im,args.out)
        head0=raster(src,0,(236,235),'head',False,idx);head1=raster(sculpt,0,(236,235),'head',False,idx)
        p=b.p;px=(p.foot-p.crown)*(.216 if idx==1 else .196)
        cy=p.foot-.924*(p.foot-p.crown)
        hrf=im.crop((round(p.center-px*.5),round(cy-px*.5),round(p.center+px*.5),round(cy+px*.5)))
        hrf=hrf.resize((236,235),Image.Resampling.LANCZOS)
        cards.append((idx,views,hrf,head0,head1,low));stats.append(stats0)
    (args.out/'anatomy-metrics.json').write_text(json.dumps(stats,ensure_ascii=False,indent=2),encoding='utf-8')
    if args.geometry_only:return
    w,h=242,416; n=len(cards); canvas=Image.new('RGB',(n*w+28,2*h+127),'#171d25');d=ImageDraw.Draw(canvas)
    d.text((14,10),'原图对比  /  实际体块几何',font=font(26,True),fill='#f1e7d0')
    d.text((14,52),'上：目标参考；下：同一纯色光照的雕刻审阅。正投影统一按头顶至足底归一。',font=font(15),fill='#bdc8d4')
    faces=Image.new('RGB',(n*w+28,3*235+119),'#171d25');fg=ImageDraw.Draw(faces)
    fg.text((14,10),'脸部几何  /  改前与改后',font=font(26,True),fill='#f1e7d0')
    fg.text((14,52),'第一排为你的参考，第二排为上一版，第三排为本轮纯色雕刻。',font=font(15),fill='#bdc8d4')
    wire=Image.new('RGB',(n*w+28,h+117),'#171d25'); wg=ImageDraw.Draw(wire)
    wg.text((14,10),'游戏底模 / 实际四边面线框',font=font(26,True),fill='#f1e7d0')
    wg.text((14,52),'斜侧裸网格审查；衣件仅在此检查视图隐藏。',font=font(15),fill='#bdc8d4')
    for j,(idx,views,headref,head0,head1,low) in enumerate(cards):
        x=14+j*w;d.text((x,84),NAMES[idx],font=font(17,True),fill='#e0e8f0');fg.text((x,78),NAMES[idx],font=font(17,True),fill='#e0e8f0')
        for row,k in enumerate((0,2)):
            canvas.paste(views[k][1].resize((w-5,h),Image.Resampling.LANCZOS),(x,110+(h+5)*row))
        faces.paste(headref,(x,102));faces.paste(head0,(x,340));faces.paste(head1,(x,578))
        wg.text((x,84),NAMES[idx],font=font(17,True),fill='#e0e8f0')
        wire.paste(raster([p for p in low if p[0]=='Body'],32,(w-5,h),wire=True),(x,109))
    canvas.save(args.out/'cast-front-reference-match.jpg',quality=94);faces.save(args.out/'cast-head-before-after.jpg',quality=94);wire.save(args.out/'cast-low-wire.jpg',quality=94)

if __name__=='__main__':main()
