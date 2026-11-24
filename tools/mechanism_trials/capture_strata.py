"""Capture two playable Strata routes and a signaled overload in the real Game MCP."""
import argparse
import json
from pathlib import Path
import shutil
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools' / 'chronograph'))
from capture import Run, contact_sheet, digest  # noqa: E402
from capture_receipt import assert_frozen, SHARED_GAME_PATHS  # noqa: E402

CUTS = {
    'bank_on_lower_rail': {0: 'sump', 100: 'lower-rack-arrival', 220: 'recovered-charge',
                           240: 'press-warning', 300: 'ceramic', 380: 'insulated-stairs', 460: 'gallery',
                           600: 'copper-reconnected', 640: 'powered-rack', 700: 'crown-strain',
                           840: 'regenerated-hatch-bank', 860: 'hatch-warning', 920: 'opened'},
    'start_insulated': {80: 'ceramic-from-sump', 400: 'gallery-with-strain', 860: 'opened'},
    'overload_control': {120: 'missed-unload', 160: 'strain-trip', 220: 'returned'},
}


def capture(out, revision=None):
    bound = (*SHARED_GAME_PATHS, 'scenes/physics_lab/strata', 'tools/strata')
    frozen = assert_frozen(ROOT, revision, bound) if revision else None
    out.mkdir(parents=True, exist_ok=True)
    package = json.loads((ROOT / 'tools/strata/golden.json').read_text(encoding='utf-8'))
    trials = package['runs'] + [{'id': 'overload_control', 'decisions': 'CCCCC WWWWWW',
                                 'checkpoints': {'160': {'mode': 'return'}, '220': {'landing': 0, 'mode': 'ready'}}}]
    run = Run(0, scene_key='strata')
    frames, traces = [], {}

    def advance(action):
        run.request('action', action='strata_' + action, frames=1, timeout=20)
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
        assert packet['viewport_size'] == [1280, 720] and packet['renderer'] == 'forward_plus'
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
        for case in trials:
            name = case['id']
            cuts = CUTS[name]
            state = advance('reset')
            assert state['state']['tick'] == 0
            if 0 in cuts:
                shot(name, cuts[0])
                assert advance('view')['state']['tick'] == 0
                shot(name, 'opposite-section')
                advance('view')
                assert advance('view')['section'] == 1
            traces[name] = []
            for i, key in enumerate(case['decisions'].replace(' ', ''), 1):
                move = package['inputs'][key]
                state = advance(move)
                tick = i * 20
                assert state['verdicts'][-1] == {'tick': tick - 20, 'action': move, 'accepted': True}, state['verdicts'][-1]
                assert state['state']['tick'] == tick
                for field, value in case.get('checkpoints', {}).get(str(tick), {}).items():
                    assert state['state'][field] == value, (name, tick, field, state['state'][field], value)
                if tick in cuts:
                    shot(name, cuts[tick])
                traces[name].append(state)
            for kind, ticks in case.get('commits', {}).items():
                assert [e['tick'] for e in state['events'] if e['id'] == kind] == ticks
        if frozen is not None and assert_frozen(ROOT, revision, bound) != frozen:
            raise ValueError('Source changed during capture')
        (out / 'manifest.json').write_text(json.dumps({'room': 'A07 / Strata: The Harness Tower', 'session': run.id,
                                                       'frames': frames, 'freeze': frozen}, indent=2), encoding='utf-8')
        (out / 'live-trace.json').write_text(json.dumps(traces, indent=2), encoding='utf-8')
        contact_sheet(out, [f for f in frames if f['case'] == 'bank_on_lower_rail' and f['label'] in
                            ('sump', 'recovered-charge', 'press-warning', 'insulated-stairs', 'powered-rack',
                             'crown-strain', 'hatch-warning', 'opened')], 'golden-contact', 'A07 / STRATA: THE HARNESS TOWER')
        contact_sheet(out, [f for f in frames if f['case'] in ('start_insulated', 'overload_control')],
                      'contrast-contact', 'A07 / SECOND ROUTE AND SAFETY CRADLE')
    finally:
        run.close()
        shutil.copyfile(run.log, out / 'godot-process.log')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, default=ROOT / '.runtime/academy-mechanisms/strata')
    parser.add_argument('--revision', help='Bind the evidence to the checked-out commit')
    args = parser.parse_args()
    capture(args.out.resolve(), args.revision)
