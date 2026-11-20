"""Render and verify the academy look studies through their normal UI and live MCP bridge."""
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'mcp/game'))
from server import Run

VIEWS = {'Service Stairs': 'service_down', 'Stair Anomaly': 'service_up',
         'Archive': 'archive', 'Ledger': 'night_register', 'Meridian': 'meridian'}


class Lab(Run):
    def __init__(self):
        super().__init__(1, architecture_lab=True)
        self.state = {}

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()

    def send(self, op='observe', **kwargs):
        result = self.request(op, timeout=45, **kwargs)
        data = json.loads(result[0]) if isinstance(result, list) else result
        self.state = data['state']
        return data

    def click(self, x, y):
        return self.send('click', x=x, y=y)

    def button(self, name):
        return self.click(*self.state['buttons'][name])

    def wait(self, frames):
        return self.send('wait', frames=frames)

    def capture(self, name):
        data = self.send(screenshot=True)
        assert data['viewport_size'] == [1280, 720], data
        source = Path(data['screenshot'])
        destination = self.directory / f'{name}.png'
        source.replace(destination)
        return str(destination)


def check(lab):
    lab.send()
    assert lab.state['view'] == 'Entrance'
    assert lab.state['exhibit_parts'] == 0
    lab.button('Service Stairs')
    assert lab.state['stair_flight'] == 'down'
    baseline = lab.state['shot']
    lab.button('Stair Anomaly')
    assert lab.state['stair_flight'] == 'up' and lab.state['shot'] == baseline
    lab.button('Archive')
    assert lab.state['view'] == 'Archive'
    archive = lab.state['shot']
    ledger = next(t for t in lab.state['targets'] if t['name'] == 'Read Night Register')
    lab.click(ledger['x'], ledger['y'])
    assert lab.state['view'] == 'Ledger' and lab.state['shot'] != archive
    lab.button('Meridian')
    rest = lab.state['meridian']
    assert 0 < rest['triangles'] <= rest['triangle_budget'] == 11500 and 0 < rest['moving_triangles'] <= rest['moving_budget'] == 7200, rest
    assert 0 < rest['surfaces'] <= rest['surface_budget'] == 22 and rest['running'], rest
    target = next(t for t in lab.state['targets'] if t['name'] == 'Start or stop Meridian')
    lab.wait(52)
    moving = lab.state['meridian']
    assert moving['running'] and all(abs(a - b) > 0.0005 for a, b in zip(rest['angles'], moving['angles'])), moving
    lab.click(target['x'], target['y'])
    paused = lab.state['meridian']
    lab.wait(18)
    assert not paused['running'] and paused['angles'] == lab.state['meridian']['angles'], paused
    lab.button('Entrance')
    assert lab.state['view'] == 'Entrance'
    lab.button('Meridian')
    assert lab.state['meridian'] == paused
    lab.click(target['x'], target['y'])
    assert lab.state['meridian']['running']
    return rest


def clean_frame(view, key):
    # Each session starts from the authored rest pose and leaves no overlay on the viewport.
    with Lab() as lab:
        lab.send()
        lab.button(view)
        lab.button('SDFGI')
        lab.button('Hide UI')
        lab.wait(120)
        assert not lab.state['hud_visible'] and lab.state['sdfgi'] and lab.state['view'] == view
        return lab.capture(key)


def main():
    with Lab() as lab:
        report = {'mechanism': check(lab), 'captures': {}}
        destination = lab.directory / 'look-studies-report.json'
    if '--clean' in sys.argv:
        report['captures'] = {key: clean_frame(view, key) for view, key in VIEWS.items()}
    destination.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(destination)
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
