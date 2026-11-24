"""A06 real Forward+ evidence: stance, warned captures, interlock and two winning rhythms."""
import argparse
import json
from pathlib import Path
import shutil
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools' / 'chronograph'))
from capture import Run, contact_sheet, digest  # noqa: E402

CUTS = {
    'normal': {0: 'entry', 20: 'drive-warning', 100: 'flat-leaf', 180: 'double-warning',
               200: 'felt-dampens-ear', 260: 'far-bank', 340: 'exit'},
    'other_rhythm': {180: 'loaded-ear', 340: 'exit'},
    'only_watch': {160: 'ear-warning', 180: 'ear-catch'},
    'only_creep_then_recover_and_win': {180: 'sight-catch', 240: 'porch-recovery'},
    'interlock_at_deadline': {440: 'counterweight-warning', 460: 'occupied-leaf-held', 520: 'clear-leaf-rises'},
}
SIGNPOSTS = {'leaf_passable', 'leaf_hold', 'leaf_blocked', 'caught', 'recovered', 'won'}


def capture(out):
    out.mkdir(parents=True, exist_ok=True)
    cases = json.loads((ROOT / 'tools/duet/golden.json').read_text(encoding='utf-8'))['cases']
    run = Run(0, scene_key='duet')
    frames, traces = [], {}

    def advance(action):
        run.request('action', action='duet_' + action, frames=1, timeout=20)
        until = time.monotonic() + 10
        while time.monotonic() < until:
            state = run.request('observe', timeout=20)['state']
            if not state['ticks_left']:
                return state
        raise AssertionError(f'No decision boundary after {action}')

    def shot(case, label):
        packet = json.loads(run.request('observe', screenshot=True, timeout=40)[0])
        state = packet['state']
        r = state['render']
        assert packet['viewport_size'] == [1280, 720] and packet['renderer'] == 'forward_plus', packet
        assert r['scaling_3d_scale'] == 1.0 and r['msaa_samples'] == 2 and r['sdfgi_enabled']
        assert abs(r['ink_opacity'] - 0.40) < 1e-5
        assert r['opaque_shader'].endswith('/HallFinish.gdshader') and r['atmosphere_baseline'].endswith('/Hall04.tres')
        file = out / f'{case}-{label}.png'
        shutil.copyfile(packet['screenshot'], file)
        frames.append({'label': label, 'case': case, 'file': file.name, 'sha256': digest(file),
                       'renderer': packet['renderer'], 'viewport': packet['viewport_size'], **state})
        print(case, label, state['state']['tick'], flush=True)

    try:
        run.request('observe', timeout=90)
        for case in cases:
            name = case['name']
            cuts = CUTS.get(name, {})
            state = advance('reset')
            assert state['state']['tick'] == 0
            if 0 in cuts:
                shot(name, cuts[0])
                assert advance('view')['state']['tick'] == 0
                shot(name, 'reverse-section')
                assert advance('view')['state']['tick'] == 0
                assert advance('view')['section'] == 1
            traces[name] = []
            tick = 0
            for action, count in case['input']:
                for _ in range(count):
                    state = advance(action)
                    row = state['verdicts'][-1]
                    assert row['tick'] == tick and row['action'] == action, row
                    assert row['reason'] == case.get('refusals', {}).get(str(tick), ''), row
                    tick += 20
                    assert state['state']['tick'] == tick
                    if tick in cuts:
                        shot(name, cuts[tick])
                    for key, expected in case.get('at', {}).get(str(tick), {}).items():
                        value = state['state']
                        for part in key.split('.'):
                            value = value[part]
                        assert value == expected, (name, tick, key, value, expected)
                    traces[name].append(state)
            assert state['state']['outcome'] == case['outcome'], (name, state['state'])
            assert [e['id'] for e in state['events']] == list(range(1, len(state['events']) + 1))
            assert [[e['tick'], e['kind'], e['source'], e['lead_ticks']]
                    for e in state['events'] if e['kind'] in SIGNPOSTS] == case['marks'], name
        (out / 'manifest.json').write_text(json.dumps({'room': 'A06 / The Felt Drawleaf', 'session': run.id,
                                                       'frames': frames}, indent=2), encoding='utf-8')
        (out / 'live-trace.json').write_text(json.dumps(traces, indent=2), encoding='utf-8')
        contact_sheet(out, [f for f in frames if f['case'] == 'normal' and f['label'] != 'reverse-section'],
                      'golden-contact', 'A06 / THE FELT DRAWLEAF: IRON, FELT AND GAZE')
        contact_sheet(out, [f for f in frames if f['case'] not in ('normal', 'other_rhythm')],
                      'contrast-contact', 'A06 / WARNED CAPTURES, RECOVERY AND OCCUPANCY HOLD')
    finally:
        run.close()
        shutil.copyfile(run.log, out / 'godot-process.log')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, default=ROOT / '.runtime/academy-mechanisms/duet')
    capture(parser.parse_args().out.resolve())
