"""Exercise the in-world hotspots and preserve same-camera Forward+ comparison plates."""
from pathlib import Path
import shutil
from look_studies_e2e import Lab, ROOT


def main():
    out = ROOT / '.runtime/vesper-index'
    out.mkdir(exist_ok=True)
    with Lab() as lab:
        lab.send()
        lab.button('Vesper Index')
        lab.button('SDFGI')
        lab.button('Hide UI')

        def act(action):
            lab.click(*lab.state['vesper']['props'][action])
            lab.wait(30)
            return lab.state['vesper']

        def plate(name):
            shutil.copyfile(lab.capture(name), out / f'{name}.png')

        lab.wait(48)
        assert not act('cross')['crossed']
        plate('01-inquiry')
        assert act('leaf')['cinder']
        assert not act('wind')['released']
        plate('02-fire')
        assert act('lamp')['aim'] == 1
        assert act('wind')['released']
        plate('03-winding')
        assert not act('cross')['crossed']
        assert not act('leaf')['cinder']
        assert not act('cross')['crossed']
        assert act('lamp')['bridge']
        plate('04-crossing')
        assert act('cross')['crossed']
        lab.wait(120)
        plate('05-register')
    log = (lab.directory / 'godot.log').read_text(encoding='utf8')
    assert 'Forward+' in log and 'ERROR:' not in log, log
    print(f'Vesper: Forward+ verified. {out}')


if __name__ == '__main__':
    main()
