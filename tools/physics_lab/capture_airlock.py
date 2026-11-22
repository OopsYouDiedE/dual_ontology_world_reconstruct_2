"""First-person Forward+ receipt for the playable L03; sends the same actions as the player."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'mcp' / 'game'))
from server import Run  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    run = Run(1, scene_key='observer_airlock', eval_review=True)
    manifest, trace = [], []

    def key(name, count=1):
        for _ in range(count):
            p = run.request('action', action='air_' + name, frames=1, timeout=60)['state']
            while p['audit_left'] > 0:
                p = run.request('wait', frames=10, timeout=60)['state']
            assert p['span_collider_mm'] == p['span_mesh_mm'] == [1640, 190, 2660]
            assert p['collider_top_mm'] == p['mesh_top_mm']
            payload = json.dumps(p, sort_keys=True, separators=(',', ':')).encode()
            trace.append(dict(action=name, tick=p['tick'], sha256=hashlib.sha256(payload).hexdigest()))
        return p

    def shot(name):
        receipt = json.loads(run.request('observe', screenshot=True, timeout=60)[0])
        s = receipt['state']
        assert s['view'] == 'eye' and not s['audit_left']
        assert s['hale_model'] == 'res://assets/characters/mpfb/r05_styled.glb'
        dest = f'{len(manifest)+1:02d}-{name}.png'
        shutil.copyfile(receipt['screenshot'], out / dest)
        manifest.append(dict(image=dest, renderer=receipt['renderer'], **s))
        (out / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
        print(dest, s['tick'], s['duty'], flush=True)
        return s

    def last(state, kind):
        return next((item for item in reversed(state['events']) if item['kind'] == kind), None)

    def prepare(record_shots=False):
        key('left', 3)
        p = key('forward')
        assert p['sight'] and len(p['perception']['lead']['first_hits']) == 27
        assert 0 < p['bridge'] < 26
        if record_shots:
            shot('entered-aperture-span-rising')
        # The same draw of rays covers the target while the camera now includes the crossing lane.
        assert key('turn_r')['sight']
        p = key('wait')
        assert p['bridge'] == 26
        if record_shots:
            shot('lit-witness-and-flush-deck')
        p = key('share')
        assert not p['revision'] and last(p, 'EVIDENCE_REJECTED')
        p = key('lamp')
        assert not p['sight'] and p['perception']['lead']['witness_faces'] > 0
        assert 'UNOBSERVABLE' in p['perception']['lead']['first_hits']
        assert key('wait', 5)['bridge'] == 0
        if record_shots:
            shot('same-view-dark-tile')
        key('trial')
        p = key('wait')
        assert 0 < p['probe_mm'][2] < 1300 and p['probe_mm'][1] < -100
        if record_shots:
            shot('control-load-descends')
        p = key('wait')
        assert [row['kind'] for row in p['records']] == ['CAUGHT']
        if record_shots:
            shot('control-load-caught')
        p = key('share')
        assert not p['revision']
        assert key('lamp')['sight']
        assert key('wait', 2)['bridge'] == 26
        key('trial')
        p = key('wait')
        assert abs(p['probe_mm'][1]) <= 35 and 0 < p['probe_mm'][2] < 1300
        if record_shots:
            shot('witness-load-on-deck')
        p = key('wait', 2)
        assert [row['kind'] for row in p['records']] == ['CAUGHT', 'SUPPORTED']
        assert p['probe_mm'][2] < -1620
        if record_shots:
            shot('witness-load-in-far-tray')
        p = key('request')
        assert p['duty'] == 'ON NEAR BANK' and p['events'][-1]['kind'] == 'ORDER_REFUSED'
        if record_shots:
            shot('native-order-refused')
        p = key('share')
        assert p['revision']['evidence'] == [1, 2] and p['events'][-1]['kind'] == 'EVIDENCE_ACCEPTED'
        if record_shots:
            shot('witness-record-accepted')
        # The evidence revision grants a conditional exemption, not a global permission.
        key('lamp')
        p = key('request')
        assert p['duty'] == 'ON NEAR BANK' and p['events'][-1]['kind'] == 'ORDER_REFUSED'
        key('lamp')
        p = key('request')
        assert p['events'][-1]['kind'] == 'ORDER_ACCEPTED' and p['duty'] == 'APPROACH'
        return p

    def on_span():
        s = key('wait', 4)
        assert s['duty'] == 'CROSSING' and -800 < s['hale_mm'][2] < 800 and abs(s['hale_mm'][1]) < 35
        assert s['perception']['hale']['far_signal'] == 'PROCEED' and s['hale_clip'] == 'walk'

    try:
        print(run.log, flush=True)
        s = key('wait')
        assert s['lamp'] and not s['sight'] and s['bridge'] == 0
        assert 'optical_hood' in s['perception']['lead']['first_hits']
        shot('entry-lamp-on-witness-occluded')
        assert key('request')['duty'] == 'ON NEAR BANK'
        s = key('forward', 5)
        assert s['lead_mm'][2] > 1500 and s['stop_bar_y_mm'] < 1000
        shot('physical-stop-bar-blocks-shortcut')
        assert key('reset')['tick'] == 0
        prepare(True)
        on_span()
        shot('hale-at-midspan')
        s = key('lamp')
        assert s['duty'] == 'HOLDING' and s['remaining'] == 60 and s['hale_clip'] == 'idle'
        shot('loss-onset')
        s = key('wait', 2)
        assert s['remaining'] == 20 and s['warning_samples'] == [41, 41]
        shot('warning-after-40-observable-ticks')
        s = key('lamp')
        assert s['duty'] == 'CROSSING' and last(s, 'WITNESS_RESTORED')['warning_age'] == 41
        shot('witness-restored')
        s = key('wait', 6)
        assert 0 < s['dog_stroke'] < 48 and s['hale_clip'] == 'operate'
        shot('hale-works-far-dog')
        s = key('wait', 2)
        assert s['dog'] and s['duty'] == 'DOG SEATED'
        shot('hale-seats-far-dog')
        key('turn_l')
        s = key('right', 3)
        assert s['dog'] and not s['sight'] and s['bridge'] == 26
        s = key('forward', 5)
        assert -1000 < s['lead_mm'][2] < 1000 and s['bridge'] == 26
        shot('lead-walks-past-near-sill')
        s = key('forward', 8)
        assert s['cleared'] and s['door'] == 44 and s['lead_mm'][2] < -5620
        shot('exit-cleared-on-foot')

        assert key('reset')['tick'] == 0
        prepare()
        on_span()
        s = key('lamp')
        assert s['remaining'] == 60
        s = key('wait', 3)
        event = last(s, 'DECK_RELEASED')
        assert event and event['tick'] - last(s, 'SIGHT_LOST')['tick'] == 60
        assert event['lead_observed_ticks'] >= 40 and event['hale_observed_ticks'] >= 40
        shot('expiry-deck-begins-to-drop')
        s = key('wait_short', 2)
        assert s['hale_mm'][1] < -60 and s['bridge'] < 26
        shot('unrestored-loss-physical-drop')
        s = key('wait', 2)
        assert last(s, 'CATCH_RETURN')['actor'] == 'hale' and not s['dog'] and not s['revision']
        shot('catch-returns-hale-no-clear')
        (out / 'trace.json').write_text(json.dumps(trace, indent=2), encoding='utf-8')
        log = run.log.read_text(encoding='utf-8', errors='replace')
        if 'ERROR:' in log:
            raise RuntimeError(f'Engine error reported, see {run.log}')
        print(f'{len(manifest)} eye-level frames, {len(trace)} command receipts', flush=True)
    finally:
        run.close()


if __name__ == '__main__':
    main()
