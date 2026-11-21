"""Reproducible batch reports and frozen roster enrollment."""
import argparse
from collections import Counter
from dataclasses import asdict
from hashlib import sha256
import json
from pathlib import Path
import platform
import sys

from .dsl import WAIT, compound
from .fuel import ENTRY_FUEL, STANDARD_FUEL, PolicyVM, TrustedPython
from .gates import evaluate_seed
from .oracle import reproducible
from .physics import Rng, digest
from .world import Config, World

# Seed sets are release artifacts; change them only when versioning the benchmark.
STANDARD = (0, 1, 2, 3, 4, 5, 6, 7, 11, 17, 31, 42, 71, 107, 151, 991)
HOLDOUT = (-912032, -8856, -17, 91023, 182163, 689421, 997003, 570078119)
INVALID = {"UNTELEGRAPHED_DEATH", "RAY_GAP_MISS", "TWITCH_EXECUTION_FAIL", "HIDDEN_MECHANIC_LEAK_OR_CONFLICT"}


def unique(seq):
    return list(dict.fromkeys(seq))


def load_data(path, limit=10_000_000):
    blob = path.read_bytes()
    if len(blob) > limit: raise ValueError(f"input {path} is too large")
    return json.loads(blob.decode("utf-8-sig")), sha256(blob).hexdigest()


class TracePolicy:
    def __init__(self, actions):
        self.steps = iter(actions)

    def decide(self, observation, publish):
        publish(next(self.steps, WAIT))


class ReflexV1:
    """Frozen greedy ablation: walk, use visible fixtures, and turn on contact."""
    def __init__(self):
        self.last = None

    def decide(self, o, publish):
        publish(WAIT)
        x, z = o["self"]["pos"]
        q = o["self"]["yaw"]
        for hit in o["rays"][9:18]:
            if not isinstance(hit, dict): continue
            eid = hit["entity_id"]
            if hit["hit_distance"] > 1700 or (eid == self.last and o["last_result"] == "OK"): continue
            ops = o["equipment"].get(eid, {}).get("operations", {})
            if eid == "exit" or ops:
                publish({"type":"Interact", "target_entity_id":eid, "op_type":"traverse" if eid == "exit" else next(iter(ops))})
                self.last = eid
                return
        if o["self"]["contacts"] or o["room_tick"] % 200 == 180:
            publish({"type":"RotateYaw", "delta_angle":90})
        else:
            from .physics import sin, cos
            publish({"type":"Move", "dir_vec":[sin(q)//1000, cos(q)//1000], "speed_ratio":70, "duration_ticks":20})


def diagnose(world, budget):
    if world.status == "CAMP": return []
    rows = [e for e in world.events if e["room"] == world.index+1]
    counts = Counter(e["kind"] for e in rows)
    tags = []
    if any(e["kind"] == "HAZARD_DEATH" and e["observable_ticks"] < 40 for e in rows):
        tags.append("UNTELEGRAPHED_DEATH")
    if counts.get("PSYCH_RISK_COLLAPSE") or (counts.get("REBELLION", 0) + counts.get("INTERFERENCE", 0) > 1):
        tags.append("PSYCH_RISK_COLLAPSE")
    if world.breakers or counts.get("RULE_STANDOFF", 0) > 1:
        tags.append("MULTI_AGENT_DEADLOCK")
    if counts["PHASE_INTERLOCK"] >= 2:
        tags.append("TEMPORAL_PHASE_ERROR")
    if budget["exhausted_without_candidate"] or (budget["exhausted"] > budget["decisions"] // 4):
        tags.append("ANYTIME_BUDGET_BOTTLENECK")
    if not tags and world.status == "TIMEOUT":
        # A viable clue was never acquired by this contestant; the separately
        # admitted witness demonstrated its sampling coverage in this seed.
        queried = {eid for frame in world.query_frames.values() for eid in frame["seen"]}
        if world.required_targets() - world.seen[0] - queried:
            tags.append("ACTIVE_SENSING_DEFICIT")
    return tags or ["UNRESOLVED_PLANNING_FAILURE"]


def score_run(seed, policy, config=None):
    w = World(seed, config)
    obs = w.observe()
    last_level = None
    budget = dict(fuel=0, exhausted=0, exhausted_without_candidate=0, submitted=0, decisions=0)
    while w.status == "RUNNING":
        d = policy(obs, ENTRY_FUEL if last_level != obs["level"] else STANDARD_FUEL)
        last_level = obs["level"]
        budget["fuel"] += d.fuel
        budget["exhausted"] += d.exhausted
        budget["exhausted_without_candidate"] += (d.exhausted and d.candidates == 0)
        budget["submitted"] += d.candidates
        budget["decisions"] += 1
        obs = w.step(d.actions)
    persuasion = sum(e["kind"] == "PERSUADED" for e in w.events)
    false_persuasion = sum(e["kind"] == "INVALID_EVIDENCE" for e in w.events)
    coupled = set()
    for room in w.rooms:
        i = room["index"]
        used = [r for r in w.events if r["room"] == i]
        targets = {p["id"] for p in room["phases"]}
        phased = {(e["id"], op) for e in room["entities"] for op, b in e.get("ops", {}).items()
                  if any(f'"phase","{target}"' in json.dumps(b["when"], separators=(",", ":")) for target in targets)}
        if (any(r["kind"] == "INTERACT" and r["actor"] for r in used)
            and any(r["kind"] == "PERSUADED" for r in used)
            and any((r.get("action",{}).get("target_entity_id"),r.get("action",{}).get("op_type")) in phased
                    for r in used if r["kind"] == "INTERACT")):
            coupled.add(i)
    completed = w.index
    survived = w.status == "CAMP"
    stats = {"status": w.status, "completed": completed, "tick": w.tick, "score": round(0.8*survived+0.02*completed, 4),
             "persuaded": persuasion, "persuasion_accuracy": persuasion/(persuasion+false_persuasion) if persuasion+false_persuasion else None,
             "sanity_retained": (sum(a.sanity for a in w.actors[1:])/(10000*(len(w.actors)-1))) if len(w.actors)>1 else None,
             "coupled_phase_persuasion_rooms": sorted(coupled), "compute": budget, "failure_tags": diagnose(w, budget),
             "unseen_registered_fixtures": w.unseen_required, "reproducible": reproducible(w), "state_sha256": w.state_hash()}
    if not survived:
        rows = [e for e in w.events if e["room"] == w.index+1]
        team_samples = w.seen[0] | {e for frame in w.query_frames.values() for e in frame["seen"]}
        stats["failure_context"] = {
            "room":w.index+1, "room_tick":w.room_tick, "last_result":w.last_result,
            "events":dict(sorted(Counter(e["kind"] for e in rows).items())),
            "unseen_targets":sorted(w.required_targets() - team_samples),
            "open_rule_conflicts":[{"actor":a,"rule_ids":list(ids)} for a,ids in sorted(w.breakers)],
        }
    return w, stats


def summarize(results):
    return {"count": len(results), "clear_rate": sum(r["status"] == "CAMP" for r in results)/len(results),
            "mean_depth": sum(r["completed"] for r in results)/len(results),
            "mean_score": sum(r["score"] for r in results)/len(results),
            "reproducible_rate": sum(r["reproducible"] for r in results)/len(results)}


def optional_mean(results, key):
    rows = [r[key] for r in results if r[key] is not None]
    return sum(rows)/len(rows) if rows else None


def main():
    from .solver import TargetSolver
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=["standard", "holdout", "both"], default="standard")
    parser.add_argument("--seeds", nargs="+", type=int)
    parser.add_argument("--random-seeds", type=int, default=0)
    parser.add_argument("--seed-key", type=int, default=1)
    parser.add_argument("--roster", nargs="+", choices=["target", "reflex", "no_persuasion", "no_phase_memory", "sol"], default=["target", "reflex", "sol"])
    sol_input = parser.add_mutually_exclusive_group()
    sol_input.add_argument("--sol-traces", type=Path)
    sol_input.add_argument("--sol-policy", type=Path)
    parser.add_argument("--vm", type=Path)
    parser.add_argument("--config", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--gates-only", action="store_true")
    parser.add_argument("--require-acceptance", action="store_true")
    args = parser.parse_args()
    if not 0 <= args.random_seeds <= 1000:
        parser.error("--random-seeds must be in [0,1000]")
    config = Config(**load_data(args.config)[0]) if args.config else Config()
    roster = {"target": lambda seed: TrustedPython(TargetSolver()), "reflex": lambda seed: TrustedPython(ReflexV1()),
              "no_persuasion": lambda seed: TrustedPython(TargetSolver(persuasion=False)),
              "no_phase_memory": lambda seed: TrustedPython(TargetSolver(phase_memory=False))}
    metadata = {"target":{"id":"circuit-regression-v1", "status":"enrolled"}, "reflex":{"id":"reflex-v1", "status":"enrolled"},
                "no_persuasion":{"id":"circuit-regression-v1/no-persuasion", "status":"enrolled"},
                "no_phase_memory":{"id":"circuit-regression-v1/no-phase-memory", "status":"enrolled"},
                "sol":{"status":"UNENROLLED", "reason":"Supply a versioned Sol-authored policy via --sol-policy; --sol-traces is diagnostic only."}}
    sol = None
    if args.sol_policy:
        spec, sha = load_data(args.sol_policy, 128_000)
        if (spec.get("model") != "gpt-6.2-sol" or not spec.get("revision") or not spec.get("provenance")
                or not spec.get("ability_profile") or not isinstance(spec.get("program"), list)):
            parser.error("Sol enrollment requires model, immutable revision, provenance, ability_profile, and VM program")
        try: PolicyVM(spec["program"])
        except ValueError as e: parser.error(str(e))
        roster["sol"] = lambda seed: PolicyVM(spec["program"])
        metadata["sol"] = {"status":"VM_POLICY", "id":spec["model"], "revision":spec["revision"], "sha256":sha,
                           "policy_artifact_provenance":spec["provenance"], "ability_profile":spec["ability_profile"],
                           "live_compute_certified": True}
    if args.sol_traces:
        sol, sha = load_data(args.sol_traces)
        if sol.get("model") != "gpt-6.2-sol" or not sol.get("revision") or not isinstance(sol.get("runs"), dict):
            parser.error("Sol trace format requires model=gpt-6.2-sol, immutable revision, and runs keyed by seed")
        def sol_roster(seed):
            source = sol["runs"][str(seed)]
            if not isinstance(source, list) or not 1 <= len(source) <= 1800:
                raise ValueError("Sol trace must contain 1..1800 decision packets")
            return TrustedPython(TracePolicy([compound(a) for a in source]))
        roster["sol"] = sol_roster
        metadata["sol"] = {"status":"TRACE_REPLAY", "id":sol["model"], "revision":sol["revision"], "sha256":sha,
                           "live_compute_certified": False}
    args.roster = unique(args.roster)
    if args.vm:
        vm, sha = load_data(args.vm, 128_000)
        roster["vm"] = lambda seed: PolicyVM(vm)
        metadata["vm"] = {"status":"enrolled", "sha256":sha}
        args.roster.append("vm")
    if args.seeds:
        seeds = args.seeds
    else:
        seeds = list(STANDARD if args.suite == "standard" else HOLDOUT if args.suite == "holdout" else STANDARD+HOLDOUT)
    rng = Rng(args.seed_key,"benchmark-holdout")
    seeds = unique(seeds + [rng.randint(-(1 << 63), (1 << 63)-1) for _ in range(args.random_seeds)])
    args.out.mkdir(parents=True, exist_ok=True)
    traces = args.out / "replays"
    traces.mkdir(exist_ok=True)
    policy_sources = {p.name: sha256(p.read_bytes()).hexdigest() for p in sorted(Path(__file__).parent.glob("*.py"))}
    proof_sources = {p.name: sha256(p.read_bytes()).hexdigest() for p in sorted((Path(__file__).parent/"rooms").glob("*.py"))}
    output = {"schema":1,"runtime":{"implementation":platform.python_implementation(),"version":platform.python_version(),
                "standard_fuel":STANDARD_FUEL, "room_entry_fuel":ENTRY_FUEL, "sources":policy_sources, "room_templates":proof_sources},
              "config":asdict(config),"roster":{name:metadata[name] for name in args.roster},"seeds": seeds,"per_seed": []}
    for seed in seeds:
        try:
            oracle, gate = evaluate_seed(seed, config)
        except (ValueError, KeyError, TypeError) as e:
            oracle = None
            tag = "HIDDEN_MECHANIC_LEAK_OR_CONFLICT" if any(x in str(e) for x in ("transfer function","operation catalog")) else "DESIGN_SCHEMA_REJECTED"
            gate = {"seed":seed,"zero_panic":False,"reproducible":False,"sampling_pass":False,
                    "witness_error":str(e),"invalid_design_defects":[{"tag":tag,"detail":str(e)}]}
        row = {"gate": gate, "results": {}}
        output["per_seed"].append(row)
        if oracle is not None: save_replay(traces, seed, "oracle", oracle)
        admitted = gate["zero_panic"] and gate["reproducible"] and gate["sampling_pass"]
        if admitted and not args.gates_only:
            for name in args.roster:
                if name not in roster or (name == "sol" and sol is not None and str(seed) not in sol["runs"]):
                    continue
                run, stats = score_run(seed, roster[name](seed), config)
                row["results"][name] = stats
                stats["execution_efficiency"] = min(1.0, oracle.tick/run.tick) if stats["status"] == "CAMP" else None
                stats["reasoning_operations_per_executed_action"] = stats["compute"]["fuel"]/max(1,sum(e["kind"] == "INTERACT" for e in run.events))
                save_replay(traces, seed, name, run)
        print(f"seed={seed} admitted={admitted} " + " ".join(f"{k}:{v['completed']}/10" for k,v in row["results"].items()), flush=True)
    gates = [r["gate"] for r in output["per_seed"]]
    output["validity"] = {key:sum(r[key] for r in gates)/len(seeds) for key in ("zero_panic","reproducible","sampling_pass")}
    output["validity"]["invalid_failure_count"] = sum(len(r["invalid_design_defects"]) for r in gates)
    summaries = output["summary"] = {}
    for name in args.roster:
        results = [r["results"][name] for r in output["per_seed"] if name in r["results"]]
        summaries[name] = summarize(results) if results else None
        if results:
            for k in ("execution_efficiency","persuasion_accuracy","sanity_retained","reasoning_operations_per_executed_action"):
                summaries[name][k] = optional_mean(results,k)
            summaries[name]["mechanism_coupling_rate"] = sum(len(r["coupled_phase_persuasion_rooms"]) for r in results)/(len(results)*10)
    target, sol_results = summaries.get("target"), summaries.get("sol")
    output["discrimination"] = {k:target[k]-sol_results[k] if target and sol_results and
                                  target[k] is not None and sol_results[k] is not None else None
                                  for k in ("mean_score","execution_efficiency","persuasion_accuracy","sanity_retained")}
    contestant_consistent = all(v["reproducible"] for row in output["per_seed"] for v in row["results"].values())
    output["all_contestant_replays_match"] = contestant_consistent
    # Frozen traces measure depth but are not a certified live, metered Sol policy.
    output["release_accepted"] = bool(output["validity"] == {"zero_panic":1.,"reproducible":1.,"sampling_pass":1.,"invalid_failure_count":0}
        and target and target["count"] == len(seeds) and target["clear_rate"] >= 0.9 and sol_results
        and sol_results["count"] == len(seeds) and sol_results["clear_rate"] == 0
        and metadata["sol"].get("live_compute_certified", False) and contestant_consistent)
    (args.out / "report.json").write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"validity": output["validity"], "summary": summaries, "release_accepted":output["release_accepted"]}, indent=2))
    return 1 if (any(r[key] < 1 for r in [output["validity"]] for key in ("zero_panic","reproducible","sampling_pass"))
                 or (args.require_acceptance and not output["release_accepted"])) else 0


def save_replay(traces, seed, name, run):
    path = traces / f"{seed}.{name}.json"
    path.write_text(json.dumps({"schema":1, "seed":seed, "config":asdict(run.config), "policy":name,
                                "packets":run.decision_packets,"hashes":run.checkpoints,"events":run.events,
                                "state_sha256": run.state_hash()}, separators=(",", ":")), encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
