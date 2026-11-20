"""Exercise the paper overlays, natural-speed movement and camp light via the live project bridge."""
from pathlib import Path
import json
import sys
from look_studies_e2e import Lab, check


def main():
    out = Path(__file__).resolve().parents[2] / '.runtime/reference-plates'
    out.mkdir(parents=True, exist_ok=True)
    with Lab() as lab:
        report = {'watch': check(lab)}
        for name in ['Forest Camp', 'Garden Gate']:
            lab.button(name)
            tufts = lab.state['grass_tufts']
            assert tufts > 15000, lab.state
            report[name] = tufts
            if name == 'Forest Camp':
                before = lab.state['fire_power']
                lab.wait(13)
                after = lab.state['fire_power']
                assert before > 0 and after > 0 and abs(after-before) > .00001
                report['fire_light_samples'] = [before, after]
        lab.button('Draft')
        lab.click(920,240)
        assert lab.state['draft_pick'] == 2, lab.state
        lab.button('Inspect')
        lab.click(790,362)
        assert lab.state['lens_at'] == [790,362], lab.state
        report['picked'] = 'Hallway'
        report['lens'] = lab.state['lens_at']
        lab.button('Entrance')
        assert lab.state['lens_at'] == [] and lab.state['grass_tufts'] == 0
    if '--frames' in sys.argv:
        for name, slug in [('Meridian','watch'), ('Forest Camp','camp')]:
            with Lab() as lab:
                lab.send()
                lab.button(name)
                if not lab.state['sdfgi']: lab.button('SDFGI')
                lab.button('Hide UI')
                lab.wait(50)
                for i in range(10):
                    (out/f'{slug}-{i:02}.png').write_bytes(Path(lab.capture(f'{slug}-{i:02}')).read_bytes())
    (out/'interaction.json').write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))

if __name__ == '__main__': main()
