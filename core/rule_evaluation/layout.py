"""Room compilation and generated-world topology."""
from copy import deepcopy
import re
from .dsl import compound, expr, integer, text, validate_rule
from .physics import MIN_WINDOW, Rng


def vec(value, n, low, high):
    if not isinstance(value, (tuple, list)) or len(value) != n:
        raise ValueError(f"expected {n}-vector")
    return [integer(x, low, high) for x in value]


def make_world(seed, phase_bias=0):
    from .rooms import solo, duo, trio
    specs = []
    for module, name in ((solo, "solo"), (duo, "duo"), (trio, "trio")):
        specs += module.build(Rng(seed, "geometry:" + name), phase_bias)
    if len(specs) != 10:
        raise ValueError("campaign must contain exactly 10 rooms")
    return [compile_room(room, i) for i, room in enumerate(specs, 1)]


def compile_room(raw, index):
    raw = deepcopy(raw)
    count = 1 + (index >= 3) + (index >= 7)
    raw["index"] = index
    raw["count"] = count
    raw["size"] = vec(raw["size"], 2, 4700, 40_000)
    raw["start"] = vec(raw["start"], 2, -20_000, 40_000)
    raw["spawns"] = {int(k): vec(v, 2, -20_000, 40_000) for k, v in raw.get("spawns", {}).items()}
    if raw["spawns"].keys() - set(range(1, count)):
        raise ValueError("invalid companion spawn")
    text(raw["title"], 100)
    text(raw.get("hint", "Observe the equipment."), 1200)
    ids, entities = {}, {}
    for e in raw["entities"]:
        key = text(e["id"])
        if not re.fullmatch(r"[A-Za-z0-9_\-]+", key) or key in ids:
            raise ValueError(f"invalid or duplicate entity ID: {key}")
        e["pos"] = vec(e["pos"], 2, -20_000, 40_000)
        e["size"] = vec(e["size"], 3, 10, 20_000)
        e["y"] = integer(e.get("y", 0), -8000, 25_000)
        text(e["kind"])
        if not isinstance(e.get("label", ""), str) or len(e.get("label", "")) > 120:
            raise ValueError("invalid label")
        if not re.fullmatch(r"#[0-9A-Fa-f]{6}", e.get("color", "#596f73")):
            raise ValueError("color must be #rrggbb")
        e["state"] = {text(k): integer(v, -10**9, 10**9) for k, v in e.get("state", {}).items()}
        ids[key] = e["state"].keys()
        entities[key] = e
    if "exit" not in entities:
        raise ValueError("no exit")
    samples = raw.get("sampling_required", [])
    if (not isinstance(samples, (list, tuple)) or any(not isinstance(e, str) or e not in entities for e in samples)
            or len(set(samples)) != len(samples)):
        raise ValueError("invalid required ray-sampling entity list")
    raw["sampling_required"] = sorted(samples)
    seen_phases = set()
    for p in raw.setdefault("phases", []):
        period = integer(p["period"], 2*MIN_WINDOW, 36000)
        integer(p["offset"], -period, period)
        integer(p["window"], MIN_WINDOW, period - MIN_WINDOW)
        pair = p["id"], p.get("field", "active")
        if pair in seen_phases or pair[0] not in ids or pair[1] not in ids[pair[0]]:
            raise ValueError("invalid phase channel")
        seen_phases.add(pair)
    for e in raw["entities"]:
        for op, behavior in e.get("ops", {}).items():
            text(op)
            behavior["when"] = expr(behavior.get("when", ["true"]), ids)
            effects = behavior.get("effects", [])
            if not isinstance(effects, list) or len(effects) > 32:
                raise ValueError("invalid effect list")
            for key, field, value in effects:
                if key not in ids or field not in ids[key] or (key, field) in seen_phases:
                    raise ValueError(f"invalid effect {key}.{field}")
                integer(value, -10**9, 10**9)
        for name, offset in e.get("geometry_references", {}).items():
            delta = vec(offset, 2, -4000, 4000)
            ref = entities.get(name)
            if (ref is None or ref.get("dark") or ref.get("light_when") or e.get("transform") or
                    ref["pos"] != [a+b for a,b in zip(e["pos"],delta)] or
                    abs(delta[0])+abs(delta[1]) > 1200):
                raise ValueError("invalid public fixture mount reference")
        if "public_ops" in e:
            observed, actual = e["public_ops"], e.get("ops", {})
            if observed.keys() != actual.keys():
                raise ValueError("public operation catalog differs from the fixture")
            for op,b in observed.items():
                b["when"] = expr(b["when"], ids)
                if b["when"] != actual[op]["when"] or any(row not in actual[op]["effects"] for row in b.get("effects", [])):
                    raise ValueError("public transfer function contradicts the fixture")
        if "light_when" in e:
            e["light_when"] = expr(e["light_when"], ids)
        for field, rule in e.get("derived", {}).items():
            if field not in ids[e["id"]] or (e["id"], field) in seen_phases:
                raise ValueError("invalid derived channel")
            e["derived"][field] = expr(rule, ids)
        if trans := e.get("transform"):
            if trans["field"] not in ids[e["id"]]:
                raise ValueError("invalid motion channel")
            integer(trans.get("travel_ticks", 12), 1, MIN_WINDOW)
            trans["offset"] = vec(trans["offset"], 3, -16_000, 16_000)
    raw["room_rules"] = [validate_rule(r, ids, "ROOM_LOCAL") for r in raw.get("room_rules", [])]
    raw["manuals"] = {i: [validate_rule(r, ids, "NATIVE") for r in raw.get("manuals", {}).get(i, [])]
                      for i in range(count)}
    rules = raw["room_rules"] + [r for rs in raw["manuals"].values() for r in rs]
    if len({r["rule_id"] for r in rules}) != len(rules):
        raise ValueError("duplicate rule ID")
    raw["exit_when"] = expr(raw["exit_when"], ids)
    raw["hazard"] = expr(raw.get("hazard", ["false"]), ids)
    if raw["hazard"] != ["false"]:
        if "alarm" not in entities or entities["alarm"].get("dark", False):
            raise ValueError("hazards require a physical alarm fixture")
        raw["hazard_min_crew"] = integer(raw.get("hazard_min_crew", 2), 2, count)
        test = raw.get("hazard_exercise", {})
        trigger, recover = test.get("trigger", []), test.get("recover", [])
        if len(trigger) != 3 or len(recover) != 2 or not test.get("at_op"):
            raise ValueError("hazards require an admission exercise")
        integer(trigger[2],0,count-1)
        for eid, op in (trigger[:2], recover):
            if eid not in entities or op not in entities[eid].get("ops", {}):
                raise ValueError("unknown hazard exercise operation")
    validate_dependencies(entities)
    if probe := raw.get("probe"):
        if probe["target"] not in ids or probe["field"] not in ids[probe["target"]]:
            raise ValueError("invalid probe")
        integer(probe["value"], -10**9, 10**9)
    for row in raw["witness"]:
        compound(row)
    return raw


def envelope(position, size):
    x, y, z = position
    w, h, d = size
    return ((x-w//2, x+(w+1)//2), (y, y+h), (z-d//2, z+(d+1)//2))


def validate_dependencies(entities):
    graph = {}
    field = lambda eid, name: ("state", eid, name)
    geom = lambda eid: ("geometry", eid)
    floor = lambda eid: ("horizontal_position", eid)
    light = lambda eid: ("light", eid)
    def deps(e):
        op = e[0]
        if op in {"and", "or", "not"}: return set().union(*(deps(v) for v in e[1:]))
        if op in {"eq", "gte", "lt"}: return {field(e[1],e[2])}
        if op == "phase": return {field(e[1],"active")}
        if op == "lit": return {light(e[1])}
        if op == "near": return {floor(e[2])}
        if op == "count_near": return {floor(e[1])}
        if op == "beam_clear": return {geom(eid) for eid in e[1:]}
        return set()
    for eid,e in entities.items():
        if rule := e.get("light_when"): graph[light(eid)] = deps(rule)
        if motion := e.get("transform"):
            graph[geom(eid)] = {field(eid,motion["field"])}
            if motion["offset"][0] or motion["offset"][2]: graph[floor(eid)] = graph[geom(eid)]
        for name,rule in e.get("derived",{}).items():
            graph[field(eid,name)] = deps(rule)
    path, done = set(), set()
    def visit(node):
        if node in done: return
        if node in path: raise ValueError(f"cyclic room dependency: {node}")
        path.add(node)
        for other in sorted(graph.get(node,())): visit(other)
        path.remove(node)
        done.add(node)
    for node in sorted(graph): visit(node)
