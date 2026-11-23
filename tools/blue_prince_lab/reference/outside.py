"""Two fixed compositions share firs, granite, ground cover and aerial-perspective ridges."""
import random
from math import sin,cos,tau,pi
import numpy as np
from mesh import Mesh,shade

def spruce(variant):
    rng=random.Random(610+variant); m=Mesh(); top=1.; m.rod((0,0,0),(.012,.87,.008),.036,'504741',7,.009)
    base=['245149','2f5c4e','456247','345c56'][variant]
    for j,(y,r,h) in enumerate([(.19,.199,.39),(.31,.183,.36),(.43,.152,.33),(.55,.122,.30),(.67,.088,.25),(.77,.058,.23)]):
        count=8 if j<4 else 6; offset=rng.random(); tip=(.013*cos(j),y+h,.009*sin(j)); rings=[[],[],[]]; shades=[]
        for i in range(2*count):
            a=tau*i/(2*count)+offset; tooth=i%2==0; length=r*rng.uniform(.92,1.13)*(1 if tooth else .69); low=y+rng.uniform(-.023,.014)+(0 if tooth else .064)
            for ring,k,dy in zip(rings,[1,.78,.38],[0,.085,.19]):
                ring.append((cos(a)*length*k,low+dy*(1 if j<4 else .67),sin(a)*length*k))
            shades.append(rng.uniform(.87,1.13))
        for i in range(2*count):
            k=(i+1)%(2*count); c=shade(base,shades[i]*(1+.035*j)); a,b,d=rings
            m.face([a[k],a[i],b[i],b[k]],c);m.face([b[k],b[i],d[i],d[k]],c);m.face([d[k],d[i],tip],c);m.face([a[i],a[k],(0,y+.07,0)],shade(base,.59))
            # Tapered needle sprays follow the actual slope of each outer facet.
            if i%2==0:
                heel=np.array(a[i]); left=np.array(b[k]); right=np.array(b[i]); up=np.array(d[i]); off=np.array([cos(tau*i/(2*count)+offset),0,sin(tau*i/(2*count)+offset)])*.0011
                for q in range(3):
                    u=(q+1)/5; root=heel*.16+(left*u+right*(1-u))*.70+up*.14+off
                    end=heel*(.79-q*.065)+(left*u+right*(1-u))*(.21+q*.065)+off
                    width=(left-right)*(.036+q*.006)
                    m.face([root+width,root-width,end],shade(c,1.14+q*.042))
    m.save('Spruce'+str(variant))

def landscape_modules():
    for i in range(4): spruce(i)
    m=Mesh();rng=random.Random(58); lo=[];hi=[]
    for i in range(8):
        a=tau*i/8;lo.append((cos(a)*rng.uniform(.86,1.15),-.05,sin(a)*.67));hi.append((cos(a)*rng.uniform(.55,.9),rng.uniform(.28,.5),sin(a)*.5))
    for i in range(8): m.face([lo[i],hi[i],hi[i-1],lo[i-1]],shade('58616a',rng.uniform(.8,1.05)));m.face([hi[i],(.04,.54,.02),hi[i-1]],'727b7e')
    m.save('Fieldstone');m=Mesh()
    for side in [-1,1]:
        x=side*1.23;m.box((x,1.82,0),(.15,3.64,.17),'313739');m.box((x,3.55,0),(.24,.11,.25),'485251')
        for i in range(1,6): m.box((side*(1.22+i*.138),1.55,.015),(.066,3.04,.10),'353c3a')
        for i in range(8): m.box((side*1.67,.26+i*.422,-.02),(.93,.073,.13),'414743')
        m.box((side*2.15,1.58,0),(.15,3.18,.2),'384343')
    for y,w,d in [(3.42,2.6,.16),(3.52,2.73,.22),(3.59,2.81,.25)]: m.box((0,y,0),(w,.10,d),'455155')
    m.ring((0,2.23,.055),.88,.975,.15,'404948',48)
    for i in range(-7,8):
        x=i*.143; high=2.23-(max(0,.96**2-min(.96,abs(x))**2))**.5
        m.box((x,high*.5,.035),(.095,high,.10),'3a4038')
    m.board((-1.1,1.68,.13),(.96,.1,.13),.13,.09,'4c4b3d');m.save('MoonGate')
    m=Mesh();m.box((0,.90,0),(4.8,.14,.43),'66757e');m.box((0,.17,0),(4.8,.35,.32),'576573')
    for i in range(6): m.box((-2.0+i*.8,.55,0),(.59,.53,.32),'657484')
    m.box((2.31,.73,0),(.49,1.46,.54),'6d7786');m.box((2.31,1.38,0),(.65,.11,.66),'475361');m.box((2.31,1.50,0),(.70,.16,.70),'82919e');m.rod((2.31,1.58,0),(2.31,1.72,0),.46,'8393a0',4,.34,phase=pi/4);m.save('GardenWall')
    m=Mesh(); # A-frame, open fly, rolled valance, poles and guy lines
    for s in [-1,1]:
        for i in range(7):
            z=1.57-i*.46; zz=z-.46
            m.face([(s*1.42,.05,z),(s*.72,1.39,z),(s*.72,1.39,zz),(s*1.42,.05,zz)],shade('90623f' if s<0 else '584b3b',1+.025*(i%3)))
            m.face([(s*.72,1.39,z),(0,2.91,z),(0,2.91,zz),(s*.72,1.39,zz)],shade('af794b' if s<0 else '5d5141',1+.02*(i%3)))
        m.face([(0,2.91,1.57),(s*1.42,.05,1.57),(s*.89,.18,1.69),(s*.38,1.26,1.72)],'ce874d');m.face([(0,2.91,1.57),(s*.38,1.26,1.72),(s*.19,1.63,1.62)],'f0a05e')
        m.face([(0,2.89,-1.65),(s*1.42,.05,-1.65),(0,.04,-1.65)],'634435')
        for z in [-1.52,1.51]: m.rod((s*.6,1.72,z),(s*2.05,.08,z+.34),.012,'a98f68',4)
    for z in [-1.65,1.52]:m.rod((0,.01,z),(0,2.99,z),.048,'64503a',7)
    m.save('RidgeTent')

def backdrop(m,rng):
    for layer,(z,base,amp,col) in enumerate([(-84,8,19,'698ba4'),(-65,5,15,'587e95'),(-48,3,6,'456d80')]):
        rows=[[],[],[]];
        for i in range(76):
            x=(i-38)*2.9; h=base+amp*(.46+.27*sin(x*.112+layer)+.18*sin(x*.28+2*layer)+.09*cos(x*.56))+rng.uniform(-1.3,1.3)
            for j,(frac,off) in enumerate([(1,0),(.49,3.4),(0,7)]):rows[j].append((x+rng.uniform(-.7,.7),h*1.62*frac-1.0,z+off+rng.uniform(-2,2)))
        for a,b in zip(rows,rows[1:]):
            for i in range(1,len(a)):
                m.face([a[i-1],b[i-1],a[i]],shade(col,rng.uniform(.91,1.05)));m.face([a[i],b[i-1],b[i]],shade(col,rng.uniform(.91,1.05)))

def outside(camp):
    name='ForestCamp' if camp else 'GardenGate';m=Mesh();rng=random.Random(523 if camp else 209);backdrop(m,rng)
    m.box((0,-.21,-22),(138,.4,100),'375b4e' if camp else '30594f');
    path=lambda z:(-.39*z-.6+.65*sin(z*.28)) if camp else 1.32-.34*z-.038*z*z
    if camp:
        for i in range(55):
            z=9-i*.47;zz=z-.47;w=1.1+.9*(z+17)/26
            m.face([(path(z)-w,.015,z),(path(z)+w,.015,z),(path(zz)+w,.015,zz),(path(zz)-w,.015,zz)],shade('474b4c',rng.uniform(.95,1.02)))
        fire=(-.10,.04,-1.1)
        for s in [-1,1]:m.rod((fire[0]+s*.70,.02,fire[2]),(fire[0]+s*.65,1.40,fire[2]),.055,'514635',6)
        m.rod((-.95,1.34,-1.1),(.78,1.34,-1.1),.064,'4e4130',7);m.rod((-.12,.82,-1.09),(-.12,1.34,-1.09),.012,'302e2c',5);m.rod((-.12,.58,-1.09),(-.12,.84,-1.09),.16,'333a34',8,.21)
        for i in range(4):
            a=.37+i*1.26; m.rod((fire[0]-.35*cos(a),.10+i*.031,fire[2]-.35*sin(a)),(fire[0]+.35*cos(a),.11+i*.031,fire[2]+.35*sin(a)),.091,'4a322a',8)
        for x,z in [(1.53,-.9),(1.8,-1.13),(-3.4,-4)]:m.rod((x,.21,z),(x+.9,.23,z-.36),.21,'65503b',8)
    else:
        for i in range(5):
            x=7+9*i;z=-23-i*7;m.rod((x,0,z),(x,7,z),.10,'555954',7);m.box((x,6.75,z),(2.4,.095,.11),'464f52');
            for s in [-.8,.8]:
                for j in range(6):
                    def wire(t): return (x+s-9*t,6.86-.48*sin(pi*t),z+7*t)
                    m.rod(wire(j/6),wire((j+1)/6),.023,'464f51',4)
    m.save(name+'Land')
