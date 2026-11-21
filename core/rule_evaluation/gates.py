"""Hard tests over generated instances, separate from contestant scoring."""
from copy import deepcopy
from functools import lru_cache
from math import lcm

from .dsl import phase_references
from .oracle import execute_witness, reproducible
from .physics import MIN_WINDOW, TELEGRAPH_TICKS, canonical


def phase_projection(expr, data):
    """Three-valued projection: non-temporal terms stay unknown."""
    op = expr[0]
    if op == "true": return True
    if op == "false": return False
    if op == "phase": return data.get(expr[1])
    if op == "not":
        item = phase_projection(expr[1], data)
        return None if item is None else not item
    if op in {"and", "or"}:
        vals = [phase_projection(x, data) for x in expr[1:]]
        if op == "and": return False if False in vals else True if all(v is True for v in vals) else None
        return True if True in vals else False if all(v is False for v in vals) else None
    return None


@lru_cache(maxsize=1024)
def min_periodic_window(values):
    if not any(values): return 0
    if all(values): return len(values)
    start = values.index(False)
    rotated = values[start:] + values[:start]
    groups, n = [], 0
    for v in rotated:
        if v: n += 1
        elif n: groups.append(n); n = 0
    if n: groups.append(n)
    return min(groups)


def timing_problems(room):
    phases = {p["id"]: p for p in room["phases"]}
    for e in room["entities"]:
        for op, b in e.get("ops", {}).items():
            names = sorted(phase_references(b["when"]) & phases.keys())
            if not names: continue
            periods = [phases[n]["period"] for n in names]
            period = lcm(*periods)
            if period > 36_000:
                yield {"tag": "TEMPORAL_PERIOD_UNCERTIFIED", "target": e["id"], "op": op}
                continue
            windows = tuple(
                phase_projection(b["when"], {n: (tick+phases[n]["offset"]) % phases[n]["period"] < phases[n]["window"]
                                            for n in names}) is not False
                for tick in range(period))
            length = min_periodic_window(windows)
            if length < MIN_WINDOW:
                yield {"tag": "TWITCH_EXECUTION_FAIL", "target": e["id"], "op": op, "min_ticks": length}


def operate(target, action):
    return {"type":"Interact", "target_entity_id":target, "op_type":action}


def hazard_checkpoint(world, packet):
    """Locate an exercise checkpoint on the safe trace (whitebox only)."""
    spec = world.room.get("hazard_exercise")
    return spec if spec and any(a.get("op_type") == spec["at_op"] for a in
        (packet if isinstance(packet,list) else packet.get("actions",[packet]))) else None


def run_hazard_exercise(world, spec):
    """Isolated branch from a safe replay, shared by renderer review and admission."""
    case = deepcopy(world)
    target, verb, who = spec["trigger"]
    wait = {"type":"Wait"}
    for _ in range(120):
        if case.test(case.entities[target]["ops"][verb]["when"],who): break
        case.step(wait)
    else: return None
    dangerous = operate(target, verb)
    baseline = deepcopy(case)
    case.step({"type":"CommandCompanion", "agent_id":who,"action_spec":dangerous} if who else dangerous)
    if not (case.status == "RUNNING" and case.observe(commit=False)["warning"]): return None
    warning = deepcopy(case)
    case.step(operate(*spec["recover"]))
    if case.status != "RUNNING" or case.alarm_active: return None
    return baseline,warning,case


def evaluate_seed(seed, config=None):
    hazard_outcomes = {}
    def check_before(w, packet):
        spec = hazard_checkpoint(w, packet)
        if not spec: return
        level = w.index+1
        experiment = run_hazard_exercise(w, spec)
        if not experiment:
            hazard_outcomes[level] = {"warning_visible": False, "recoverable": False, "fatal_after_ticks": None}
            return
        baseline, warning, rescued = experiment
        stamp = warning.tick
        for _ in range(4):
            if warning.status != "RUNNING": break
            warning.step({"type":"Wait"})
        death = next((e for e in reversed(warning.events) if e["kind"] == "HAZARD_DEATH"),None)
        hazard_outcomes[level] = {"warning_visible":True,"recoverable":rescued.status == "RUNNING",
                                  "fatal_after_ticks":death["tick"]-stamp if death else None,
                                  "observed_warning_ticks":death.get("observable_ticks") if death else None}
    world, failure = execute_witness(seed, config, diagnostic=True, check_before=check_before)
    problems = [{"room": room["index"], **issue} for room in world.rooms for issue in timing_problems(room)]
    for row in world.events:
        if row["kind"] == "HAZARD_DEATH" and row.get("observable_ticks", 0) < TELEGRAPH_TICKS:
            problems.append({"tag": "UNTELEGRAPHED_DEATH", "room": row["room"], "tick": row["tick"]})
    for level, missing in world.unseen_required.items():
        problems.extend({"tag": "RAY_GAP_MISS", "room": level, "target": e} for e in missing)
    for room in world.rooms:
        if room["hazard"] == ["false"]: continue
        result = hazard_outcomes.get(room["index"],{})
        if (not result.get("warning_visible") or not result.get("recoverable") or
                (result.get("observed_warning_ticks") or 0) < TELEGRAPH_TICKS):
            problems.append({"tag":"UNTELEGRAPHED_DEATH", "room":room["index"], "exercise":result})
    projection_shapes, live_counterexamples = [], {}
    proven = set()
    for event in world.events:
        if event["kind"] == "PERSUADED":
            proven.add((event["room"],event["actor"],event["rule"]))
        if event["kind"] == "INTERACT":
            for rule in event.get("native_blocks", []):
                if (event["room"],event["actor"],rule) in proven:
                    live_counterexamples.setdefault(event["room"], []).append({
                        "actor":event["actor"], "rule":rule, "tick":event["tick"], "action":event["action"]})
    for room in world.rooms:
        shapes = [canonical([{k: r[k] for k in ("condition","action","modality")} for r in rules])
                  for rules in room["manuals"].values()]
        distinct = len(set(shapes)) == room["count"] and "[]" not in shapes
        projection_shapes.append(distinct)
        if not distinct:
            problems.append({"tag":"NON_DISTINCT_RULE_PROJECTION", "room":room["index"]})
        if failure is None and room["count"] > 1 and room["index"] not in live_counterexamples:
            problems.append({"tag":"UNCERTIFIED_RULE_STANDOFF", "room":room["index"]})
    consistent = reproducible(world)
    return world, {"seed": seed, "zero_panic": failure is None, "witness_ticks": world.tick,
                   "witness_error": failure, "reproducible": consistent, "sampling_pass": not bool(problems),
                   "invalid_design_defects": problems, "hazard_exercises": hazard_outcomes,
                   "distinct_manual_shapes":all(projection_shapes), "live_counterexamples":live_counterexamples,
                   "state_sha256": world.state_hash(),
                   "physical_sha256":world.physics_chain.hex()}
