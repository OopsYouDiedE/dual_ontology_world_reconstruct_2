"""Typed, bounded rule and action language. No executable strings or callbacks."""
from copy import deepcopy

PERSONAL = {"Move", "RotateYaw", "SetPose", "Wait", "Interact", "DeployProbe"}
COMM = {"QueryCompanion", "CommandCompanion", "PersuadeWithEvidence", "CoerceOverride"}
WAIT = {"type": "Wait"}
ACTION_PARAMS = {
    "Move":{"dir_vec","speed_ratio","duration_ticks"}, "RotateYaw":{"delta_angle"}, "Wait":set(),
    "SetPose":{"pose"}, "Interact":{"target_entity_id","op_type"},
    "DeployProbe":{"target_entity_id","target","dir_vec"}, "QueryCompanion":{"agent_id"},
    "CommandCompanion":{"agent_id","action_spec"}, "CoerceOverride":{"agent_id","temp_action_spec"},
    "PersuadeWithEvidence":{"agent_id","rule_node_id","proposed_ast_patch","evidence_ref"},
}


def integer(v, a, b):
    if type(v) is not int or not a <= v <= b:
        raise ValueError(f"expected integer in [{a}, {b}]")
    return v


def text(v, limit=80):
    if not isinstance(v, str) or not v or len(v) > limit:
        raise ValueError("expected nonempty bounded string")
    return v


def direction(v):
    if not isinstance(v, (list, tuple)) or len(v) != 2:
        raise ValueError("dir_vec must be [x,z]")
    return [integer(v[0], -1000, 1000), integer(v[1], -1000, 1000)]


def action(a, *, nested=False):
    if not isinstance(a, dict) or len(a) > 8:
        raise ValueError("action must be a bounded object")
    t = a.get("type")
    if not isinstance(t, str) or t not in PERSONAL | (set() if nested else COMM):
        raise ValueError("unknown action type")
    if a.keys() - ACTION_PARAMS[t] - {"type","delay_ticks"}:
        raise ValueError("unknown action parameter")
    out = {"type": t, "delay_ticks": integer(a.get("delay_ticks", 0), 0, 19)}
    if t == "Move":
        out.update(dir_vec=direction(a.get("dir_vec")), speed_ratio=integer(a.get("speed_ratio", 100), 0, 100),
                   duration_ticks=integer(a.get("duration_ticks", 20), 1, 20))
    elif t == "RotateYaw":
        out["delta_angle"] = integer(a.get("delta_angle"), -360, 360)
    elif t == "SetPose":
        if a.get("pose") not in ("stand", "crouch"):
            raise ValueError("invalid pose")
        out["pose"] = a["pose"]
    elif t == "Interact":
        out.update(target_entity_id=text(a.get("target_entity_id")), op_type=text(a.get("op_type")))
    elif t == "DeployProbe":
        out["dir_vec"] = direction(a.get("dir_vec", [0, 0]))
        if "target_entity_id" in a or "target" in a:
            out["target_entity_id"] = text(a.get("target_entity_id", a.get("target")))
    elif t in COMM:
        out["agent_id"] = integer(a.get("agent_id"), 1, 2)
        if t == "CommandCompanion":
            out["action_spec"] = action(a.get("action_spec"), nested=True)
        if t == "CoerceOverride":
            out["temp_action_spec"] = action(a.get("temp_action_spec"), nested=True)
        if t == "PersuadeWithEvidence":
            out["rule_node_id"] = text(a.get("rule_node_id"))
            ev = a.get("evidence_ref")
            if isinstance(ev, list) and 1 <= len(ev) <= 8:
                ev = [text(item) for item in ev]
            else:
                ev = [text(ev)]
            patch = a.get("proposed_ast_patch")
            if not isinstance(patch, dict) or len(patch) > 2:
                raise ValueError("patch must be a bounded object")
            out.update(evidence_ref=ev, proposed_ast_patch={"mode": text(patch.get("mode"))})
            if "action" in patch:
                out["proposed_ast_patch"]["action"] = pattern(patch["action"])
    return out


def compound(packet):
    raw = packet if isinstance(packet, list) else packet.get("actions", [packet]) if isinstance(packet, dict) else []
    if not isinstance(raw, list) or not 1 <= len(raw) <= 6:
        raise ValueError("expected 1..6 ordered actions")
    actions = [action(row) for row in raw]
    return sorted(actions, key=lambda row: row["delay_ticks"])


def pattern(p):
    keys = {"type", "op_type", "target_entity_id", "pose"}
    if not isinstance(p, dict) or not p or p.keys() - keys:
        raise ValueError("invalid action pattern")
    return {k: text(v) for k, v in p.items()}


def match(p, a):
    return all(a.get(k) == v for k, v in p.items())


def expr(e, ids, depth=0):
    if not isinstance(e, (tuple, list)) or not e or depth > 12 or not isinstance(e[0], str):
        raise ValueError(f"invalid expression: {e}")
    op, *v = e
    if op in {"and", "or"} and 1 <= len(v) <= 16:
        return [op, *(expr(x, ids, depth+1) for x in v)]
    if op == "not" and len(v) == 1:
        return [op, expr(v[0], ids, depth+1)]
    if op in {"true", "false"} and not v:
        return [op]
    if op in {"eq", "gte", "lt"} and len(v) == 3 and v[0] in ids and v[1] in ids[v[0]]:
        return [op, *v[:2], integer(v[2], -10**9, 10**9)]
    if op == "phase" and len(v) == 1 and v[0] in ids and "active" in ids[v[0]]:
        return [op, *v]
    if op == "lit" and len(v) == 1 and v[0] in ids:
        return [op, *v]
    if op == "beam_clear" and len(v) == 3 and all(e in ids for e in v) and len(set(v)) == 3:
        return [op, *v]
    if op in {"near", "carrying"} and len(v) == (3 if op == "near" else 2) and v[1] in ids:
        return [op, integer(v[0], 0, 2), v[1], *([integer(v[2], 1, 20_000)] if op == "near" else [])]
    if op == "pose" and len(v) == 2 and v[1] in {"crouch", "stand"}:
        return [op, integer(v[0], 0, 2), v[1]]
    if op == "actor" and len(v) == 1:
        return [op, integer(v[0], 0, 2)]
    if op == "count_near" and len(v) == 3 and v[0] in ids:
        return [op, v[0], integer(v[1], 1, 20_000), integer(v[2], 0, 3)]
    raise ValueError(f"invalid expression: {e}")


def phase_references(expr):
    op = expr[0]
    if op == "phase": return {expr[1]}
    if op in {"and", "or", "not"}: return set().union(*(phase_references(e) for e in expr[1:]))
    return set()


def validate_rule(rule, ids, source):
    expected = {"rule_id", "scope", "modality", "condition", "action", "source"}
    if not expected <= rule.keys() or rule["source"] != source:
        raise ValueError("incomplete rule")
    if rule["scope"] not in {"SELF", "ROOM", "GLOBAL"} or rule["modality"] not in {"FORBID", "REQUIRE", "PERMIT"}:
        raise ValueError("invalid scope or modality")
    result = {"rule_id": text(rule["rule_id"]), "scope": rule["scope"], "modality": rule["modality"],
              "source": source, "condition": expr(rule["condition"], ids), "action": pattern(rule["action"])}
    if result["action"].get("target_entity_id", "") not in ids and "target_entity_id" in result["action"]:
        raise ValueError("rule references nonexistent target")
    if "label" in rule:
        result["label"] = text(rule["label"], 240)
    return result


def public_rule(rule):
    result = deepcopy(rule)
    if result["source"] == "TAMPERED":
        result["source"] = "NATIVE"
    return result
