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

CASES = ['clear', 'alternate', 'blocked', 'public', 'recoil', 'death', 'early', 'late', 'panic', 'solo']


def milestones(s, case):
    phase, age = s['film'], s['phase_age']
    kinds = {e['kind'] for e in s['events']}
    states = {
        '01-one-eye-cold': phase == 0 and 10 <= age <= 42 and s['solid'][0],
        '02-original-field-copies': phase == 0 and s['book'] and not s['revision'],
        '03-a-with-original-rules': phase == 1 and s['role'] in ('A_LINE', 'CROSS_A') and not s['revision'],
        '04-tread-dark': phase in (3, 4) and 'TREAD_DARK' in kinds and not s['stalemate'],
        '05-rules-stall-at-island': phase in (4, 5) and s['stalemate'] and 'TRIAL_REQUESTED' not in kinds and s['hale_percept']['head'] == 'AWAY',
        '06-double-gaze-warning': phase == 5 and 6 <= s['red'][1] <= 35 and not s['distorted'],
        '07-solo-white-witness': phase == 5 and s['witness'][1][1] and not s['witness'][0][1] and not s['counterexample'],
        '08-evidence-amendment': phase == 6 and s['offer_open'] and 'OFFER_REJECTED' not in kinds,
        '09-wrong-amendment-rejected': phase == 6 and s['offer_open'] and 'OFFER_REJECTED' in kinds,
        '10-hale-takes-under-new-rule': phase == 7 and s['witness'][1][1] and s['revision'],
        '11-crouch-under-lintel': phase == 8 and age >= 11 and s['crouched'],
        '12-walking-b': phase == 9 and age >= 28,
        '13-rail-starts-dark': s['role'] in ('B_LINE', 'CROSS_B') and 2 <= s['dark'][1] <= 12,
        '14-rail-partly-dark': s['role'] in ('B_LINE', 'CROSS_B') and 20 <= s['dark'][1] <= 33,
        '15-rail-last-mark': s['role'] in ('B_LINE', 'CROSS_B') and 48 <= s['dark'][1] <= 56,
        '16-one-eye-resumes-b': phase == 12 and age >= 19 and s['witness'][0][1] and not s['witness'][1][1],
        '17-cleared': phase == 15 and age >= 45 and s['cleared'],
        '18-terminal-red': bool(s['failed'] == 'DOUBLE_GAZE' and age >= 65),
        '19-overlap-in-cover': bool(case == 'early' and phase >= 10 and 6 <= s['red'][1] <= 35),
        '20-fall-empty-deck': case == 'late' and s['failed'] == 'FALL' and age >= 130,
        '21-false-testimony': case == 'panic' and s['distorted'] and 'RULE_DISTORTED' in kinds,
        '22-grounded': case == 'panic' and 'GROUNDED' in kinds and phase == 4,
        '23-concealed-pose-unseen': case == 'blocked' and phase == 11 and 32 <= age <= 81
            and s['hale_percept']['head'] == 'UNSEEN' and s['role'] == 'WATCH_B' and s['solid'][1],
        '24-corrupted-hale-looks': case == 'panic' and s['distorted'] and 'FALSE_RULE_GLANCE' in kinds and s['red'][1] > 0,
        '25-hale-recoils': case == 'recoil' and s['role'] == 'RETRY_B' and 'HALE_RECOILS' in kinds,
    }
    return {name for name, reached in states.items() if reached}


def validate(s, case):
    events = s['events']
    by_kind = lambda kind, span: [e for e in events if e['kind'] == kind and e.get('span') == span]
    names = [e['kind'] for e in events]
    lead_in = ['FIRST_HANDOFF', 'HALE_AT_LANDING', 'TREAD_DARK', 'ORIGINAL_RULES_STALL', 'TRIAL_REQUESTED']
    assert [names.index(k) for k in lead_in] == sorted(names.index(k) for k in lead_in)
    for e in by_kind('HALE_DECISION', None):
        if e['action'] in ('TAKE', 'GIVE', 'RECOIL'):
            assert e['boot_hit']['light'].startswith('landing-')
            assert e['boot_hit']['incidence'] > .02
            assert 0 <= e['boot_hit']['ray'] < 27 and 0 <= e['tick'] - e['boot_hit']['tick'] <= 9
        if e['action'] in ('TAKE', 'GIVE'):
            assert e['head_hit']['light'].startswith('landing-')
            assert e['head_hit']['incidence'] > .02
            assert 0 <= e['head_hit']['ray'] < 27 and e['head_hit']['tick'] == e['tick']
        if e['action'] == 'RECOIL':
            assert e['span_hit']['incidence'] > .02
            assert e['span_hit']['ray'] < 27 and e['span_hit']['light'] == 'span-1'
    if case not in ('early', 'death', 'late'):
        assert s['cleared'] and s['revision'] and not s['failed'] and not s['distorted']
        expected = ['COUNTEREXAMPLE', 'OFFER_REJECTED', 'RULE_REVISED', 'HALE_TAKES_B', 'BLIND_SIGNAL', 'FAR_HANDOFF', 'HALE_ACROSS', 'EXIT_CLEARED']
        assert [names.index(k) for k in expected] == sorted(names.index(k) for k in expected)
        gap = by_kind('FAR_HANDOFF', None)[0]['gap']
        assert 0 < gap < 60
        reds = by_kind('RED', 1)
        if case == 'solo':
            assert not reds and len(s['hypotheses']) == 2 and s['ast']['allowed_heads'] == ['AWAY']
        else:
            assert by_kind('RED_CLEARED', 1)[0]['held'] <= 40
        if case == 'panic':
            order = [names.index(k) for k in ['RULE_DISTORTED', 'FALSE_RULE_GLANCE', 'GROUNDED', 'COUNTEREXAMPLE', 'EXIT_CLEARED']]
            assert order == sorted(order)
            corrupted = by_kind('FALSE_RULE_GLANCE', None)[0]['tick']
            assert any(e['tick'] == corrupted+1 for e in reds), 'The bad turn must physically cause red'
        elif case == 'recoil':
            assert names.index('HALE_RECOILS') < names.index('HALE_RETAKES_B') < names.index('BLIND_SIGNAL')
        elif case == 'public':
            assert 13 < gap < 60 and len(reds) == 1
    elif case in ('early', 'death'):
        assert s['failed'] == 'DOUBLE_GAZE' and not s['cleared']
        assert by_kind('DEAD', 1)[0]['tick'] - by_kind('RED', 1)[-1]['tick'] == 40
    elif case == 'late':
        assert s['failed'] == 'FALL' and not s['cleared']
        assert by_kind('RELEASE', 1)[-1]['tick'] - by_kind('NO_EYES', 1)[-1]['tick'] == 59


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
            'clear': {'01', '02', '03', '04', '05', '06', '07', '08', '09', '11', '12', '13', '16', '17'},
            'alternate': {'13', '16', '17'}, 'blocked': {'23', '16', '17'},
            'public': {'13', '14', '16', '17'}, 'recoil': {'25', '16', '17'},
            'death': {'06', '18'}, 'early': {'18', '19'}, 'late': {'14', '15', '20'},
            'panic': {'21', '22', '24', '17'}, 'solo': {'07', '08', '17'},
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
