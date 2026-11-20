"""Sample the running Forward+ exhibit at regular, real movement-clock intervals."""
from pathlib import Path
from look_studies_e2e import Lab, ROOT


def main():
    out = ROOT / '.runtime/reference-plates/meridian-train'
    out.mkdir(parents=True, exist_ok=True)
    with Lab() as lab:
        lab.send()
        lab.button('Inspect train')
        if not lab.state['sdfgi']:
            lab.button('SDFGI')
        lab.button('Hide UI')
        lab.wait(20)
        poses = []
        for i in range(48):
            result = lab.send('action', action='meridian_inspect_frame', screenshot=True)
            assert result['renderer'] == 'forward_plus' and not lab.state['meridian']['running']
            (out / f'{i:02}.png').write_bytes(Path(result['screenshot']).read_bytes())
            poses.append(lab.state['meridian']['train'])
        for j in range(4):
            assert len({p[j] for p in poses}) > 1
        assert poses[-1] == lab.send('wait', frames=4)['state']['meridian']['train']
    assert 'ERROR:' not in lab.log.read_text(encoding='utf8')
    print(out, flush=True)


if __name__ == '__main__':
    main()
