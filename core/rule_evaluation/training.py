"""Run a policy against the public development fixtures using the shared lane."""
import argparse
import json
from pathlib import Path

from .fuel import ENTRY_FUEL, STANDARD_FUEL
from .sandbox import Program
from .world import World

TRAINING = (101, 113, 127, 139, 149, 163)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('policy', type=Path)
    p.add_argument('--seeds', type=int, nargs='+', choices=TRAINING, default=TRAINING)
    p.add_argument('--log', type=Path, help='Optional black-box JSONL (observations, decisions, compute); single seed')
    args = p.parse_args()
    if args.log and len(args.seeds) != 1:
        p.error('--log requires exactly one public seed')
    compiled = Program(args.policy.read_text(encoding='utf-8-sig'))
    log = args.log.open('w', encoding='utf-8') if args.log else None
    try:
        for seed in args.seeds:
            w, lane = World(seed), compiled.start()
            last_room = 0
            caps = errors = 0
            first_error = None
            o = w.observe()
            while w.status == 'RUNNING':
                d = lane(o, ENTRY_FUEL if o['level'] != last_room else STANDARD_FUEL)
                last_room = o['level']
                caps += d.exhausted
                errors += bool(d.fault)
                if d.fault and first_error is None:
                    first_error = d.fault
                if log:
                    log.write(json.dumps({'observation':o, 'decision':d.__dict__}, separators=(',', ':'))+'\n')
                o = w.step(d.actions)
            print(json.dumps({'seed':seed, 'completed':w.index,
                              'status':w.status, 'tick':w.tick, 'last_result':w.last_result,
                              'fuel_cap_hits':caps, 'faults':errors, 'first_fault':first_error}), flush=True)
    finally:
        if log:
            log.close()


if __name__ == '__main__':
    main()
