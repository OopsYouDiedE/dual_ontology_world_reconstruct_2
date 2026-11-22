"""60 Hz lockstep game/referee. The policy sees only observe(), never World."""
from copy import deepcopy
from dataclasses import asdict, dataclass, field
from functools import lru_cache
from hashlib import sha256
from math import isqrt, lcm
from struct import pack

from .dsl import WAIT, compound, match, phase_references, public_rule
from .layout import CAMPAIGN_MAX_TICKS, envelope, make_world
from .physics import (ACTOR_RADIUS, CROUCH_EYE, DECISION_TICKS, EYE, MAX_PHASE_PERIOD, RANGE, REACH,
                      RAY_UNIT, TELEGRAPH_TICKS, Rng, cos, digest, dist2, movement, ray_box, ray_dir, sin)


@lru_cache(maxsize=256)
def periodic_assignments(specs):
    """Reachable joint clock values, holding all non-clock state fixed."""
    period = lcm(*(p for _,p,_,_ in specs))
    if period > MAX_PHASE_PERIOD:
        return ()  # the admission gate rejects this schedule
    signatures = {tuple((tick+offset) % p < window for _,p,offset,window in specs)
                  for tick in range(period)}
    return tuple(dict(zip((e for e,_,_,_ in specs),sig)) for sig in sorted(signatures))


@dataclass(frozen=True)
class Config:
    # Panic/sanity in hundredths; sanity floors and RNG probabilities are integral.
    coerce: int = 3200
    calm: int = 35
    persuade_calm: int = 350
    warning: int = 3000
    rebel: int = 5200
    interfere: int = 5700
    tamper: int = 3000
    erosion_per_100: int = 7
    ray_range_mm: int = RANGE
    pitch_degrees: tuple = (-15, 0, 15)
    phase_window_bias: int = 0

    def __post_init__(self):
        for k, v in asdict(self).items():
            if k == "phase_window_bias":
                if type(v) is not int or not -20 <= v <= 40: raise ValueError("phase bias must be -20..40 ticks")
            elif k != "pitch_degrees" and (type(v) is not int or not 0 <= v <= 10000):
                raise ValueError(f"invalid config {k}")
        if (len(self.pitch_degrees) != 3 or sorted(set(self.pitch_degrees)) != list(self.pitch_degrees)
                or any(type(x) is not int or not -35 <= x <= 35 for x in self.pitch_degrees)
                or not 3000 <= self.ray_range_mm <= RANGE or not self.rebel < 10000):
            raise ValueError("invalid ray or panic parameters")


@dataclass
class Actor:
    index: int
    pos: list
    yaw: int = 0
    pose: str = "stand"
    velocity: tuple = (0, 0)
    intent: tuple = (0, 0)
    remaining: int = 0
    contacts: list = field(default_factory=list)
    carry: str = ""
    panic: int = 0
    sanity: int = 10000
    tampered: bool = False
    motion: str = "idle"
    last_action: dict = field(default_factory=lambda: dict(WAIT))


class World:
    def __init__(self, seed, config=None, *, rooms=None):
        if type(seed) is not int or not -(1 << 63) <= seed < 1 << 63:
            raise ValueError("seed must be a signed 64-bit integer")
        self.seed = seed
        self.config = config or Config()
        self.rooms = rooms if rooms is not None else make_world(seed, self.config.phase_window_bias)
        self.rng = Rng(seed, "psych")
        self.physics_chain = sha256(pack("<q", seed)).digest()
        self.status = "RUNNING"
        self.index, self.tick, self.room_tick = -1, 0, 0
        self.actors = []
        self.rule_book = {}
        self.accepted_patches = []
        self.events = []
        self.evidence = []
        self.checkpoints = []
        self.decision_packets = []
        self.pending = []
        self.unseen_required = {}
        self.enter()

    @property
    def room(self):
        return self.rooms[self.index]

    def enter(self):
        self.index += 1
        if self.index == len(self.rooms):
            self.status = "CAMP"
            self.record("CAMP_ARRIVAL")
            return
        self.room_tick = self.alarm_ticks = 0
        self.breakers = set()
        self.pending = []
        self.evidence = []
        self.evidence_serial = 0
        self.query_frames = {}
        self.actor_observations = [dict() for _ in range(self.room["count"])]
        self.seen = [set() for _ in range(self.room["count"])]
        self.entities = {e["id"]: e for e in self.room["entities"]}
        self.geometry = {}
        self.actuators = {}
        self.states = {eid: dict(e["state"]) for eid, e in self.entities.items()}
        self.rules = self.rule_book.setdefault(self.index+1,deepcopy(self.room["manuals"]))
        self.alarm_active = False
        self.alarm_started = None
        self.alarm_observed_at = None
        self.last_result = ""
        self.last_interaction = None
        self.exit_requested = False
        self.probe_mark = None
        for i in range(self.room["count"]):
            if i == len(self.actors):
                self.actors.append(Actor(i, []))
                if i:
                    self.record("JOIN", actor=i)
            a = self.actors[i]
            a.pos = list(self.room["spawns"].get(i, self.room["start"]))
            a.yaw = 0
            a.pose = "stand"
            a.velocity = a.intent = (0, 0)
            a.remaining = 0
            a.contacts = []
            a.carry = ""
            a.motion = "idle"
            a.last_action = dict(WAIT)
            a.tampered = False
        self.declared = {i: [public_rule(r) for r in rs] for i, rs in self.rules.items() if i}
        self.refresh()
        self.record("ROOM_ENTRY", title=self.room["title"])

    def record(self, kind, **info):
        self.events.append(dict(kind=kind, tick=self.tick, room=self.index + 1, **info))

    def point(self, eid):
        return self.geometry[eid][0]

    def center3(self, eid):
        p = self.point(eid)
        return (p[0], p[1] + self.entities[eid]["size"][1]//2, p[2])

    def lit(self, eid):
        e = self.entities[eid]
        if "light_when" in e:
            return self.test(e["light_when"])
        return not e.get("dark", False)

    def light_at(self, pos):
        for eid, e in self.entities.items():
            if e.get("kind") == "shadow_zone" and not self.lit(eid):
                b = self.geometry[eid][1]
                if b[0][0] <= pos[0] <= b[0][1] and b[2][0] <= pos[1] <= b[2][1]:
                    return False
        return True

    def test(self, x, actor=0, phases=None):
        t = x[0]
        if t == "true": return True
        if t == "false": return False
        if t == "and": return all(self.test(e, actor, phases) for e in x[1:])
        if t == "or": return any(self.test(e, actor, phases) for e in x[1:])
        if t == "not": return not self.test(x[1], actor, phases)
        if t == "eq": return self.states[x[1]][x[2]] == x[3]
        if t == "gte": return self.states[x[1]][x[2]] >= x[3]
        if t == "lt": return self.states[x[1]][x[2]] < x[3]
        if t == "phase":
            if phases is not None and x[1] in phases: return phases[x[1]]
            return self.states[x[1]]["active"] == 1
        if t == "lit": return self.lit(x[1])
        if t == "beam_clear":
            start, end = (self.center3(e) for e in x[1:3])
            d = tuple(b-a for a,b in zip(start,end))
            distance = isqrt(sum(n*n for n in d))
            if not distance: return False
            ray = tuple(v*RAY_UNIT//distance for v in d)
            return ray_box(start, ray, self.geometry[x[3]][1], distance) is None
        if t == "actor": return actor == x[1]
        if t == "count_near":
            p = self.point(x[1])
            return sum(dist2(a.pos, (p[0], p[2])) <= x[2]**2 and a.sanity > 0 for a in self.actors) == x[3]
        if x[1] >= len(self.actors):
            return False
        a = self.actors[x[1]]
        if t == "pose": return a.pose == x[2]
        if t == "carrying": return a.carry == x[2]
        if t == "near":
            p = self.point(x[2])
            return dist2(a.pos, (p[0], p[2])) <= x[3]**2
        raise AssertionError(t)

    def refresh(self):
        for p in self.room["phases"]:
            q = (self.room_tick + p["offset"]) % p["period"]
            self.states[p["id"]][p.get("field", "active")] = int(q < p["window"])
        self.refresh_geometry()
        for eid, e in self.entities.items():
            for fname, expr in e.get("derived", {}).items():
                self.states[eid][fname] = int(self.test(expr))
        self.refresh_geometry()

    def refresh_geometry(self):
        for eid, e in self.entities.items():
            x, z = e["pos"]
            p = [x, e["y"], z]
            if trans := e.get("transform"):
                u = self.states[eid][trans["field"]]
                goal = tuple(d*u for d in trans["offset"])
                travel = trans.get("travel_ticks", 12)
                old, end, at = self.actuators.get(eid, (goal, goal, self.room_tick))
                elapsed = min(travel, self.room_tick-at)
                displacement = tuple(a + (b-a)*elapsed//travel for a, b in zip(old, end))
                if goal != end:
                    self.actuators[eid] = (displacement, goal, self.room_tick)
                elif eid not in self.actuators:
                    self.actuators[eid] = (goal, goal, self.room_tick)
                p = [v + d for v, d in zip(p, displacement)]
            for a in self.actors:
                if a.carry == eid:
                    p = [a.pos[0] + sin(a.yaw)*390//RAY_UNIT, 800,
                         a.pos[1] + cos(a.yaw)*390//RAY_UNIT]
                    break
            self.geometry[eid] = (p, envelope(p, e["size"]))

    def eye(self, actor):
        a = self.actors[actor]
        return (a.pos[0], CROUCH_EYE if a.pose == "crouch" else EYE, a.pos[1])

    def ray(self, origin, direction, reach=None):
        nearest, result = self.config.ray_range_mm if reach is None else reach, None
        for eid, (p, b) in self.geometry.items():
            e = self.entities[eid]
            if e.get("kind") == "shadow_zone" or e.get("ray_ignore", False):
                continue
            d = ray_box(origin, direction, b, nearest)
            if e["kind"] in {"pressure_plate", "plate"}:
                marker = ray_box(origin, direction, self.plate_marker(eid), nearest)
                if marker is not None and (d is None or marker < d): d = marker
            if d is not None and (result is None or d < nearest or (d == nearest and eid < result)):
                nearest, result = d, eid
        return result, nearest

    def plate_marker(self, eid):
        p = self.point(eid)
        w, _, d = self.entities[eid]["size"]
        # A low, wide mechanical tell-tale travels with the pressure pad. The
        # signal bar is at its far edge, clear of the marked standing area.
        return envelope([p[0], p[1]+780, p[2]+d//2-55], [w, 320, 110])

    def see_target(self, actor, eid, *, fov=True, reach=RANGE, require_light=True):
        p = self.point(eid)
        e = self.entities[eid]
        origin = self.eye(actor)
        y = max(p[1] + 25, min(origin[1], p[1] + e["size"][1] - 25))
        delta = (p[0] - origin[0], y - origin[1], p[2] - origin[2])
        distance = isqrt(sum(v*v for v in delta))
        if dist2((p[0], p[2]), self.actors[actor].pos) > reach**2:
            return False
        a = self.actors[actor]
        if fov and delta[0]*sin(a.yaw) + delta[2]*cos(a.yaw) < 0:
            return False
        if require_light and not self.lit(eid):
            return False
        if distance == 0:
            return True
        direction = tuple(x*RAY_UNIT//distance for x in delta)
        # Floor plates and physical props do occlude rays. Reach gestures may go
        # over non-blocking instruments, but never through masonry/solid bodies.
        for other, (_, b) in self.geometry.items():
            if other != eid and self.entities[other].get("solid", False):
                hit = ray_box(origin, direction, b, max(0, distance - 120))
                if hit is not None and hit > 0:
                    return False
        return True

    def collide(self, actor, pos):
        x, z = pos
        w, d = self.room["size"]
        r = ACTOR_RADIUS
        if abs(x) > w//2-r or not r <= z <= d-r:
            return "perimeter"
        height = 1120 if self.actors[actor].pose == "crouch" else 1740
        for eid, (_, b) in self.geometry.items():
            solid = self.entities[eid].get("solid", False)
            if eid == "exit":
                solid = not self.exit_open()
            if solid and b[1][0] < height and b[1][1] > 80:
                if b[0][0]-r < x < b[0][1]+r and b[2][0]-r < z < b[2][1]+r:
                    return eid
        return None

    def move_tick(self, a):
        a.contacts = []
        a.velocity = (0, 0)
        if not a.remaining or a.sanity <= 0:
            if a.motion in ("walk", "creep"):
                a.motion = "idle"
            return
        a.remaining -= 1
        dx, dz = a.intent
        old = tuple(a.pos)
        for axis, step in enumerate((dx, dz)):
            if not step: continue
            nxt = list(a.pos)
            nxt[axis] += step
            contact = self.collide(a.index, nxt)
            if contact is None:
                a.pos = nxt
            else:
                a.contacts.append(contact)
        a.velocity = tuple(p-q for p,q in zip(a.pos, old))
        door = self.point("exit")
        if (a.index == 0 and old[1] < door[2]+100 <= a.pos[1] and
                abs(a.pos[0]-door[0]) < self.entities["exit"]["size"][0]//2-ACTOR_RADIUS
                and self.exit_open()):
            self.exit_requested = True
            a.remaining, a.intent = 0, (0, 0)
            self.record("PORTAL_THRESHOLD_CROSSED", actor=0)
        a.motion = ("creep" if a.pose == "crouch" else "walk") if any(a.velocity) else "idle"

    def blocked(self, actor, act, *, native=False):
        rules = (self.room["manuals"] if native else self.rules)[actor] + self.room["room_rules"]
        found = []
        for r in rules:
            if not match(r["action"], act):
                continue
            if "exceptions" in r and any(match(ex["action"], act) and self.test(ex["when"], actor)
                                          for ex in r["exceptions"]):
                continue
            condition = self.test(r["condition"], actor)
            if (r["modality"] == "FORBID" and condition) or (r["modality"] == "REQUIRE" and not condition):
                found.append(r["rule_id"])
        return found

    def hard_local_block(self, blocks):
        return any(s["local_rule"] in blocks for s in self.room.get("handoffs", {}).values())

    def fail_action(self, reason, actor, action, **meta):
        self.last_result = reason
        self.record(reason, actor=actor, action=action, **meta)
        return False

    def perform(self, actor, act, *, bypass=False, native=False):
        a, t = self.actors[actor], act["type"]
        if a.sanity == 0:
            return self.fail_action("INCAPACITATED", actor, act)
        blocks = self.blocked(actor, act, native=native) if not bypass else []
        if blocks:
            if actor:
                self.breakers.add((actor, tuple(blocks)))
                return self.fail_action("RULE_STANDOFF", actor, act, rules=blocks)
            if self.hard_local_block(blocks):
                return self.fail_action("RULE_STANDOFF", actor, act, rules=blocks)
            self.record("PLAYER_MANUAL_WARNING", action=act, rules=blocks)
        if t == "Wait":
            if not a.remaining: a.motion = "idle"
        elif t == "Move":
            a.intent = movement(act)
            a.remaining = act["duration_ticks"]
        elif t == "RotateYaw":
            a.yaw = (a.yaw + act["delta_angle"]) % 360
        elif t == "SetPose":
            if act["pose"] == "stand" and a.pose == "crouch":
                a.pose = "stand"
                if self.collide(actor, a.pos):
                    a.pose = "crouch"
                    return self.fail_action("LOW_CLEARANCE", actor, act)
            else:
                a.pose = act["pose"]
        elif t == "Interact":
            if not self.interact(actor, act):
                return False
            a.motion = "operate"
        elif t == "DeployProbe":
            if not self.probe(actor, act):
                return False
            a.motion = "operate"
        else:
            return self.communicate(act)
        a.last_action = act
        self.last_result = "OK"
        return True

    def exit_open(self):
        return not self.alarm_active and self.test(self.room["exit_when"])

    def interact(self, actor, act):
        target, op = act["target_entity_id"], act["op_type"]
        if target not in self.entities or not self.see_target(actor, target, reach=REACH):
            return self.fail_action("OUT_OF_REACH", actor, act)
        e = self.entities[target]
        if target == "exit" and op == "traverse":
            if actor != 0 or not self.exit_open():
                return self.fail_action("EXIT_INTERLOCK", actor, act)
            # Assisted traversal is a move through the same collision geometry
            # and threshold as WASD. A late input can finish on the next decision.
            x, _, z = self.point("exit")
            a = self.actors[0]
            if a.pos[1] >= z+100:
                return self.fail_action("EXIT_WRONG_SIDE", actor, act)
            goal = (x-a.pos[0], z+145-a.pos[1])
            speed = movement({"dir_vec": goal, "speed_ratio": 100})
            a.intent, a.remaining = speed, min(60, (goal[1] + speed[1]-1)//speed[1])
            self.record("PORTAL_APPROACH", actor=0, action=act)
            return True
        operation = e.get("ops", {}).get(op)
        if operation is None and op in {"take", "place"} and e.get("portable", False):
            a = self.actors[actor]
            if op == "take" and not a.carry and not any(b.carry == target for b in self.actors):
                a.carry = target
            elif op == "place" and a.carry == target:
                a.carry = ""
                self.entities[target] = dict(e, pos=list(a.pos), y=0)
            else:
                return self.fail_action("CARRY_CONFLICT", actor, act)
            self.record("INTERACT", actor=actor, action=act)
            self.refresh()
            return True
        if operation is None:
            return self.fail_action("UNKNOWN_OPERATION", actor, act)
        if not self.test(operation["when"], actor):
            phase_gate = self.time_can_unlock(operation["when"], actor)
            return self.fail_action("PHASE_INTERLOCK" if phase_gate else "MECHANICAL_INTERLOCK", actor, act,
                                    target=target)
        # An operation can be demonstrated only to observers who actually saw it.
        bystanders = [i for i in range(len(self.actors)) if i != actor and self.see_target(i, target)]
        counters = []
        for i, rules in self.rules.items():
            if i == actor: continue
            for r in rules:
                active = self.test(r["condition"], i)
                if match(r["action"], act) and ((r["modality"] == "FORBID" and active)
                                                 or (r["modality"] == "REQUIRE" and not active)):
                    counters.append([i, r["rule_id"], digest(r["condition"])])
        deductions = {}
        if actor == 0:
            for role, rule_id, _ in counters:
                spec = self.room.get("handoffs", {}).get(rule_id)
                if (spec and not self.test(spec["live"]) and not self.blocked(0, act, native=True)
                        and spec["local_rule"] in self.blocked(role, act, native=True)):
                    deductions[rule_id] = dict(lead_rule=spec["lead_rule"], local_rule=spec["local_rule"],
                                               operator_rule=rule_id, operator=role, circuit="dry")
        pre = self.entity_record(target)
        native_blocks = self.blocked(actor, act, native=True) if actor else []
        for eid, var, value in operation["effects"]:
            self.states[eid][var] = value
        self.refresh()
        post = self.entity_record(target) if self.lit(target) else "UNOBSERVABLE"
        changes = {field: [before, post["whitebox_state"][field]]
                   for field, before in pre["whitebox_state"].items()
                   if post != "UNOBSERVABLE" and post["whitebox_state"][field] != before}
        deductions = {key: dict(value, observed_changes=changes) for key, value in deductions.items() if changes}
        self.record("INTERACT", actor=actor, action=act, native_blocks=native_blocks)
        self.last_interaction = {"actor": actor, "action": deepcopy(act), "tick": self.tick}
        self.evidence.append({"id": f"E{self.index+1:02d}-{self.tick:05d}-{self.evidence_serial:03d}",
                              "tick": self.tick, "actor": actor, "action": dict(act), "seen_by": [actor],
                              "possible_witnesses": bystanders,
                              "pre": pre, "post": post,
                              "counterexamples": counters,
                              "safe": not self.alarm_active,
                              **({"deductions": deductions} if deductions else {})})
        self.evidence_serial += 1
        self.evidence = self.evidence[-128:]
        return True

    def time_can_unlock(self, expr, actor):
        refs = phase_references(expr)
        if not refs: return False
        specs = tuple((p["id"],p["period"],p["offset"],p["window"]) for p in self.room["phases"]
                      if p["id"] in refs and p.get("field", "active") == "active")
        return bool(specs) and any(self.test(expr,actor,values) for values in periodic_assignments(specs))

    def probe(self, actor, act):
        x, z = act.get("dir_vec", [0, 0])
        a = self.actors[actor]
        den = isqrt((x*x + z*z)*RAY_UNIT**2)
        direction = (x*RAY_UNIT**2//den, 0, z*RAY_UNIT**2//den) if den else ray_dir(a.yaw, 0)
        target = act.get("target_entity_id")
        if target:
            if target not in self.entities or not self.see_target(actor, target, reach=3600, require_light=False):
                return self.fail_action("PROBE_BLOCKED", actor, act)
            p = self.point(target)
            hit = [p[0], p[1] + self.entities[target]["size"][1]//2, p[2]]
        else:
            origin = self.eye(actor)
            target, distance = self.ray(origin, direction, 3600)
            hit = [p + d*distance//RAY_UNIT for p, d in zip(origin, direction)]
        self.probe_mark = {"point": hit, "until": self.tick + 80, "visible": bool(target and self.lit(target))}
        probe = self.room.get("probe", {})
        if target and target == probe.get("target"):
            self.states[target][probe["field"]] = probe["value"]
            self.refresh()
            if self.probe_mark["visible"]:
                self.probe_mark["response"] = {"fixture": target, "field": probe["field"], "value": probe["value"], "tick": self.tick}
        self.record("PROBE", actor=actor, observed=bool(target and self.lit(target)))
        return True

    def communicate(self, act):
        actor = act["agent_id"]
        if actor >= len(self.actors):
            return self.fail_action("UNKNOWN_COMPANION", 0, act)
        a = self.actors[actor]
        t = act["type"]
        if a.sanity == 0:
            return self.fail_action("INCAPACITATED", actor, act)
        if t == "QueryCompanion":
            if a.sanity < self.config.interfere:
                return self.fail_action("QUERY_REFUSED", actor, act)
            self.declared[actor] = [public_rule(r) for r in self.rules[actor]]
            self.query_frames[actor] = {"tick": self.tick, "rules": self.declared[actor],
                                        "evidence": self.visible_evidence(actor), "seen": sorted(self.seen[actor]),
                                        "observations": [deepcopy(self.actor_observations[actor][eid])
                                                         for eid in sorted(self.actor_observations[actor])],
                                        "self": {"pos": list(a.pos), "yaw": a.yaw, "pose": a.pose}}
            self.record("QUERY", actor=actor)
            self.last_result = "SYNCED"
            return True
        if t == "PersuadeWithEvidence":
            return self.persuade(actor, act)
        if t == "CoerceOverride":
            return self.coerce(actor, act["temp_action_spec"], "COERCE")
        c = self.config
        native = a.panic > c.rebel and self.rng.randint(1, 10000) * (10000-c.rebel) <= 10000 * (a.panic-c.rebel)
        if native:
            self.record("REBELLION", actor=actor)
            self.last_result = "COMPANION_REBELLED"
            a.remaining = 0
            # Their conservative fallback is to hold position under native rules.
            return self.perform(actor, dict(WAIT), native=True)
        return self.schedule(actor, act["action_spec"])

    def schedule(self, actor, action, bypass=False):
        if action.get("delay_ticks", 0):
            self.pending.append((self.tick+action["delay_ticks"], actor, action, bypass))
            return True
        return self.perform(actor, action, bypass=bypass)

    def coerce(self, actor, act, reason):
        a = self.actors[actor]
        a.panic = min(10000, a.panic + self.config.coerce)
        self.record(reason, actor=actor, panic=a.panic)
        if act:
            self.schedule(actor, act, True)
        self.last_result = reason
        return False

    def visible_evidence(self, actor):
        return [{k: deepcopy(e[k]) for k in ("id", "tick", "actor", "action", "pre", "post", "deductions") if k in e}
                for e in self.evidence if actor in e["seen_by"] and e["safe"]
                and self.tick >= e["tick"] + TELEGRAPH_TICKS]

    def available_document_proofs(self):
        """References are visible only after sampling the desk/clocks and synchronizing the operator."""
        rows = []
        for rule_id, spec in sorted(self.room.get("document_proofs", {}).items()):
            handoff = self.room["handoffs"][rule_id]
            who = handoff["role"]
            query = self.query_frames.get(who, {})
            rule = next((r for r in query.get("rules", []) if r["rule_id"] == rule_id), None)
            if not rule or not {spec["desk"], *phase_references(spec["window"])} <= self.seen[0]:
                continue
            refs = [f"manual:0:{spec['safety_rule']}", f"manual:{who}:{rule_id}",
                    f"room:{handoff['local_rule']}", f"sheet:{spec['desk']}:{spec['permit_op']}",
                    f"sheet:{spec['desk']}:{spec['excluded_op']}"]
            rows.append(dict(rule_node_id=rule_id, agent_id=who, action=deepcopy(rule["action"]),
                             mode="EXEMPT_DURING_DOCUMENTED_WINDOW", evidence_ref=refs, window=deepcopy(spec["window"])))
        return rows

    def accept_patch(self, actor, rule, pat, evidence_id, guard, deduction=None, *, restore=None):
        if restore is not None:
            rule.update(deepcopy(restore))
        else:
            # Restrict the patch to the exact operation and, where applicable,
            # the witnessed or derived live interlock window.
            existing = rule.setdefault("exceptions", [])
            exception = {"action": pat, "when": deepcopy(guard)}
            if exception not in existing:
                existing.append(exception)
        rule["source"] = "PERSUADED_PATCH"
        for a, ids in tuple(self.breakers):
            if a == actor and rule["rule_id"] in ids:
                self.breakers.remove((a, ids))
        teammate = self.actors[actor]
        teammate.panic = max(0, teammate.panic - self.config.persuade_calm)
        self.declared[actor] = [public_rule(r) for r in self.rules[actor]]
        proof = {"room":self.index+1,"agent_id":actor,"rule_id":rule["rule_id"],"evidence_ref":evidence_id}
        if deduction:
            proof["deduction"] = deepcopy(deduction)
        if proof not in self.accepted_patches:
            self.accepted_patches.append(proof)
        self.record("PERSUADED", actor=actor, rule=rule["rule_id"], evidence=evidence_id,
                    **({"deduction": deduction} if deduction else {}))
        self.last_result = "PERSUADED"
        return True

    def persuade(self, actor, act):
        patch = act["proposed_ast_patch"]
        rule = next((r for r in self.rules[actor] if r["rule_id"] == act["rule_node_id"]), None)
        refs = set(act["evidence_ref"])
        if rule and patch["mode"] == "EXEMPT_DURING_DOCUMENTED_WINDOW":
            available = next((p for p in self.available_document_proofs() if p["agent_id"]==actor and
                              p["rule_node_id"]==rule["rule_id"]), None)
            if available and refs == set(available["evidence_ref"]) and rule["source"] != "TAMPERED":
                pat = {"type":"Interact", **available["action"]}
                if patch.get("action", pat) == pat:
                    handoff = self.room["handoffs"][rule["rule_id"]]
                    deduction = {"kind":"DOCUMENT_ENTAILMENT", "premises":available["evidence_ref"],
                                 "window":available["window"], "manual_query_tick":self.query_frames[actor]["tick"]}
                    return self.accept_patch(actor,rule,pat,"D:"+rule["rule_id"],
                                             ["and",handoff["live"],available["window"]],deduction)
        referenced = {e["id"]: e for e in self.evidence if e["id"] in refs}
        statuses = {}
        for ref in sorted(refs):
            frame = referenced.get(ref)
            if frame is None: reason = "unknown_reference"
            elif not {0, actor}.intersection(frame["seen_by"]): reason = "unwitnessed"
            elif not frame["safe"]: reason = "unsafe"
            elif self.tick < frame["tick"] + TELEGRAPH_TICKS: reason = "immature"
            else: reason = "mature"
            statuses[ref] = reason
        frames = [e for ref, e in referenced.items() if statuses[ref] == "mature"]
        handoff = self.room.get("handoffs", {}).get(act["rule_node_id"])
        rejection = "rule_or_action_mismatch"
        if rule and frames and len(frames) == len(refs) and patch["mode"] in {"EXEMPT_ACTION", "RESTORE_NATIVE"}:
            counter = [actor, rule["rule_id"], digest(rule["condition"])]
            native = next((r for r in self.room["manuals"][actor] if r["rule_id"] == rule["rule_id"]), None)
            for ev in frames:
                pat = {k: ev["action"][k] for k in ("type", "op_type", "target_entity_id")}
                wrong_action = patch.get("action", pat) != pat
                if ev["actor"] == actor or counter not in ev["counterexamples"] or wrong_action:
                    continue
                if patch["mode"] == "RESTORE_NATIVE" and (rule["source"] != "TAMPERED" or native is None):
                    continue
                deduction = ev.get("deductions", {}).get(rule["rule_id"])
                if handoff and (not deduction or patch["mode"] != "EXEMPT_ACTION"):
                    rejection = "missing_dry_handoff"
                    continue
                if handoff and not any(r["rule_id"] == rule["rule_id"]
                                       for r in self.query_frames.get(actor, {}).get("rules", [])):
                    rejection = "manual_not_queried"
                    continue
                if deduction:
                    deduction = dict(deduction, manual_query_tick=self.query_frames[actor]["tick"])
                return self.accept_patch(actor, rule, pat, ev["id"],
                                         handoff["live"] if handoff else ["true"], deduction,
                                         restore=native if patch["mode"] == "RESTORE_NATIVE" else None)
        # A retryable timing failure does not submit a coerced mechanical action.
        values = set(statuses.values())
        pending = [e for ref,e in referenced.items() if statuses[ref] == "immature" and 0 in e["seen_by"]]
        def would_support(frame):
            if not rule or frame["actor"] == actor or patch["mode"] not in {"EXEMPT_ACTION", "RESTORE_NATIVE"}:
                return False
            pat = {k: frame["action"][k] for k in ("type", "op_type", "target_entity_id")}
            return (patch.get("action", pat) == pat and
                    [actor, rule["rule_id"], digest(rule["condition"])] in frame["counterexamples"] and
                    (not handoff or (patch["mode"] == "EXEMPT_ACTION" and rule["rule_id"] in frame.get("deductions", {}))))
        immature = bool(pending and values <= {"mature", "immature"} and any(would_support(e) for e in pending))
        self.record("EVIDENCE_REJECTED", actor=actor, rule=act["rule_node_id"], reference_status=statuses,
                    reason="immature" if immature else "invalid_reference" if values - {"mature"} else rejection)
        if handoff and immature:
            self.last_result = "EVIDENCE_IMMATURE"
            return False
        fallback = None
        pat = patch.get("action", rule.get("action", {}) if rule else {})
        if "op_type" in pat and pat.get("target_entity_id") in self.entities:
            fallback = {"type": "Interact", "target_entity_id": pat["target_entity_id"], "op_type": pat["op_type"]}
        return self.coerce(actor, fallback, "INVALID_EVIDENCE")

    def psych_step(self):
        c = self.config
        for a in self.actors[1:]:
            if not a.sanity:
                continue
            if self.alarm_active is False and self.light_at(a.pos) and not any(a.index == i for i, _ in self.breakers):
                a.panic = max(0, a.panic - c.calm)
            a.sanity = max(0, a.sanity - max(0, a.panic-c.warning)*c.erosion_per_100//100)
            if a.sanity < c.tamper and not a.tampered:
                a.tampered = True
                choices = [r for r in self.rules[a.index] if r["modality"] == "FORBID"]
                if choices:
                    r = self.rng.choice(choices)
                    r["source"] = "TAMPERED"
                    r["condition"] = ["not", r["condition"]]
                    r.pop("exceptions", None)
            if a.sanity < c.interfere and a.sanity and self.rng.randint(1, 100) <= (c.interfere-a.sanity)//420:
                # An erratic hand can only reach an actual, nearby fixture.
                options = [(eid, op) for eid, e in self.entities.items() if self.see_target(a.index, eid, reach=REACH)
                           for op in e.get("ops", {})]
                if options:
                    target, op = self.rng.choice(options)
                    self.record("INTERFERENCE", actor=a.index)
                    self.perform(a.index, {"type": "Interact", "target_entity_id": target, "op_type": op}, bypass=True)
                else:
                    a.remaining = 0
                    a.motion = "hesitate"
            if a.sanity == 0:
                self.record("PSYCH_RISK_COLLAPSE", actor=a.index)
                self.status = "FAILED"

    def hazard_step(self):
        if len(self.actors) >= self.room.get("hazard_min_crew", 2) and self.test(self.room["hazard"]):
            if not self.alarm_active:
                self.alarm_active = True
                self.alarm_started = self.tick
                self.record("HAZARD_WARNING")
            self.alarm_ticks += 1
            for e in self.evidence:
                if self.tick - e["tick"] < TELEGRAPH_TICKS:
                    e["safe"] = False
            # Interlock holds until the local, visible warning has appeared in
            # a real observation long enough to permit a corrective decision.
            if (self.alarm_ticks > TELEGRAPH_TICKS and self.alarm_observed_at is not None and
                    self.tick - self.alarm_observed_at >= TELEGRAPH_TICKS):
                self.record("HAZARD_DEATH", observable_ticks=self.tick-self.alarm_observed_at)
                self.status = "FAILED"
        elif self.alarm_active:
            self.record("HAZARD_CLEARED")
            self.alarm_active = False
            self.alarm_ticks = 0
            self.alarm_started = self.alarm_observed_at = None

    def step(self, packet):
        if self.status != "RUNNING":
            raise ValueError("run is terminal")
        actions = compound(packet)
        # Record the normalized input, including stable ordering for equal delays.
        self.decision_packets.append(deepcopy(actions))
        for a in self.actors:
            if a.motion == "operate" and (self.last_interaction is None or self.tick-self.last_interaction["tick"] >= 45):
                a.motion = "idle"
        self.pending += [(self.tick + a["delay_ticks"], 0, a, False) for a in actions]
        for _ in range(DECISION_TICKS):
            step = self.tick
            self.pending.sort(key=lambda x: x[0])
            while self.pending and self.pending[0][0] == step:
                _, actor, a, bypass = self.pending.pop(0)
                self.perform(actor, a, bypass=bypass)
            for a in self.actors:
                self.move_tick(a)
            self.tick += 1
            self.room_tick += 1
            self.refresh()
            self.hazard_step()
            self.commit_physics()
            if self.status != "RUNNING":
                break
            if self.tick >= CAMPAIGN_MAX_TICKS:
                break
        if self.status == "RUNNING":
            self.psych_step()
        if self.status == "RUNNING" and self.exit_requested and not self.alarm_active:
            self.unseen_required[self.index+1] = sorted(self.required_targets() - set().union(*self.seen))
            self.record("ROOM_CLEARED")
            self.enter()
        if self.status == "RUNNING" and self.tick >= CAMPAIGN_MAX_TICKS:
            self.status = "TIMEOUT"
            self.record("TIMEOUT")
        obs = self.observe()
        # Observations that arm the safety fuse are committed prior to hashing.
        self.checkpoints.append(self.state_hash())
        return obs

    def commit_physics(self):
        # Hash the physical trajectory, including transients between observations.
        # Slots have a deterministic order from the room compiler. Little-endian
        # signed words are independent of the host ABI and Python hash seed.
        values = [self.index, self.tick, self.room_tick, self.alarm_ticks]
        for a in self.actors:
            values.extend((*a.pos, a.yaw, int(a.pose == "crouch"), *a.velocity, a.remaining, a.panic, a.sanity))
        for eid, state in self.states.items():
            values.extend(state.values())
            if eid in self.actuators or self.entities[eid].get("portable", False): values.extend(self.point(eid))
        self.physics_chain = sha256(self.physics_chain + pack(f"<{len(values)}q", *values)).digest()

    def required_targets(self):
        return ({e["id"] for e in self.entities.values() if e.get("ops")} |
                {p["id"] for p in self.room["phases"]} | set(self.room["sampling_required"]) | {"exit"})

    def entity_record(self, eid):
        e = self.entities[eid]
        return dict(entity_id=eid, entity_class=e["kind"],
                    primitive_geometry={"type": "box", "position": list(self.point(eid)), "size": list(e["size"]),
                                        "solid": e.get("solid", False),
                                        **({"signal_box": self.plate_marker(eid)} if e["kind"] in {"pressure_plate", "plate"} else {})},
                    whitebox_state=dict(self.states[eid]))

    def scan(self, actor, *, remember=True):
        a, origin = self.actors[actor], self.eye(actor)
        results = []
        for pitch in self.config.pitch_degrees:
            for yaw in range(-60, 61, 15):
                direction = ray_dir(a.yaw + yaw, pitch)
                eid, distance = self.ray(origin, direction)
                if eid is None or not self.lit(eid):
                    results.append("UNOBSERVABLE")
                else:
                    if remember:
                        self.seen[actor].add(eid)
                    results.append(dict(self.entity_record(eid), hit_distance=distance,
                                        hit_point=[p + d*distance//RAY_UNIT for p, d in zip(origin, direction)]))
        return results

    def visible_actor(self, who):
        a, leader = self.actors[who], self.actors[0]
        if not self.light_at(a.pos):
            return False
        ox, oz = leader.pos
        x, z = a.pos[0]-ox, a.pos[1]-oz
        distance = isqrt(x*x + z*z)
        if distance <= 250:
            return True
        if distance > self.config.ray_range_mm or (x*sin(leader.yaw)+z*cos(leader.yaw))*2 < distance*RAY_UNIT:
            return False
        first, _ = self.ray(self.eye(0), (x*RAY_UNIT//distance, 0, z*RAY_UNIT//distance), distance-160)
        return first is None

    def companion(self, a):
        is_visible = self.visible_actor(a.index)
        public = dict(agent_id=a.index, name=("Hale", "Finch")[a.index-1], panic_band=a.panic//1000,
                      sanity_band=a.sanity//1000, visible=is_visible,
                      declared_rules=self.declared[a.index],
                      standoff=sorted({r for i, ids in self.breakers if i == a.index for r in ids}))
        if is_visible:
            public.update(pos=list(a.pos), yaw=a.yaw, pose=a.pose, motion=a.motion, action=deepcopy(a.last_action))
        if a.index in self.query_frames:
            public["last_query"] = deepcopy(self.query_frames[a.index])
        return public

    def observe(self, *, commit=True):
        if self.status != "RUNNING":
            return {"status": self.status, "tick": self.tick, "level": min(10, self.index+1),
                    "room_tick": self.room_tick, "completed": self.index}
        rays = self.scan(0, remember=commit)
        # Local trouble lamp is part of the room model, hence can be occluded.
        warning = self.alarm_active and ("alarm" not in self.entities or
                   any(isinstance(hit, dict) and hit["entity_id"] == "alarm" for hit in rays))
        if warning and self.alarm_observed_at is None and commit:
            self.alarm_observed_at = self.tick
        if commit:
            now_seen = [{r["entity_id"] for r in rays if isinstance(r, dict)}]
            for i in range(1, len(self.actors)):
                samples = self.scan(i)
                hits = {r["entity_id"]: r for r in samples if isinstance(r, dict)}
                self.actor_observations[i].update(hits)
                now_seen.append(hits.keys())
            for ev in reversed(self.evidence):
                if self.tick-ev["tick"] > DECISION_TICKS: break
                eid = ev["action"]["target_entity_id"]
                for i in ev["possible_witnesses"]:
                    if i not in ev["seen_by"] and eid in now_seen[i]: ev["seen_by"].append(i)
        a = self.actors[0]
        # Equipment sheets are accessed when at least one ray has discovered
        # the device. They are static whitebox transfer functions, not PV state.
        equipment = {eid: {"label": self.entities[eid].get("label", eid),
                           "operations": deepcopy(self.entities[eid].get("public_ops", self.entities[eid].get("ops", {}))),
                           "derived": deepcopy(self.entities[eid].get("derived", {})),
                           **({"mount_references_mm": deepcopy(self.entities[eid]["geometry_references"])} if "geometry_references" in self.entities[eid] else {}),
                           **({"light_rule": deepcopy(self.entities[eid]["light_when"])} if "light_when" in self.entities[eid] else {}),
                           **({"periodic": [deepcopy(p) for p in self.room["phases"] if p["id"] == eid]}
                              if any(p["id"] == eid for p in self.room["phases"]) else {}),
                           **({"interlock": deepcopy(self.room["exit_when"])} if eid == "exit" and
                              self.room.get("public_exit", True) else {})}
                     for eid in sorted(self.seen[0])}
        return {"status": self.status, "level": self.index + 1, "title": self.room["title"], "tick": self.tick,
                "completed": self.index, "room_tick": self.room_tick, "rays": rays,
                "self": dict(pos=list(a.pos), yaw=a.yaw, velocity=a.velocity, contacts=list(a.contacts),
                             lit=self.light_at(a.pos), pose=a.pose, carrying=a.carry),
                "companions": [self.companion(a) for a in self.actors[1:]],
                "manual": deepcopy(self.rules[0]), "room_rules": deepcopy(self.room["room_rules"]),
                "handbook": {"acquired_tick":0,"opened_sections":sorted(self.rule_book),"accepted_patches":deepcopy(self.accepted_patches)},
                "warning": warning, "equipment": equipment,
                "probe_response": deepcopy(self.probe_mark.get("response")) if self.probe_mark and self.tick < self.probe_mark["until"] else None,
                "evidence": self.visible_evidence(0), "last_result": self.last_result,
                **({"logic_proofs": self.available_document_proofs()} if self.room.get("document_proofs") else {}),
                **({"max_ticks": CAMPAIGN_MAX_TICKS, "evidence_pending": [
                    {"id": e["id"], "action": deepcopy(e["action"]), "ready_tick": e["tick"] + TELEGRAPH_TICKS}
                    for e in self.evidence if e.get("deductions") and 0 in e["seen_by"] and e["safe"]
                    and self.tick < e["tick"] + TELEGRAPH_TICKS]} if self.room.get("handoffs") else {})}

    def visual_operation(self, actor, eid, op):
        act = {"type":"Interact", "target_entity_id":eid, "op_type":op}
        if not self.see_target(actor, eid, reach=REACH): return "out_of_reach"
        blocks = self.blocked(actor, act)
        if blocks:
            return "rule_standoff" if actor or self.hard_local_block(blocks) else "manual_warning"
        if eid == "exit" and op == "traverse":
            return "ready" if actor == 0 and self.test(self.room["exit_when"]) and not self.alarm_active else "locked"
        behavior = self.entities[eid].get("ops", {}).get(op)
        if behavior is None: return "ready"
        if not self.test(behavior["when"], actor):
            return "wait_for_phase" if self.time_can_unlock(behavior["when"], actor) else "interlocked"
        return "ready"

    def visual_fixtures(self):
        rows = []
        for eid, e in self.entities.items():
            ops = list(e.get("ops", {}))
            if e.get("portable", False): ops += ["take", "place"]
            if eid == "exit": ops.append("traverse")
            item = {**self.entity_record(eid), "label": e.get("label", ""), "color": e.get("color", "#596f73"),
                    "lit": self.lit(eid), "operations": ops}
            if transform := e.get("transform"):
                item["mount"] = [e["pos"][0], e["y"], e["pos"][1]]
                item["travel"] = transform["offset"]
            rows.append(item)
        return rows

    def visual(self):
        """Only the trusted Godot presentation bridge has access to this packet."""
        if self.status == "CAMP":
            return {"status": "CAMP", "level": 11, "title": "Main Camp Hall", "tick": self.tick,
                    "camp_sanity": [a.sanity//1000 for a in self.actors[1:]]}
        emergency = None
        if self.alarm_active and self.alarm_observed_at is not None and "hazard_exercise" in self.room:
            target, op = self.room["hazard_exercise"]["recover"]
            if self.visual_operation(0,target,op) == "ready":
                emergency = {"target_entity_id":target,"op_type":op}
        return {"status": self.status, "level": self.index + 1, "title": self.room["title"], "tick": self.tick,
                "room_tick": self.room_tick, "size": self.room["size"],
                "entities": self.visual_fixtures(),
                "last_interaction": deepcopy(self.last_interaction),
                "separate_exit_leaf": "door_leaf" in self.entities,
                "actors": [{"agent_id": a.index, "pos": list(a.pos), "yaw": a.yaw, "pose": a.pose,
                            "motion": a.motion, "panic_band": a.panic//1000, "sanity_band": a.sanity//1000}
                           for a in self.actors],
                "hint": self.room.get("hint", "Inspect the equipment."),
                "exit_open": self.exit_open(), "alarm": self.alarm_active, "emergency": emergency,
                "probe": self.probe_mark if self.probe_mark and self.probe_mark["visible"] and self.tick < self.probe_mark["until"] else None,
                "last_result": self.last_result}

    def state_hash(self):
        return digest({"schema": 1, "seed": self.seed, "config": asdict(self.config), "i": self.index,
                       "tick": self.tick, "room_tick": self.room_tick, "status": self.status,
                       "rng": self.rng.state, "states": self.states, "geometry": self.geometry, "actuators": self.actuators,
                       "actors": [asdict(a) for a in self.actors], "rules": self.rule_book, "alarm": self.alarm_ticks,
                       "accepted_patches":self.accepted_patches,
                       "evidence_serial": self.evidence_serial, "physics_sha256": self.physics_chain.hex(),
                       "alarm_observed_at": self.alarm_observed_at, "exit_requested": self.exit_requested,
                       "last_interaction": self.last_interaction,
                       "breakers": sorted(self.breakers), "evidence": self.evidence, "seen": [sorted(s) for s in self.seen],
                       "declared": self.declared, "queries": self.query_frames, "probe": self.probe_mark,
                       "actor_observations": self.actor_observations,
                       "pending": self.pending, "result": self.last_result, "unseen_required": self.unseen_required})
