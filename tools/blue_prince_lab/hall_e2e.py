"""Check the optional architecture hall through the same live Forward+ MCP bridge."""
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'mcp/game'))
from server import Run


def check():
    run = Run(1, architecture_lab=True)
    views = {}
    metrics = {}
    state = {}

    def request(op='observe', **kwargs):
        nonlocal state
        result = run.request(op, timeout=40, **kwargs)
        state = (json.loads(result[0]) if isinstance(result, list) else result)['state']
        return result

    def click(x, y):
        request('click', x=x, y=y)

    def button(name):
        click(*state['buttons'][name])

    def target(name):
        item = next(t for t in state['targets'] if t['name'] == name)
        click(item['x'], item['y'])

    def wait(frames):
        request('wait', frames=frames)

    def move(action, frames):
        request('action', action=action, frames=frames)

    def frame(name):
        result = request(screenshot=True)
        views[name] = json.loads(result[0])['screenshot']

    try:
        request()
        assert state['mode'] == 'architecture_lab', state
        wait(90)
        metrics['base'] = {k: state[k] for k in ('fps', 'draw_calls')}
        frame('entrance')
        target('Turn the helm')
        wait(46)
        assert 0.76 < state['helm_angle'] < 0.81, state
        button('Mechanisms')
        target('Open or close the cabinet')
        target('Start or stop the gear train')
        wait(60)
        assert state['cabinet_open'] and state['gear_running'] and state['gear_angle'] > 0.35, state
        frame('mechanisms')
        target('Start or stop the gear train')
        assert not state['gear_running'], state
        button('Airflow')
        frame('still_air')
        rest = state['banner_deflection']
        button('Gust')
        wait(25)
        assert state['wind'] and state['pendulum_radians'] > 0.02 and state['banner_deflection'] > rest + 0.12, state
        frame('gust')
        button('Gust')
        button('Landing')
        target('Open or close the stair door')
        wait(48)
        assert state['door_open'], state
        frame('open_door')
        button('Walk')
        move('move_left', 13)
        for _ in range(4):
            if state['player'][2] < -3.2:
                break
            frames = max(1, min(110, round((state['player'][2] + 3.5) * 60 / 3.3)))
            move('move_up', frames)
        assert -4.3 < state['player'][2] < -3.2, state
        move('move_right', 18)
        for _ in range(4):
            if state['player'][2] < -9.5:
                break
            frames = max(1, min(105, round((state['player'][2] + 9.8) * 60 / 3.3)))
            move('move_up', frames)
        assert state['player'][2] < -9.5 and 1.61 < state['player'][1] < 1.7, state
        button('Entrance')
        frame('entrance_after_interaction')
        button('SDFGI')
        wait(120)
        assert state['sdfgi'], state
        metrics['sdfgi'] = {k: state[k] for k in ('fps', 'draw_calls')}
        frame('sdfgi')
        button('SDFGI')
        wait(12)
        button('Hide UI')
        frame('clean')
        report = {'ok': True, 'session': run.id, 'metrics': metrics, 'views': views, 'log': str(run.log)}
        (run.directory / 'architecture-report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
        print(json.dumps(report, indent=2))
    except Exception:
        print(json.dumps({'session': run.id, 'views': views, 'log': str(run.log), 'last': state}, indent=2), file=sys.stderr)
        raise
    finally:
        run.close()


if __name__ == '__main__':
    check()
