# Sol v2 | Public observation-only course policy.
# The map caches ray-visible geometry within one room. The stage only advances
# after observed state or an accepted action; no seed or layout lookup is used.
def wait():
    return {"type": "Wait"}


def use(target, op, delay=0):
    return {"type": "Interact", "target_entity_id": target, "op_type": op, "delay_ticks": delay}


def command(agent, action):
    return {"type": "CommandCompanion", "agent_id": agent, "action_spec": action}


def turn(yaw, target):
    return {"type": "RotateYaw", "delta_angle": (target-yaw+180)%360-180}


def square(p, q):
    return (p[0]-q[0])*(p[0]-q[0])+(p[1]-q[1])*(p[1]-q[1])


def move(p, q, speed=100):
    dx, dz = q[0]-p[0], q[1]-p[1]
    dist = isqrt(dx*dx+dz*dz)
    return {"type": "Move", "dir_vec": [dx*1000//max(1,abs(dx),abs(dz)),dz*1000//max(1,abs(dx),abs(dz))], "speed_ratio": 100,
            "duration_ticks": max(1,min(20,(dist+speed//2)//speed))}


def bearing(p, q):
    x,z = q[0]-p[0],q[1]-p[1]
    ax,az = abs(x),abs(z)
    if ax+az == 0:
        return 0
    if ax <= az:
        r = ax*100//az
        a = r*(57-r*12//100)//100
    else:
        r = az*100//ax
        a = 90-r*(57-r*12//100)//100
    if z < 0:
        a = 180-a
    if x < 0:
        a = -a
    return a%360


def location(m, name):
    g = m.get(name)
    if g:
        p = g[0]["position"]
        return [p[0],p[2]]
    return None


def field(m, name, key):
    return m.get(name,[{},{}])[1].get(key,0)


def blocks(a,b,box):
    xmin,zmin,xmax,zmax=box
    ax,az=a
    bx,bz=b
    if ax<=xmin and bx<=xmin or ax>=xmax and bx>=xmax or az<=zmin and bz<=zmin or az>=zmax and bz>=zmax:
        return False
    dx,dz=bx-ax,bz-az
    if dx==0 or dz==0:
        return True
    if dx>0:
        lo=(xmin-ax)*1000//dx
        hi=(xmax-ax)*1000//dx
    else:
        lo=(xmax-ax)*1000//dx
        hi=(xmin-ax)*1000//dx
    if dz>0:
        lower=(zmin-az)*1000//dz
        upper=(zmax-az)*1000//dz
    else:
        lower=(zmax-az)*1000//dz
        upper=(zmin-az)*1000//dz
    return lo<upper and lower<hi and lo<1000 and lower<1000 and hi>0 and upper>0


def navigate(m,p,q,ignore="",speed=100):
    obstacles=[]
    for name, record in m.items():
        g=record[0]
        if name == ignore or not g.get("solid") or not g.get("size"):
            continue
        x,y,z=g["position"]
        w,h,d=g["size"]
        if y+h<250 or y>1500:
            continue
        box=(x,z,w//2+300,d//2+300)
        if abs(p[0]-x)<box[2] and abs(p[1]-z)<box[3]:
            continue
        obstacles.append((x-box[2],z-box[3],x+box[2],z+box[3]))
    # Look around the nearest blocking rectangle with at most two corners.
    # Keep the search local so complex rooms do not exhaust the decision fuel.
    blocking=None
    closest=1000000000
    for box in obstacles:
        if blocks(p,q,box):
            dx=max(box[0]-p[0],p[0]-box[2],0)
            dz=max(box[1]-p[1],p[1]-box[3],0)
            d=dx*dx+dz*dz
            if d<closest:
                closest=d
                blocking=box
    if not blocking:
        return move(p,q,speed)
    x0,z0,x1,z1=blocking
    a=[x0-120,z0-120]
    b=[x1+120,z0-120]
    c=[x0-120,z1+120]
    d=[x1+120,z1+120]
    best=100000000
    goal=q
    for start,side,end in [(a,b,c),(b,a,d),(c,d,a),(d,c,b)]:
        if square(p,start)<135*135 or not clear_path(p,start,obstacles):
            continue
        origin=isqrt(square(p,start))
        if clear_path(start,q,obstacles):
            total=origin+isqrt(square(start,q))
            if total<best:
                best,goal=total,start
        for other in [side,end]:
            if not clear_path(start,other,obstacles):
                continue
            penalty=0 if clear_path(other,q,obstacles) else 2500
            total=origin+isqrt(square(start,other))+isqrt(square(other,q))+penalty
            if total<best:
                best,goal=total,start
    return move(p,goal,speed)


def clear_path(p,q,obstacles):
    for b in obstacles:
        if blocks(p,q,b):
            return False
    return True


def survey(o,s):
    p=o["self"]["pos"]
    t=s.get("survey",0)
    s["survey"]=t+1
    if t%5==0:
        return turn(o["self"]["yaw"],0)
    if t%5<4:
        return {"type":"RotateYaw","delta_angle":90}
    return navigate(s["map"],p,[p[0]+[0,1200,-1200][t//5%3],p[1]+1100])


def approach(o,s,target,action,reach=2000):
    m=s["map"]
    p=o["self"]["pos"]
    q=location(m,target)
    if q is None:
        return survey(o,s)
    yaw=o["self"]["yaw"]
    angle=bearing(p,q)
    if square(p,q)>reach*reach:
        d=isqrt(square(p,q))
        offset=reach-400
        if reach<1000:
            offset=reach-180
        goal=[q[0]+(p[0]-q[0])*offset//d,q[1]+(p[1]-q[1])*offset//d]
        return navigate(m,p,goal,target if reach<1000 else "")
    if abs((angle-yaw+180)%360-180)>7:
        return turn(yaw,angle)
    return action


def exit_room(o,s):
    m=s["map"]
    p=o["self"]["pos"]
    q=location(m,"exit")
    if not q:
        return survey(o,s)
    reach=1050
    if square(p,q)>reach*reach:
        goal=[q[0],q[1]-650]
        return navigate(m,p,goal,"exit")
    return approach(o,s,"exit",use("exit","traverse"),reach)


def delay_for(o,s,names):
    periods=[]
    for name in names:
        r=o["equipment"].get(name,{}).get("periodic",[])
        if not r:
            return -2
        periods.append(r[0])
    for delay in range(20):
        t=o["room_tick"]+delay
        active=True
        for r in periods:
            if (t+r["offset"])%r["period"]>=r["window"]:
                active=False
        if active:
            return delay
    return -1


def cam_exit(o,s):
    # Traverse the outside of the cam assembly before cutting back to the door.
    m=s["map"]
    p=o["self"]["pos"]
    door=location(m,"exit")
    if not door:
        return survey(o,s)
    stage=s["stage"]
    if stage==0:
        sign=1
        if "right_rail" in m and "left_rail" not in m:
            sign=-1
        edge=0
        back=p[1]
        for name in ["latch","left_cam","right_cam","left_rail","right_rail"]:
            if name not in m:
                continue
            g=m[name][0]
            x,y,z=g["position"]
            w,h,d=g["size"]
            edge=max(edge,sign*x+w//2)
            back=max(back,z+d//2)
        s["lane"]=sign*(edge+520)
        s["back"]=back+670
        s["stage"]=1
        stage=1
    x=s["lane"]
    if stage==1:
        if abs(p[0]-x)>90:
            return move(p,[x,p[1]])
        s["stage"]=2
        stage=2
    if stage==2:
        if p[1]<s["back"]-90:
            return move(p,[x,s["back"]])
        s["stage"]=3
    return exit_room(o,s)


def synchronize(o,s):
    if field(s["map"],"latch","latched"):
        return cam_exit(o,s)
    if s.get("issued") and o["last_result"]=="OK":
        return cam_exit(o,s)
    d=delay_for(o,s,["left_cam","right_cam"])
    if d==-2:
        return survey(o,s)
    action=approach(o,s,"latch",use("latch","latch",max(0,d)))
    s["issued"]=action["type"]=="Interact" and d>=0
    if action["type"]=="Interact" and d<0:
        return wait()
    return action


def gallery_exit(o,s):
    # Bay center spacing gives a through lane between the observed assemblies.
    m=s["map"]
    p=o["self"]["pos"]
    door=location(m,"exit")
    if not door:
        return survey(o,s)
    stage=s["stage"]
    if stage==0:
        xs=[]
        back=p[1]
        for bay in ["bay_1","bay_2","bay_3"]:
            q=location(m,bay)
            if q:
                xs.append(q[0])
            g=m[bay+"_arm"][0]
            back=max(back,g["position"][2]+g["size"][2]//2)
        q=location(m,"master_arm")
        if q:
            xs.append(q[0])
        xs=sorted(xs)
        lane=p[0]
        best=9999999
        for i in range(1,len(xs)):
            x=(xs[i]+xs[i-1])//2
            cost=abs(x-p[0])*2+abs(x-door[0])
            if cost<best:
                lane,best=x,cost
        s["lane"]=lane
        s["back"]=back+450
        s["stage"]=1
        stage=1
    x=s["lane"]
    if stage==1:
        if abs(p[0]-x)>90:
            return move(p,[x,p[1]])
        s["stage"]=2
        stage=2
    if stage==2:
        if p[1]<s["back"]-90:
            return move(p,[x,s["back"]])
        s["stage"]=3
    return exit_room(o,s)


def inspection(o,s):
    if s.get("issued") and o["last_result"]=="OK":
        s["solved"]=True
    if s.get("solved"):
        return gallery_exit(o,s)
    m=s["map"]
    bays=["bay_1","bay_2","bay_3"]
    master=m.get("master_arm")
    if not master:
        for name,r in m.items():
            if "master" in name and "arm" in name:
                master=r
    if not master or "bay_1_arm" not in m or "bay_2_arm" not in m or "bay_3_arm" not in m:
        return survey(o,s)
    y=master[0]["position"][1]
    score=-1
    chosen=bays[0]
    for b in bays:
        diff=abs(m[b+"_arm"][0]["position"][1]-y)
        if diff>score:
            score=diff
            chosen=b
    a=approach(o,s,chosen,use(chosen,"reject"))
    s["issued"]=a["type"]=="Interact"
    return a


def evidence_for(o,target,op):
    for e in o["evidence"]:
        a=e["action"]
        if a.get("target_entity_id")==target and a.get("op_type")==op:
            return e
    return None


def patch(o,c,target,op):
    for r in c.get("declared_rules",[]):
        a=r.get("action",{})
        if a.get("target_entity_id")==target and a.get("op_type")==op and not r.get("exceptions"):
            e=evidence_for(o,target,op)
            if e and o["tick"]-e["tick"]>=40:
                return {"type":"PersuadeWithEvidence","agent_id":c["agent_id"],"rule_node_id":r["rule_id"],
                        "proposed_ast_patch":{"mode":"EXEMPT_ACTION"},"evidence_ref":e["id"]}
            return wait()
    return None


def companion(o,s,i):
    if i>=len(o["companions"]):
        return {}
    c=o["companions"][i]
    if "pos" not in c:
        snapshot=c.get("last_query",{})
        if o["tick"]-snapshot.get("tick",-100)==20:
            c=dict(c)
            actor=snapshot["self"]
            c["pos"]=actor["pos"]
            c["yaw"]=actor["yaw"]
    return c


def query(c):
    return {"type":"QueryCompanion","agent_id":c["agent_id"]}


def ally_move(m,c,q):
    if "pos" not in c:
        return query(c)
    return command(c["agent_id"],navigate(m,c["pos"],q))


def ally_face(c,q):
    if "pos" not in c:
        return query(c)
    angle=bearing(c["pos"],q)
    if abs((angle-c["yaw"]+180)%360-180)>7:
        return command(c["agent_id"],turn(c["yaw"],angle))
    return None


def spring(o,s):
    m=s["map"]
    p=o["self"]["pos"]
    c=companion(o,s,0)
    pad=location(m,"treadle")
    bolt=location(m,"bolt")
    if not pad or not bolt or not c:
        return survey(o,s)
    if not evidence_for(o,"bolt","throw"):
        if square(p,pad)>350*350:
            return navigate(m,p,pad)
        return approach(o,s,"bolt",use("bolt","throw"),2250)
    a=patch(o,c,"bolt","throw")
    if a:
        return a
    stage=s.get("stage",0)
    if stage==0:
        if "pos" not in c:
            return query(c)
        if square(c["pos"],pad)>350*350:
            return ally_move(m,c,pad)
        a=ally_face(c,bolt)
        if a:
            return a
        s["stage"]=1
        stage=1
    if stage==1:
        if field(m,"selector","live"):
            s["stage"]=2
            stage=2
        else:
            return approach(o,s,"selector",use("selector","arm"),1350)
    if stage==2:
        if s.get("live_throw") and o["last_result"]=="OK":
            s["stage"]=3
            stage=3
        else:
            s["live_throw"]=True
            return command(c["agent_id"],use("bolt","throw"))
    if stage==3:
        if "pos" not in c:
            return query(c)
        if square(c["pos"],pad)<950*950:
            return ally_move(m,c,[pad[0],pad[1]-1200])
        s["stage"]=4
    return exit_room(o,s)


def ready_ally(o,s,c,q):
    if "pos" not in c:
        return query(c)
    p=c["pos"]
    if square(p,q)>1750*1750:
        d=isqrt(square(p,q))
        goal=[q[0]+(p[0]-q[0])*1250//d,q[1]+(p[1]-q[1])*1250//d]
        return ally_move(s["map"],c,goal)
    return ally_face(c,q)


def flywheel(o,s):
    m=s["map"]
    c=companion(o,s,0)
    if not c:
        return survey(o,s)
    if s.get("stage",0)==0:
        e=evidence_for(o,"release","release")
        if not e:
            d=delay_for(o,s,["wheel"])
            if d==-2:
                return survey(o,s)
            a=approach(o,s,"release",use("release","release",max(0,d)))
            if a["type"]=="Interact" and d<0:
                return wait()
            return a
        a=patch(o,c,"release","release")
        if a:
            return a
        q=location(m,"release")
        if not q:
            return survey(o,s)
        a=ready_ally(o,s,c,q)
        if a:
            return a
        s["stage"]=1
    if s["stage"]==1:
        if field(m,"receiver","armed"):
            s["stage"]=2
        else:
            return approach(o,s,"receiver",use("receiver","arm"),1150)
    if s["stage"]==2:
        if field(m,"receiver","charged") or (s.get("transferred") and o["last_result"]=="OK"):
            s["stage"]=3
        else:
            d=delay_for(o,s,["wheel"])
            if d<0:
                return wait()
            a=command(c["agent_id"],use("release","release"))
            a["delay_ticks"]=d
            s["transferred"]=True
            return a
    return exit_room(o,s)


def counterweight(o,s):
    m=s["map"]
    p=o["self"]["pos"]
    c=companion(o,s,0)
    stage=s["stage"]
    if stage==0:
        if not evidence_for(o,"capstan","shift"):
            if field(m,"capstan","stroked") or field(m,"shuttle","docked"):
                return wait()
            return approach(o,s,"capstan",use("capstan","shift"),1250)
        q=location(m,"capstan")
        if not q:
            return survey(o,s)
        a=ready_ally(o,s,c,q)
        if a:
            return a
        stage=1
        s["stage"]=1
    if stage==1:
        if not field(m,"clutch","engaged"):
            return approach(o,s,"clutch",use("clutch","commission"),1300)
        stage=2
        s["stage"]=2
    if stage==2:
        a=patch(o,c,"capstan","shift")
        if a:
            return a
        q=location(m,"balance")
        if not q:
            return survey(o,s)
        if square(p,q)>375*375:
            return navigate(m,p,q)
        if s.get("transferred") and o["last_result"]=="OK":
            stage=3
            s["stage"]=3
        else:
            s["transferred"]=True
            return command(c["agent_id"],use("capstan","shift"))
    return exit_room(o,s)


def shutter_room(o,s):
    m=s["map"]
    p=o["self"]["pos"]
    c=companion(o,s,0)
    stage=s["stage"]
    if stage==0:
        if field(m,"vent","bled"):
            return approach(o,s,"vent",use("vent","seal"),1400)
        if not evidence_for(o,"handle","retract"):
            if field(m,"handle","released") or field(m,"shutter","open"):
                return wait()
            return approach(o,s,"handle",use("handle","retract"),1400)
        s["stage"]=1
        stage=1
    if stage==1:
        if not field(m,"vent","bled"):
            return approach(o,s,"vent",use("vent","bleed"),1400)
        v=location(m,"vent")
        h=location(m,"handle")
        if not v or not h:
            return survey(o,s)
        if "pos" not in c:
            return query(c)
        midpoint=[(v[0]+h[0])//2,min(v[1],h[1])-320]
        if square(c["pos"],midpoint)>250*250:
            return ally_move(m,c,midpoint)
        a=ally_face(c,v)
        if a:
            return a
        s["stage"]=2
        stage=2
    if stage==2:
        if not field(m,"sight","live"):
            if o["self"]["pose"]!="crouch":
                return {"type":"SetPose","pose":"crouch"}
            return approach(o,s,"sight",use("sight","engage"),1150)
        s["stage"]=3
        stage=3
    if stage==3:
        a=patch(o,c,"handle","retract")
        if a:
            return a
        if s.get("sealed") and o["last_result"]=="OK":
            s["stage"]=4
            stage=4
        else:
            s["sealed"]=True
            return command(c["agent_id"],use("vent","seal"))
    if stage==4:
        a=ready_ally(o,s,c,location(m,"handle"))
        if a:
            return a
        s["stage"]=5
        stage=5
    if stage==5:
        if s.get("transferred") and o["last_result"]=="OK":
            s["stage"]=6
        else:
            s["transferred"]=True
            return command(c["agent_id"],use("handle","retract"))
    return exit_room(o,s)


def mount(o,m,target,plate):
    q=location(m,plate)
    if q:
        return q
    q=location(m,target)
    d=o["equipment"].get(target,{}).get("mount_references_mm",{}).get(plate)
    if q and d:
        return [q[0]+d[0],q[1]+d[1]]
    return None


def put_on(o,s,i,target,plate):
    m=s["map"]
    c=companion(o,s,i)
    q=mount(o,m,target,plate)
    t=location(m,target)
    if not q or not t:
        return survey(o,s)
    if "pos" not in c:
        return query(c)
    if square(c["pos"],q)>230*230:
        return ally_move(m,c,q)
    return ally_face(c,t)


def exchange(o,s,room):
    # The trio circuits share a dry proof, two stations, and a live handoff.
    # The finishing operation and timing come from the current course circuit.
    m=s["map"]
    c=companion(o,s,0)
    d=companion(o,s,1)
    stage=s["stage"]
    test,proof,read,finish="copper","charge","charged","release"
    first,second="charge","brace"
    if room==8:
        test,proof,read,finish="cobalt","mesh","meshed","transfer"
        first,second="drive","mesh"
    if room==9:
        test,proof,read,finish="copper","raise","raised","read"
        first,second="raise","turn"
    if room==10:
        test,proof,read,finish="copper","retain","retained","index"
        first,second="retain","secure"
    if stage==0:
        if not evidence_for(o,test,proof):
            if field(m,test,read):
                return wait()
            return approach(o,s,test,use(test,proof),1550)
        if room>=9 and not evidence_for(o,"cobalt",second):
            if field(m,"cobalt","turned" if room==9 else "secured"):
                return wait()
            return approach(o,s,"cobalt",use("cobalt",second),1550)
        s["stage"]=1
        stage=1
    if stage==1 or stage==2:
        a=put_on(o,s,stage-1,["copper","cobalt"][stage-1],["copper_plate","cobalt_plate"][stage-1])
        if a:
            return a
        s["stage"]=stage+1
        return wait()
    if stage==3:
        if room==9 and o["self"]["pose"]!="crouch":
            return {"type":"SetPose","pose":"crouch"}
        if not field(m,"console","armed") and not (s.get("primed") and o["last_result"]=="OK"):
            a=approach(o,s,"console",use("console","arm"),950 if room==9 else 1450)
            s["primed"]=a["type"]=="Interact"
            return a
        stage=4
        s["stage"]=4
    if stage==4:
        a=patch(o,d if room==8 else c,test,proof)
        if a:
            return a
        if s.get("transferred") and o["last_result"]=="OK":
            stage=5
            s["stage"]=5
        else:
            s["transferred"]=True
            return command(c["agent_id"],use("copper",first))
    if stage==5:
        if room>=9:
            a=patch(o,d,"cobalt",second)
            if a:
                return a
        if s.get("sealed") and o["last_result"]=="OK":
            s["stage"]=6
            stage=6
        else:
            s["sealed"]=True
            return command(d["agent_id"],use("cobalt",second))
    if stage==6:
        if s.get("issued") and o["last_result"]=="OK":
            s["stage"]=7
        else:
            if room==9 and o["self"]["pose"]!="crouch":
                return {"type":"SetPose","pose":"crouch"}
            delay=0
            if room==8 or room==10:
                delay=delay_for(o,s,["clock","return_clock"] if room==8 else ["clock"])
                if delay==-2:
                    return survey(o,s)
            a=approach(o,s,"console",use("console",finish,max(0,delay)),950 if room==9 else 1450)
            if a["type"]=="Interact" and delay<0:
                return wait()
            s["issued"]=a["type"]=="Interact"
            return a
    if room==10:
        return finish_foundry(o,s)
    return exit_room(o,s)


def low_delay(o):
    clock=o["equipment"].get("clock",{}).get("periodic",[])
    if not clock:
        return -1
    r=clock[0]
    for delay in range(20):
        if (o["room_tick"]+delay+r["offset"])%r["period"]>=r["window"]:
            return delay
    return -1


def stand_down(o,s,i,name):
    m=s["map"]
    c=companion(o,s,i)
    q=mount(o,m,name,name+"_plate")
    if not q:
        return survey(o,s)
    if "pos" not in c:
        return query(c)
    if square(c["pos"],q)>900*900:
        return None
    return ally_move(m,c,[q[0],q[1]-1250])


def finish_foundry(o,s):
    # The side that can seat the stop remains on its plate until the other leaves.
    last="cobalt"
    operation="settle"
    for name in ["cobalt","copper"]:
        for op,contract in o["equipment"].get(name,{}).get("operations",{}).items():
            for effect in contract.get("effects",[]):
                if effect==["stop_block","seated",1]:
                    last=name
                    operation=op
    i=1 if last=="cobalt" else 0
    other="copper" if i==1 else "cobalt"
    stage=s["stage"]
    if stage==7:
        a=stand_down(o,s,1-i,other)
        if a:
            return a
        s["stage"]=8
        stage=8
    if stage==8:
        if s.get("seated") and o["last_result"]=="OK":
            s["stage"]=9
            stage=9
        else:
            c=companion(o,s,i)
            s["seated"]=True
            return command(c["agent_id"],use(last,operation))
    if stage==9:
        a=stand_down(o,s,i,last)
        if a:
            return a
        s["stage"]=10
        stage=10
    if stage==10:
        if s.get("unloaded") and o["last_result"]=="OK":
            s["stage"]=11
        else:
            delay=low_delay(o)
            if delay<0:
                return wait()
            a=approach(o,s,"console",use("console","unload",delay),1400)
            s["unloaded"]=a["type"]=="Interact"
            return a
    return exit_room(o,s)


def decide(o,state):
    level=o["level"]
    if state.get("level")!=level:
        state["seated"]=False
        state["unloaded"]=False
        state["primed"]=False
        state["sealed"]=False
        state["transferred"]=False
        state["stage"]=0
        state["live_throw"]=False
        state["issued"]=False
        state["solved"]=False
        state["survey"]=0
        state["level"]=level
        state["map"]={}
    m=state["map"]
    for r in o["rays"]:
        if isinstance(r,dict):
            m[r["entity_id"]]=[r["primitive_geometry"],r["whitebox_state"],r["entity_class"]]
    if level==1:
        return synchronize(o,state)
    if level==2:
        return inspection(o,state)
    if level==3:
        return spring(o,state)
    if level==4:
        return flywheel(o,state)
    if level==5:
        return counterweight(o,state)
    if level==6:
        return shutter_room(o,state)
    if level>=7 and level<=10:
        return exchange(o,state,level)
    return wait()
