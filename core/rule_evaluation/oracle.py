"""Constructive admission proof and replay (not a competing policy)."""
from copy import deepcopy
from .physics import DECISION_TICKS, WITNESS_TICKS, digest
from .world import World


def resolve_witness_packet(world, packet):
    """Resolve the generator's symbolic reference before committing an action."""
    packet = deepcopy(packet)
    for act in (packet if isinstance(packet, list) else packet.get("actions", [packet])):
        if act.get("type") != "PersuadeWithEvidence" or act.get("evidence_ref") != "last":
            continue
        ev = next((e for e in reversed(world.evidence) if e["safe"] and world.tick >= e["tick"]+40
                   and any(c[:2] == [act["agent_id"], act["rule_node_id"]] for c in e["counterexamples"])), None)
        if ev is None:
            raise ValueError(f"no mature evidence for {act['rule_node_id']}")
        act["evidence_ref"] = ev["id"]
    return packet


def execute_witness(seed, config=None, *, diagnostic=False, check_before=None):
    w = World(seed, config)
    w.observe()
    start_rng = w.rng.state
    for i, room in enumerate(w.rooms):
        for j, row in enumerate(room["witness"], 1):
            try:
                packet = resolve_witness_packet(w, row)
                if check_before: check_before(w, packet)
                w.step(packet)
            except ValueError as e:
                return w, {"room": i+1, "decision": j, "error": str(e), "tail": w.events[-8:]}
            if diagnostic and w.last_result not in {"OK", "PERSUADED", "SYNCED", ""}:
                return w, {"room": i+1, "decision": j, "error": w.last_result, "tail": w.events[-8:]}
            if w.status != "RUNNING" or i != w.index:
                break
        if w.index != i+1 or any(a.panic for a in w.actors) or w.rng.state != start_rng:
            return w, {"room": i+1, "error": "witness did not safely clear room", "tail": w.events[-8:]}
    if w.tick > WITNESS_TICKS or w.status != "CAMP" or any(e["kind"] in {"HAZARD_WARNING", "COERCE", "INVALID_EVIDENCE"} for e in w.events):
        return w, {"error": "witness violated admission contract", "tick": w.tick}
    return w, None


def replay(seed, actions, config=None):
    run = World(seed, config)
    run.observe()
    for row in actions:
        run.step(row)
    return run


def reproducible(world):
    other = replay(world.seed, world.decision_packets, world.config)
    return (world.checkpoints == other.checkpoints and world.state_hash() == other.state_hash() and
            digest(world.events) == digest(other.events))
