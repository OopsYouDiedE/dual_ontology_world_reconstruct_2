"""Replay ordinary first-person inputs through Game MCP and sample real Vulkan viewports."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'mcp' / 'game'))
from server import Run  # noqa: E402

CASES = ['clear', 'alternate', 'blocked', 'public', 'recoil', 'death', 'early', 'late', 'panic']


def milestones(s, case):
    phase, age = s['film'], s['phase_age']
    kinds = {e['kind'] for e in s['events']}
    states = {
        '01-one-eye-cold': phase == 0 and age >= 49 and s['solid'][0],
        '02-entry-notice': phase == 1 and age >= 79,
        '03-double-gaze-warning-A': phase == 3 and 5 <= s['red'][0] <= 36,
        '04-eye-withdrawn-safe': phase in (3, 4) and not s['red'][0] and 'RED_CLEARED' in kinds and not s['counterexample'],
        '05-Hale-testimony': phase == 4 and s['counterexample'] and age >= 15,
        '06-crouch-under-lintel': phase == 8 and age >= 13 and s['crouched'],
        '07-walking-B': phase == 9 and age >= 24,
        '08-blind-wall': phase in (11, 12) and not s['witness'][0][1] and 2 <= s['dark'][1] <= 25 and 'BLIND_SIGNAL' in kinds,
        '08b-rail-going-dark': phase in (11, 12) and 13 <= s['dark'][1] <= 49 and not s['witness'][0][1],
        '09-one-eye-resumes-B': phase == 12 and age >= 25 and s['witness'][0][1] and not s['witness'][1][1],
        '10-cleared': phase == 15 and age >= 88 and s['cleared'],
        '11-terminal-red': bool(s['failed'] == 'DOUBLE_GAZE' and age >= 65),
        '12-B-overlap': bool(case == 'early' and 5 <= s['red'][1] <= 36),
        '13-fall-empty-deck': case == 'late' and s['failed'] == 'FALL' and age >= 175,
        '14-false-testimony': case == 'panic' and s['distorted'] and 'RULE_DISTORTED' in kinds,
        '15-grounded': case == 'panic' and 'GROUNDED' in kinds and phase == 4 and age >= 62,
        '16-concealed-pose-unseen': case == 'blocked' and phase == 11 and 32 <= age <= 81
            and s['hale_percept']['head'] == 'UNSEEN' and s['role'] == 'WATCH_B' and s['solid'][1],
        '17-corrupted-Hale-looks': case == 'panic' and s['distorted'] and 'FALSE_RULE_GLANCE' in kinds and s['red'][0] > 0,
        '18-Hale-recoils': case == 'recoil' and s['role'] == 'RETRY_B' and 'HALE_RECOILS' in kinds,
    }
    return {name for name, reached in states.items() if reached}


def validate(s, case):
    events = s['events']
    by_kind = lambda kind, span: [e for e in events if e['kind'] == kind and e.get('span') == span]
    if case not in ('early', 'death', 'late'):
        assert s['cleared'] and s['revision'] and not s['failed'] and not s['distorted']
        names = [e['kind'] for e in events]
        expected = ['COUNTEREXAMPLE', 'RULE_REVISED', 'FIRST_HANDOFF', 'HALE_TAKES_B', 'BLIND_SIGNAL', 'FAR_HANDOFF', 'HALE_ACROSS', 'EXIT_CLEARED']
        assert [names.index(k) for k in expected] == sorted(names.index(k) for k in expected)
        gap = by_kind('FAR_HANDOFF', None)[0]['gap']
        assert 0 < gap < 60
        assert by_kind('RED_CLEARED', 0)[0]['held'] <= 40
        if case == 'panic':
            order = [names.index(k) for k in ['RULE_DISTORTED', 'FALSE_RULE_GLANCE', 'GROUNDED', 'COUNTEREXAMPLE', 'EXIT_CLEARED']]
            assert order == sorted(order)
            corrupted = by_kind('FALSE_RULE_GLANCE', None)[0]['tick']
            assert any(e['tick'] == corrupted+1 for e in by_kind('RED', 0)), 'The bad turn must physically cause red'
        elif case == 'recoil':
            assert 'HALE_RECOILS' in names and names.index('HALE_RECOILS') < names.index('HALE_RETAKES_B') < names.index('BLIND_SIGNAL')
        elif case == 'public':
            assert 13 < gap < 60 and not by_kind('RED', 1)
        else:
            assert not by_kind('RED', 1)
    elif case in ('early', 'death'):
        i = int(case == 'early')
        assert s['failed'] == 'DOUBLE_GAZE' and not s['cleared']
        assert by_kind('DEAD', i)[0]['tick'] - by_kind('RED', i)[-1]['tick'] == 40
    elif case == 'late':
        assert s['failed'] == 'FALL' and not s['cleared']
        release = by_kind('RELEASE', 1)[0]['tick']
        gap_start = by_kind('NO_EYES', 1)[-1]['tick']
        assert release - gap_start == 59


def observe(run, *, screenshot=False):
    # Windows can briefly lock a newly published result even after it exists.
    for attempt in range(3):
        try:
            return run.request('observe', screenshot=screenshot, timeout=60)
        except PermissionError:
            if attempt == 2:
                raise
            time.sleep(.03)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--case', default='clear', choices=CASES)
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    os.environ['DUAL_AIRLOCK_AUDIT_CASE'] = args.case
    run = Run(1, scene_key='observer_airlock', eval_review=True)
    rows = []
    seen = set()
    try:
        print(run.log, flush=True)
        run.request('action', action='air_film', frames=1, timeout=60)
        deadline = time.monotonic() + 105
        while time.monotonic() < deadline:
            s = observe(run)['state']
            assert s['hale_model'] == 'res://assets/characters/mpfb/r05_formal.glb'
            assert not s['film_error'], s['film_error']
            assert s['solid'] == s['collision'] == s['bridge_mesh']
            if milestones(s, args.case) - seen:
                receipt = json.loads(observe(run, screenshot=True)[0])
                s = receipt['state']
                for milestone in sorted(milestones(s, args.case) - seen):
                    image = milestone + '.png'
                    shutil.copyfile(receipt['screenshot'], out / image)
                    assert receipt['renderer'] == 'forward_plus'
                    rows.append(dict(image=image, renderer=receipt['renderer'], **s))
                    seen.add(milestone)
                    print(image, s['tick'], flush=True)
            if s['film'] == 17:
                break
        else:
            raise AssertionError('First-person control score did not finish')
        validate(s, args.case)
        required = {
            'clear': {'01', '02', '03', '05', '06', '08b', '09', '10'},
            'alternate': {'08b', '09', '10'}, 'blocked': {'16', '09', '10'},
            'public': {'08b', '09', '10'}, 'recoil': {'18', '09', '10'},
            'death': {'03', '11'}, 'early': {'11', '12'}, 'late': {'08b', '13'},
            'panic': {'14', '15', '17', '10'},
        }
        assert required[args.case] <= {n.split('-')[0] for n in seen}, seen
        (out / 'manifest.json').write_text(json.dumps(rows, indent=2), encoding='utf-8')
        trace = json.dumps(s['events'], indent=2)
        (out / 'trace.json').write_text(trace, encoding='utf-8')
        (out / 'result.json').write_text(json.dumps(s, indent=2), encoding='utf-8')
        assert 'ERROR:' not in run.log.read_text(encoding='utf-8', errors='replace'), run.log
        print(f'{args.case}: {len(rows)} Forward+ frames; event trace {hashlib.sha256(trace.encode()).hexdigest()}', flush=True)
    finally:
        run.close()


if __name__ == '__main__':
    main()
