"""Interactive, unmetered black-box JSONL interface for authoring and evaluation.

Only the data-only policy runner can certify live fuel; this tool is for
collecting provenance or developing a contestant's policy against observations.
"""
import argparse
import json
from pathlib import Path
import sys

from .gates import evaluate_seed
from .oracle import replay
from .world import Config, World


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--seed", type=int)
    modes.add_argument("--verify-replay", type=Path)
    args = parser.parse_args()
    if args.verify_replay:
        blob = json.loads(args.verify_replay.read_text(encoding="utf-8"))
        world = replay(blob["seed"], blob["packets"], Config(**blob["config"]))
        good = (world.checkpoints == blob["hashes"] and world.state_hash() == blob["state_sha256"]
                and world.events == blob["events"])
        print(json.dumps({"match":good,"status":world.status,"state_sha256":world.state_hash()}))
        return 0 if good else 1
    checked, gate = evaluate_seed(args.seed)
    if not (gate["zero_panic"] and gate["reproducible"] and gate["sampling_pass"]):
        print(json.dumps({"error":"seed did not pass admission"}), flush=True)
        return 1
    run = World(args.seed)
    print(json.dumps(run.observe(), ensure_ascii=True), flush=True)
    for line in sys.stdin:
        if run.status != "RUNNING": break
        try:
            if len(line) > 8192: raise ValueError("decision is too large")
            packet = json.loads(line)
            result = run.step(packet)
        except (KeyError, TypeError, ValueError) as e:
            result = {"error":str(e)}
        print(json.dumps(result, ensure_ascii=True), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
