"""Replay the L03 first-person control score via Game MCP, capturing selected real viewports."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'mcp' / 'game'))
from server import Run  # noqa: E402

PHASES = {
    0: 'arrival', 1: 'look-away', 4: 'walked-the-span', 7: 'face-to-face',
    8: 'hold-first-span', 10: 'island-corner', 11: 'crouch-under-lintel',
    12: 'second-span', 14: 'hold-for-hale', 17: 'cleared',
}

AGE = {0: 47, 1: 88, 7: 21, 8: 115, 11: 17, 12: 31, 14: 143, 17: 35}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    run = Run(1, scene_key='observer_airlock', eval_review=True)
    rows = []
    seen = set()
    try:
        print(run.log, flush=True)
        run.request('action', action='air_film', frames=1, timeout=60)
        deadline = time.monotonic() + 95
        while time.monotonic() < deadline:
            s = run.request('observe', timeout=60)['state']
            assert s['hale_model'] == 'res://assets/characters/mpfb/r05_formal.glb'
            assert not s['film_error'], s['film_error']
            assert s['solid'] == s['collision'] == s['bridge_mesh']
            phase = s['film']
            if phase in PHASES and phase not in seen and s['phase_age'] >= AGE.get(phase, 0):
                receipt = json.loads(run.request('observe', screenshot=True, timeout=60)[0])
                s = receipt['state']
                phase = s['film']
                if phase in PHASES and phase not in seen and s['phase_age'] >= AGE.get(phase, 0):
                    dest = f'{phase:02d}-{PHASES[phase]}.png'
                    shutil.copyfile(receipt['screenshot'], out / dest)
                    assert receipt['renderer'] == 'forward_plus'
                    rows.append(dict(image=dest, renderer=receipt['renderer'], **s))
                    seen.add(phase)
                    print(dest, s['tick'], flush=True)
            if s['cleared'] and s['film'] >= 18:
                break
        else:
            raise AssertionError('First-person control score did not clear the room')
        kinds = [e['kind'] for e in s['events']]
        expected = ['COUNTEREXAMPLE', 'RULE_REVISED', 'FIRST_HANDOFF', 'HALE_AT_LANDING',
                    'FAR_HANDOFF', 'HALE_ACROSS', 'EXIT_CLEARED']
        assert [x for x in kinds if x in expected] == expected
        assert 'CATCH_RETURN' not in kinds
        assert {0, 4, 8, 12, 14, 17}.issubset(seen), seen
        (out / 'manifest.json').write_text(json.dumps(rows, indent=2), encoding='utf-8')
        trace = json.dumps(s['events'], indent=2)
        (out / 'trace.json').write_text(trace, encoding='utf-8')
        assert 'ERROR:' not in run.log.read_text(encoding='utf-8', errors='replace'), run.log
        print(f'{len(rows)} Forward+ frames; event trace {hashlib.sha256(trace.encode()).hexdigest()}', flush=True)
    finally:
        run.close()


if __name__ == '__main__':
    main()
