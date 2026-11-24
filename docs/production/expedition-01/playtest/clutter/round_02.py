"""Round 02: compare two arrangements of the same furnished kit in Godot."""
import argparse
import json
import math

from design_review import ROOM, SEED, render
from run import RUNTIME, evaluate_rooms

OUTPUT = RUNTIME / 'design-review/round-02'
NAMES = ('Opposing Bays', 'Shared Apron')


def length(path):
    return round(sum(math.dist(a, b) for a, b in zip(path, path[1:])), 2)


def compare(seed):
    key = dict(room_id=ROOM, seed=seed, mode='furnished', density=1.0, max_layers=3)
    report = evaluate_rooms([dict(key, arrangement=a) for a in ('opposed', 'shared_apron')], workspace=OUTPUT)
    left, right = report['rooms']
    a, b = left['layout'], right['layout']
    inventory = lambda layout: sorted((i['id'], i['kind'], i['size'], i['support']) for i in layout['items'])
    fronts = lambda layout: [s['route'][-1][2] for s in layout['stations']]
    rules = {
        'same_envelope_doors_main_route_and_keepout': all(a[k] == b[k] for k in
            ('room_size', 'door_width', 'route', 'route_clear_half_width')),
        'same_furniture_kit': inventory(a) == inventory(b),
        'opposite_work_bays_vs_same_wall': fronts(a)[0] * fronts(a)[1] < 0 < fronts(b)[0] * fronts(b)[1],
        'separate_entries_vs_shared_apron': (a['stations'][0]['route'][0] != a['stations'][1]['route'][0]
            and b['stations'][0]['route'][:2] == b['stations'][1]['route'][:2]),
    }
    report['comparison'] = {'seed': seed, 'shared_constraints': rules, 'candidates': [
        {'name': name, 'main_length_m': length(row['layout']['route']),
         'station_lengths_m': {s['id']: length(s['route']) for s in row['layout']['stations']},
         'handoff_length_m': length(row['handoff_route']),
         'passed': sum(t['status'] == 'pass' for t in row['traversals'] + row['station_traversals'] + row['handoff_traversals']),
         'expected_traversals': 8}
        for name, row in zip(NAMES, (left, right))]}
    report['ok'] = report['ok'] and all(rules.values()) and all(c['passed'] == c['expected_traversals'] for c in report['comparison']['candidates'])
    suffix = '' if seed == SEED else f'-{seed}'
    target = OUTPUT / f'room{suffix}.png'
    evidence = OUTPUT / f'acceptance{suffix}.json'
    evidence.write_text(json.dumps(report, indent=2), encoding='utf-8')
    if not report['ok']:
        raise SystemExit(f'Round 02 failed: {evidence}')
    render(left, right, target, round_two=True)
    print(f'{target} | {NAMES[0]} 8/8 | {NAMES[1]} 8/8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seed', type=int, action='append', help='Repeat for more comparisons; default: 31')
    args = parser.parse_args()
    for seed in args.seed or [SEED]:
        compare(seed)


if __name__ == '__main__':
    main()
