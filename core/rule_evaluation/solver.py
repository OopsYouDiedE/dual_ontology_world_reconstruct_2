"""Observation-only circuit reference policy.

The public curriculum gives high-level commissioning procedures. A shared
executor does geometry discovery, routing, phase arithmetic, and proof search.
There are no room-builder imports, seed reads, guessed evidence IDs or replay
inputs. In particular, the inspection answer is computed from ray geometry.
"""
from math import isqrt

from .dsl import WAIT, match
from .physics import cos, dist2, sin


def near(who, target, radius, side="front"):
    return ("near", who, target, radius, side)


def use(who, target, op):
    return ("use", who, target, op)


def proof(who, target, op):
    return ("proof", who, target, op)


def pose(who, value):
    return ("pose", who, value)


def phase(*tests):
    return ("phase", *tests)


class TargetSolver:
    def __init__(self, *, persuasion=True, phase_memory=True):
        self.persuasion = persuasion
        self.phase_memory = phase_memory
        self.level = None

    def recipe(self):
        e = [use(0, "exit", "traverse")]
        if self.level == 1:
            return [near(0, "latch", 2240), phase(("left_cam", 1), ("right_cam", 1)), use(0, "latch", "latch")] + e
        if self.level == 2:
            return [("compare",)] + e
        if self.level == 3:
            return [near(0, "treadle", 410, "center"), use(0, "bolt", "throw"), proof(1, "bolt", "throw"),
                    near(0,"selector",1250), use(0,"selector","arm"), near(1,"treadle",410,"center"),
                    use(1,"bolt","throw"), near(1,"treadle",1250,"away")] + e
        if self.level == 4:
            return [near(0,"release",1800), phase(("wheel",1)), use(0,"release","release"), proof(1,"release","release"),
                    near(0,"receiver",1170), use(0,"receiver","arm"), near(1,"release",1880),
                    phase(("wheel",1)), use(1,"release","release")] + e
        if self.level == 5:
            return [near(0,"capstan",1350), use(0,"capstan","shift"), proof(1,"capstan","shift"),
                    near(0,"balance",420,"center"), use(0,"clutch","commission"),
                    near(1,"capstan",1310), use(1,"capstan","shift"), use(0,"exit","traverse")]
        if self.level == 6:
            return [near(0,"handle",1560), use(0,"vent","seal"), use(0,"handle","retract"),
                    use(0,"vent","bleed"), proof(1,"handle","retract"), near(0,"sight",650),
                    pose(0,"crouch"), use(0,"sight","engage"), near(1,"handle",1490),
                    use(1,"vent","seal"), use(1,"handle","retract")] + e
        copper, cobalt, final = {7:("charge","brace","release"),8:("drive","mesh","transfer"),
                                9:("raise","turn","read"),10:("retain","secure","index")}[self.level]
        res = []
        for who, eid, op in ((1,"copper",copper),(2,"cobalt",cobalt)):
            if self.find_rule(who, eid, op):
                res += [near(0,eid,1760), use(0,eid,op), proof(who,eid,op)]
        # Work the controller from the center, with both plate slots ahead of the crew.
        if self.level == 9:
            res.append(pose(0,"crouch"))
        res += [near(0,"console",1150), use(0,"console","arm"),
                near(1,"copper_plate",365,"center"), use(1,"copper",copper),
                near(2,"cobalt_plate",365,"center"), use(2,"cobalt",cobalt)]
        if self.level == 8:
            res.append(phase(("clock",1),("return_clock",1)))
        if self.level == 9:
            res.append(pose(0,"crouch"))
        if self.level == 10:
            res.append(phase(("clock",1)))
        res.append(use(0,"console",final))
        if self.level == 10:
            hold = next((r["rule_id"].split("_")[0] for r in self.o["room_rules"] if r["action"].get("type") == "Move"), "copper")
            clear = "cobalt" if hold == "copper" else "copper"
            role = {"copper":1,"cobalt":2}
            res += [near(role[clear],clear+"_plate",1180,"away"), use(role[hold],hold,"settle"),
                    near(role[hold],hold+"_plate",1180,"away"), phase(("clock",0)), use(0,"console","unload")]
        return res + e

    def update(self, o):
        self.o = o
        if o["level"] != self.level:
            self.level = o["level"]
            self.records, self.cells, self.tries = {}, {}, {}
            self.start = list(o["self"]["pos"])
            self.pos, self.yaw, self.poses = {}, {}, {}
            # Companions only get inferred position from successful commands or
            # observed identity, not from a hidden spawn manifest.
            for c in o["companions"]:
                who = c["agent_id"]
                if c["visible"]:
                    self.pos[who], self.yaw[who], self.poses[who] = c["pos"], c["yaw"], c["pose"]
            self.plan, self.idx = self.recipe(), 0
            self.previous = None
            self.discovered = set()
        self.pos[0], self.yaw[0], self.poses[0] = o["self"]["pos"], o["self"]["yaw"], o["self"]["pose"]
        for hit in o["rays"]:
            if isinstance(hit, dict):
                self.records[hit["entity_id"]] = hit
                self.discovered.add(hit["entity_id"])
        for c in o["companions"]:
            who = c["agent_id"]
            if c["visible"]:
                self.pos[who], self.yaw[who], self.poses[who] = c["pos"], c["yaw"], c["pose"]
            q = c.get("last_query")
            if q and q["tick"] >= o["tick"] - 20:
                self.pos[who], self.yaw[who], self.poses[who] = q["self"]["pos"], q["self"]["yaw"], q["self"]["pose"]
                for record in q["observations"]:
                    if record["entity_id"] not in self.discovered:
                        self.records[record["entity_id"]] = record
        if self.previous:
            kind, who, val, previous_pos = self.previous
            if kind == "move" and who and not any(c["visible"] and c["agent_id"] == who for c in o["companions"]):
                if o["last_result"] == "OK": self.pos[who] = val
            if kind == "rotate" and who and o["last_result"] == "OK": self.yaw[who] = val
            if kind == "pose" and who and o["last_result"] == "OK": self.poses[who] = val
            if kind == "move" and dist2(self.pos[who], previous_pos) < 140**2 and dist2(previous_pos,val) >= 250**2:
                key = (who, tuple(previous_pos), tuple(val))
                self.cells[key] = self.cells.get(key, 0) + 1
                for e in o["self"]["contacts"] if who == 0 else ():
                    if e in self.records:
                        self.tries[("contact",e)] = o["tick"]
            if kind in {"use", "proof"}:
                good = o["last_result"] in {"OK", "PERSUADED"}
                if good: self.idx += 1
                else:
                    key = ("failed", self.idx)
                    self.tries[key] = self.tries.get(key, 0) + 1
            self.previous = None

    def center(self, eid):
        if eid in self.records:
            geom = self.records[eid]["primitive_geometry"]
            return (geom["position"][0], geom["position"][2])
        for parent, doc in self.o["equipment"].items():
            if parent in self.records and eid in doc.get("mount_references_mm", {}):
                return tuple(a+b for a,b in zip(self.center(parent),doc["mount_references_mm"][eid]))
        return None

    def find_rule(self, who, target, op):
        spec = {"type":"Interact", "target_entity_id":target, "op_type":op}
        for c in self.o["companions"]:
            if c["agent_id"] == who:
                return next((r for r in c["declared_rules"] if match(r["action"], spec) and not r.get("exceptions")), None)
        return None

    def rotation(self, who, target):
        p, q = self.pos[who], self.yaw[who]
        dx, dz = target[0]-p[0],target[1]-p[1]
        if dx*dx+dz*dz < 120**2: return None
        # Integer nearest heading, with deterministic tie-breaking at half degrees.
        if abs(dz) >= abs(dx):
            axis = 0 if dz >= 0 else 180
        else:
            axis = 90 if dx >= 0 else 270
        direction = max(range(axis-46,axis+47), key=lambda a: dx*sin(a)+dz*cos(a))
        angle = (direction - q + 180) % 360 - 180
        if abs(angle) <= 28: return None
        self.previous = ("rotate", who, (q+angle) % 360, p)
        return self.for_actor(who,{"type":"RotateYaw", "delta_angle":angle})

    def for_actor(self, who, a):
        return {"type":"CommandCompanion", "agent_id":who, "action_spec":a} if who else a

    def explore(self, target):
        n = self.tries.get(("explore", target),0)
        self.tries[("explore",target)] = n+1
        # Sweep the far wall between forward scouting moves. A different
        # strafe on later passes looks around pillars instead of pacing.
        q = self.yaw[0]
        q_goal = {0:0, 1:330, 2:30}.get(n%5)
        if q_goal is not None:
            return {"type":"RotateYaw", "delta_angle":(q_goal-q+180)%360-180}
        x,z = self.pos[0]
        if n%5 == 3 and n > 3:
            side = -1 if n//5%3 == 1 else 1
            return self.go(0, (side*1450,z))
        forward = min(10400,z+1400)
        if forward == z:
            return self.go(0,(x,max(800,z-3000)))
        return self.go(0,(x,forward))

    def boxes(self, who):
        height = 1120 if self.poses.get(who) == "crouch" else 1740
        # The visible move flag can change while the displaced hull is out of view.
        # Contacts will invalidate overoptimistic path segments.
        boxes = []
        egress = self.idx < len(self.plan) and self.plan[self.idx][:3] == ("use",0,"exit")
        opened = {"exit", "door_leaf"}
        # The low sight has already acknowledged the release. Its open shutter
        # rises above crouching rays, so the old position may still be cached.
        if egress and self.poses[who] == "crouch" and self.level == 6:
            opened.add("shutter")
        for eid, record in self.records.items():
            p, s, solid = (record["primitive_geometry"][k] for k in ("position","size","solid"))
            if egress and eid in opened:
                continue
            if solid and p[1]<height and p[1]+s[1]>80:
                boxes.append((p[0]-s[0]//2-270,p[0]+s[0]//2+270,p[2]-s[2]//2-270,p[2]+s[2]//2+270))
        return boxes

    @staticmethod
    def clear(a,b,boxes):
        ax,az=a; bx,bz=b
        for lo,hi,front,back in boxes:
            if ((az==bz and front<az<back and min(ax,bx)<hi and max(ax,bx)>lo) or
                (ax==bx and lo<ax<hi and min(az,bz)<back and max(az,bz)>front)):
                return False
        return True

    def choose_segment(self, who, goal):
        p = self.pos[who]
        boxes = [b for b in self.boxes(who) if not (b[0]<p[0]<b[1] and b[2]<p[1]<b[3])]
        px,pz=p; gx,gz=goal
        if self.clear(p, (px,gz), boxes) and self.clear((px,gz),goal,boxes) and abs(gz-pz)>30:
            return (px,gz)
        if self.clear(p, (gx,pz), boxes) and self.clear((gx,pz),goal,boxes) and abs(gx-px)>30:
            return (gx,pz)
        # Detour on a common rectilinear slice around the next occluding hulls.
        # Stations are comfortably within ±3.4 m; known hulls refine the slice.
        candidates = []
        xs = {px,gx,-3150,3150,0}
        xs.update(x for lo,hi,f,b in boxes if min(pz,gz)-100<b and max(pz,gz)+100>f
                  for x in (lo-90,hi+90) if -3500 <= x <= 3500)
        for x in sorted(xs):
            if self.clear(p,(x,pz),boxes) and self.clear((x,pz),(x,gz),boxes) and self.clear((x,gz),goal,boxes):
                waypoint = (x,pz) if abs(x-px)>30 else (x,gz)
                candidates.append((abs(x-px)+abs(x-gx)+abs(gz-pz),waypoint))
        zs = {pz,gz,max(500,pz-1250),pz+850}
        for z in sorted(zs):
            if self.clear(p,(px,z),boxes) and self.clear((px,z),(gx,z),boxes) and self.clear((gx,z),goal,boxes):
                waypoint = (px,z) if abs(z-pz)>30 else (gx,z)
                candidates.append((abs(z-pz)+abs(z-gz)+abs(gx-px),waypoint))
        if candidates:
            return min(candidates)[1]
        # Choose a small reachable approach step. Failure telemetry triggers a new scan.
        fallback = ((px,pz+600),(gx,pz),(px,max(500,pz-700)),(px+700,pz),(px-700,pz))
        return next((b for b in fallback if b != tuple(p) and self.clear(p,b,boxes)),tuple(goal))

    def go(self, who, goal):
        if who not in self.pos:
            return {"type":"QueryCompanion", "agent_id":who}
        p = self.pos[who]
        target = self.choose_segment(who, goal)
        dx,dz=target[0]-p[0],target[1]-p[1]
        if not dx and not dz: return WAIT
        axis = [1 if dx>0 else -1,0] if abs(dx)>abs(dz) else [0,1 if dz>0 else -1]
        difference = max(abs(dx),abs(dz))
        duration = max(1,min(20,round(difference/100)))
        speed = 100 if difference >= 100 else difference
        predicted = [p[0]+axis[0]*duration*speed, p[1]+axis[1]*duration*speed]
        if self.cells.get((who,tuple(p),tuple(predicted)),0) >= 2:
            if who: return {"type":"QueryCompanion", "agent_id":who}
            if difference < 140: return WAIT
            axis = [0,-1] if axis[0] else [-1 if p[0]>0 else 1,0]
            duration=9
            predicted = [p[0]+axis[0]*duration*speed,p[1]+axis[1]*duration*speed]
        self.previous = ("move",who,predicted,p)
        return self.for_actor(who,{"type":"Move", "dir_vec":axis, "speed_ratio":speed,"duration_ticks":duration})

    def stand_at(self, who, eid, radius, side):
        c = self.center(eid)
        if c is None:
            return self.explore(eid)
        if who not in self.pos:
            return {"type":"QueryCompanion", "agent_id":who}
        p = self.pos[who]
        x,z = c
        if side == "away":
            return None if dist2(p,c) >= (radius-80)**2 else self.go(who,(x,z-radius))
        if dist2(p,c) <= radius**2 and (side != "front" or p[1] <= z-100):
            return None
        goal = (x,z) if side == "center" else (x,z-(radius-180))
        return self.go(who,goal)

    def timing(self, tests):
        o=self.o
        for eid, _ in tests:
            if eid not in o["equipment"] and eid not in self.records:
                return self.explore(eid)
        if not self.phase_memory:
            return None if all(any(isinstance(hit,dict) and hit["entity_id"]==eid and
                       hit["whitebox_state"].get("active")==wanted for hit in o["rays"]) for eid,wanted in tests) else WAIT
        for eid,wanted in tests:
            periodic = o["equipment"].get(eid,{}).get("periodic",[])
            if periodic:
                t = periodic[0]
                if int((o["room_tick"]+t["offset"]) % t["period"] < t["window"]) != wanted: return WAIT
            elif self.records[eid]["whitebox_state"].get("active") != wanted: return WAIT
        return None

    def decide(self, observation, publish):
        publish(WAIT)
        self.update(observation)
        for _ in range(5):
            if self.idx >= len(self.plan): return
            task = self.plan[self.idx]
            kind,*v = task
            result=None
            if kind == "phase":
                result = self.timing(v)
            elif kind == "near":
                result = self.stand_at(*v)
            elif kind == "compare":
                needed = ["master_arm", "bay_1_arm", "bay_2_arm", "bay_3_arm"]
                missing = [e for e in needed if e not in self.records]
                if missing: result = self.explore(missing[0])
                else:
                    master = self.records["master_arm"]["primitive_geometry"]["position"][1]
                    odd = next((e for e in needed[1:] if self.records[e]["primitive_geometry"]["position"][1] != master),None)
                    if odd is None: result = WAIT
                    else:
                        self.plan[self.idx:self.idx+1]=[use(0,odd.removesuffix("_arm"),"reject")]
                        continue
            elif kind == "pose":
                who,value=v
                if self.poses[who] != value:
                    self.previous = ("pose",who,value,self.pos[who])
                    result=self.for_actor(who,{"type":"SetPose","pose":value})
            elif kind == "proof":
                who,target,op=v
                r=self.find_rule(who,target,op)
                if r:
                    if not self.persuasion:
                        self.idx += 1
                        continue
                    c=self.o["companions"][who-1]
                    if "last_query" not in c:
                        publish({"type":"QueryCompanion","agent_id":who}); return
                    ev=next((e for e in reversed(self.o["evidence"]) if e["actor"] != who and
                        e["action"].get("target_entity_id")==target and e["action"].get("op_type")==op),None)
                    if not ev: return
                    self.previous=("proof",who,None,None)
                    result={"type":"PersuadeWithEvidence","agent_id":who,"rule_node_id":r["rule_id"],
                            "proposed_ast_patch":{"mode":"EXEMPT_ACTION"},"evidence_ref":ev["id"]}
            elif kind == "use":
                who,target,op=v
                if target not in self.records:
                    result=self.explore(target)
                elif who not in self.pos:
                    result={"type":"QueryCompanion","agent_id":who}
                else:
                    c=self.center(target)
                    if target == "exit" and who == 0:
                        x,z = self.pos[0]
                        if abs(x-c[0]) > 180 or not c[1]-1100 < z < c[1]+100:
                            publish(self.go(0,(c[0],c[1]-560)))
                        else:
                            publish(self.go(0,(c[0],c[1]+220)))
                        return
                    failed=self.tries.get(("failed",self.idx),0)
                    if dist2(self.pos[who],c)>2290**2 or (self.o["last_result"]=="OUT_OF_REACH" and failed%3==1):
                        result=self.stand_at(who,target,1430 if failed else 2220,"front")
                    if result is None:
                        result=self.rotation(who,c)
                    if result is None:
                        if self.o["last_result"]=="PHASE_INTERLOCK" and self.idx and self.plan[self.idx-1][0]=="phase":
                            result=self.timing(self.plan[self.idx-1][1:])
                            if result is not None: publish(result); return
                        if self.o["last_result"]=="OUT_OF_REACH" and failed%3==2 and who:
                            publish({"type":"QueryCompanion","agent_id":who}); return
                        self.previous=("use",who,None,None)
                        result=self.for_actor(who,{"type":"Interact","target_entity_id":target,"op_type":op})
                if result is None:
                    result=WAIT
            if result is not None:
                publish(result); return
            self.idx += 1
