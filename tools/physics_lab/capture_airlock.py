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
        '08-blind-wall': phase == 11 and not s['witness'][0][1],
        '09-one-eye-resumes-B': phase == 12 and age >= 25 and s['witness'][0][1] and not s['witness'][1][1],
        '10-cleared': phase == 15 and age >= 88 and s['cleared'],
        '11-terminal-red': bool(s['failed'] == 'DOUBLE_GAZE' and age >= 65),
        '12-B-overlap': bool(case == 'early' and 5 <= s['red'][1] <= 36),
        '13-fall-empty-deck': case == 'late' and s['failed'] == 'FALL' and age >= 175,
        '14-false-testimony': case == 'panic' and s['distorted'] and 'RULE_DISTORTED' in kinds,
        '15-grounded': case == 'panic' and 'GROUNDED' in kinds and phase == 4 and age >= 62,
    }
    return {name for name, reached in states.items() if reached}


def validate(s, case):
    events = s['events']
    by_kind = lambda kind, span: [e for e in events if e['kind'] == kind and e.get('span') == span]
    if case == 'clear':
        assert s['cleared'] and not s['failed']
        for kind in ['COUNTEREXAMPLE', 'RULE_REVISED', 'FIRST_HANDOFF', 'BLIND_SIGNAL', 'FAR_HANDOFF', 'HALE_ACROSS', 'EXIT_CLEARED']:
            assert any(e['kind'] == kind for e in events), kind
        assert 0 < by_kind('FAR_HANDOFF', None)[0]['gap'] < 60
        assert by_kind('RED_CLEARED', 0)[0]['held'] <= 40 and not by_kind('RED', 1)
    elif case in ('early', 'death'):
        i = int(case == 'early')
        assert s['failed'] == 'DOUBLE_GAZE' and not s['cleared']
        assert by_kind('DEAD', i)[0]['tick'] - by_kind('RED', i)[-1]['tick'] == 40
    elif case == 'late':
        assert s['failed'] == 'FALL' and not s['cleared']
        assert by_kind('RELEASE', 1)[0]['tick'] - by_kind('NO_EYES', 1)[0]['tick'] == 59
    else:
        assert not s['distorted'] and not s['revision'] and not s['failed']
        assert by_kind('RULE_DISTORTED', None)[0]['tick'] < by_kind('GROUNDED', None)[0]['tick']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--case', default='clear', choices=['clear', 'death', 'early', 'late', 'panic'])
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
            s = run.request('observe', timeout=60)['state']
            assert s['hale_model'] == 'res://assets/characters/mpfb/r05_formal.glb'
            assert not s['film_error'], s['film_error']
            assert s['solid'] == s['collision'] == s['bridge_mesh']
            if milestones(s, args.case) - seen:
                receipt = json.loads(run.request('observe', screenshot=True, timeout=60)[0])
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
            'clear': {'01', '02', '03', '05', '06', '08', '09', '10'},
            'death': {'03', '11'}, 'early': {'11', '12'}, 'late': {'08', '13'},
            'panic': {'14', '15'},
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
