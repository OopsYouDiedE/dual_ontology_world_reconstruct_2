"""Line-delimited local presentation worker for the Godot scene."""
import argparse
import json
from pathlib import Path
import sys

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from core.rule_evaluation.gates import evaluate_seed, hazard_checkpoint, run_hazard_exercise
from core.rule_evaluation.oracle import resolve_witness_packet
from core.rule_evaluation.world import World


def reply(world):
    return {"visual": world.visual(), "observation": world.observe(commit=False)}


def risk_samples(world, room_index):
    if world.index+1 != room_index: return []
    spec = world.room.get("hazard_exercise")
    outcome = run_hazard_exercise(world,spec) if spec else None
    return [(tag,reply(state)) for tag,state in zip(("before-warning","warning","recovered"),outcome)] if outcome else []


def make_samples(seed):
    run = World(seed)
    run.observe()
    points = []
    for room in run.rooms:
        stage = run.index
        local, supplemental = [], []
        if stage == 1: local.append(("comparison-row",reply(run)))
        for i, act in enumerate(room["witness"]):
            packet = resolve_witness_packet(run, act)
            acts = packet if isinstance(packet, list) else [packet]
            has_interaction = any(a.get("type") in {"SetPose", "Interact"} or
                a.get("action_spec", {}).get("type") == "Interact" for a in acts)
            before = reply(run) if has_interaction else None
            if hazard_checkpoint(run,packet):
                supplemental += risk_samples(run,stage+1)
            run.step(packet)
            if stage == 5 and any(a.get("type") == "SetPose" and a.get("pose") == "crouch" for a in acts):
                supplemental.extend([("sight-standing",before),("sight-crouching",reply(run))])
            if stage == 8 and any(a.get("op_type") == "arm" for a in acts):
                supplemental.append(("optics-blocked",reply(run)))
            if stage == 8 and any(a.get("action_spec",{}).get("op_type") == "turn" for a in acts):
                supplemental.append(("optics-clear",reply(run)))
            if stage == 0 and i == 0:
                local.append(("cams-offset",reply(run)))
            if stage != run.index:
                local.append(("exit", before or reply(run)))
                break
            if has_interaction and run.last_result == "OK":
                if not local or (stage == 0 and i == 4):
                    local.append(("before", before))
                local.append((f"operation-{i+1:02d}", reply(run)))
        if len(local) > 6:
            local = local[:2] + local[-4:]
        for label, sample in local + supplemental:
            sample["review"] = f"{stage + 1:02d}-{label}"
            points.append(sample)
    campus = reply(run)
    campus["review"] = "11-camp"
    points.append(campus)
    return points


def archived_warning(seed, room_index):
    """Construct the real warning state for interactive renderer QA only."""
    run = World(seed)
    run.observe()
    for room in run.rooms:
        for row in room["witness"]:
            packet = resolve_witness_packet(run,row)
            if run.index+1 == room_index and (spec := hazard_checkpoint(run,packet)):
                states = run_hazard_exercise(run,spec)
                if not states: raise ValueError("warning was not reproducible")
                return states[1]
            run.step(packet)
    raise ValueError("no warning rehearsal at that room")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=1)
    modes=parser.add_mutually_exclusive_group()
    modes.add_argument("--review", action="store_true")
    modes.add_argument("--rehearse-warning", type=int, choices=[4,10])
    modes.add_argument("--film", choices=["admitted", "development"])
    args = parser.parse_args()
    world, samples, index = World(args.seed), [], 0
    if args.review:
        samples = make_samples(args.seed)
    elif args.rehearse_warning:
        world = archived_warning(args.seed,args.rehearse_warning)
    elif args.film != "development":
        # Admission never changes the selected seed or exposes the constructive witness.
        _, gate = evaluate_seed(args.seed)
        if not (gate["zero_panic"] and gate["sampling_pass"] and gate["reproducible"]):
            print(json.dumps({"error": f"seed rejected by admission: {gate}"}), flush=True)
            return 1
    world.observe()
    def emit(data):
        print(json.dumps(data, separators=(",", ":"), ensure_ascii=True), flush=True)
    emit(samples[0] if samples else reply(world))
    for line in sys.stdin:
        try:
            packet = json.loads(line)
            op = packet.get("op")
            if op == "quit":
                return 0
            if op == "review_next" and samples:
                index = min(len(samples) - 1, index + 1)
                emit(samples[index])
            elif op == "review_prev" and samples:
                index = max(0, index - 1)
                emit(samples[index])
            elif op == "step" and not samples:
                if world.status == "RUNNING":
                    world.step(packet["action"])
                snapshot = reply(world)
                if args.film and world.status == "CAMP":
                    snapshot["film_state_sha256"] = world.state_hash()
                emit(snapshot)
            else:
                raise ValueError("invalid operation in current mode")
        except (TypeError, KeyError, ValueError) as e:
            emit({"error": str(e)})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
