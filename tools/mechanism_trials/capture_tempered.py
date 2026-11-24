"""Render two frozen Tempered Span player tapes and a no-splice counterfactual in Forward+."""
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
    'staged_jack_rising_weight': {
        0: 'entry', 55: 'jack-teeth', 80: 'service-punch-warning', 127: 'pin-out',
        169: 'hot-copper-bend', 185: 'splice-warning', 233: 'local-reset-retained-bend', 326: 'ballast-raised',
        339: 'proof-arming', 387: 'proof-live', 450: 'rider-preparation', 460: 'rider-release',
        485: 'rider-on-span', 508: 'far-landing'},
    'loaded_bench_falling_brake': {240: 'bench-mark', 363: 'loaded-splice-warning', 411: 'bench-restored',
                                  436: 'draw-armed', 608: 'brake-window', 633: 'crossing', 657: 'far-landing'},
    'no_splice': {169: 'hot-seat-pin-still-out', 198: 'rejected-without-pin'},
}


def capture(out, revision=None):
    bound = (*SHARED_GAME_PATHS, 'scenes/physics_lab/counterfactual', 'tools/counterfactual')
    proof = assert_frozen(ROOT, revision, bound) if revision else None
    out.mkdir(parents=True, exist_ok=True)
    fixture = json.loads((ROOT / 'tools/counterfactual/golden.json').read_text(encoding='utf-8'))
    frames, traces, sessions = [], {}, []
    prefix = [entry for entry in fixture['routes'][0]['inputs'] if entry['tick'] <= 128]
    control = {'id': 'no_splice', 'inputs': prefix + [{'tick': 173, 'press': 'move', 'target': 'yoke'},
                                                       {'tick': 198, 'press': 'arm'}]}
    for route in fixture['routes'] + [control]:
        name = route['id']
        cuts = CUTS[name]
        model_wins = 'win_tick' in route
        ref = out / f'{name}-study-tape.json'
        ref.write_text(json.dumps({'inputs': route['inputs'], 'stops': sorted(t for t in cuts if t > 0)}, indent=2), encoding='utf-8')
        run = Run(0, scene_key='tempered', scene_args=(f'--tempered-study={ref}',))
        sessions.append(run.id)
        traces[name] = []

        def state_until(tick):
            until = time.monotonic() + 10
            while time.monotonic() < until:
                state = run.request('observe', timeout=20)['state']
                if int(state['state']['tick']) == tick and not state['ticks_left']:
                    return state
            raise AssertionError((name, tick, state))

        def shot(tick, label):
            packet = json.loads(run.request('observe', screenshot=True, timeout=40)[0])
            state = packet['state']
            assert state['state']['tick'] == tick
            r = state['render']
            assert packet['viewport_size'] == [1280, 720] and packet['renderer'] == 'forward_plus'
            assert r['scaling_3d_scale'] == 1.0 and r['msaa_samples'] == 2 and r['sdfgi_enabled']
            assert abs(r['ink_opacity'] - 0.40) < 1e-5
            assert r['opaque_shader'].endswith('/HallFinish.gdshader') and r['atmosphere_baseline'].endswith('/Hall04.tres')
            file = out / f'{name}-{label}.png'
            shutil.copyfile(packet['screenshot'], file)
            frames.append({'label': label, 'case': name, 'file': file.name, 'sha256': digest(file),
                           'renderer': packet['renderer'], 'viewport': packet['viewport_size'], **state})
            print(name, label, tick, flush=True)
            return state

        try:
            run.request('observe', timeout=90)
            state = state_until(0)
            if 0 in cuts:
                shot(0, cuts[0])
                run.request('action', action='tempered_view', frames=1, timeout=20)
                shot(0, 'reverse-section')
                for _ in range(2):
                    run.request('action', action='tempered_view', frames=1, timeout=20)
            for tick, label in sorted(cuts.items()):
                if tick == 0:
                    continue
                run.request('action', action='tempered_continue', frames=1, timeout=20)
                state = state_until(tick)
                if model_wins and tick == route['splice_tick']:
                    assert state['state']['event']['id'] == 'spliced'
                    assert state['state']['retained'] == route['retained_at_splice'] and state['state']['local']['pin_intact']
                if model_wins and tick == route['board_tick']:
                    assert state['state']['crossing']['from'] == route['approach']
                shot(tick, label)
                traces[name].append(state)
            if model_wins:
                assert state['state']['won'] and state['state']['place'] == 'exit' and state['state']['tick'] == route['win_tick']
                assert [('spliced', route['splice_tick']), ('boarding', route['board_tick']), ('crossed', route['win_tick'])] == [
                    (e['id'], e['tick']) for e in state['events'] if e['id'] in ('spliced', 'boarding', 'crossed')]
            else:
                assert not state['state']['won'] and not state['state']['local']['pin_intact']
                assert state['state']['proof']['stage'] == 'parked' and 'seated pin' in state['state']['event']['text']
        finally:
            run.close()
            shutil.copyfile(run.log, out / f'{name}-godot.log')
    if proof is not None and assert_frozen(ROOT, revision, bound) != proof:
        raise ValueError('Source changed during capture')
    (out / 'manifest.json').write_text(json.dumps({'room': 'A08 / The Tempered Span', 'sessions': sessions,
                                                   'frames': frames, 'freeze': proof}, indent=2), encoding='utf-8')
    (out / 'live-trace.json').write_text(json.dumps(traces, indent=2), encoding='utf-8')
    choices = {'entry', 'service-punch-warning', 'hot-copper-bend', 'local-reset-retained-bend', 'proof-live',
               'rider-release', 'rider-on-span', 'far-landing'}
    contact_sheet(out, [f for f in frames if f['case'] == fixture['routes'][0]['id'] and f['label'] in choices],
                  'golden-contact', 'A08 / THE TEMPERED SPAN: THE PIN REWINDS, THE BEND STAYS')
    contact_sheet(out, [f for f in frames if f['case'] in (fixture['routes'][1]['id'], 'no_splice')],
                  'contrast-contact', 'A08 / A SAVED BENCH MARK AND THE UNSPLICED CONTROL')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, default=ROOT / '.runtime/academy-mechanisms/tempered')
    parser.add_argument('--revision', help='Bind the evidence to the checked-out commit')
    args = parser.parse_args()
    capture(args.out.resolve(), args.revision)
