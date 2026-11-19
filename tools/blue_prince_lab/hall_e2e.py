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
        assert state['mode'] == 'architecture_lab' and state['toon'] and state['ink'] and not state['sdfgi'], state
        wait(120)
        wait(90)
        metrics['base'] = {k: state[k] for k in ('fps', 'draw_calls')}
        composition = state['entrance_landmarks']
        assert abs(composition['threshold'][1] - 0.714) < 0.013, composition
        assert abs(composition['runner_far_left'][0] - 0.469) < 0.012, composition
        assert abs(composition['first_pendant'][0] - 0.293) < 0.025, composition
        frame('entrance')
        button('Ink')
        assert not state['ink'], state
        frame('no_ink')
        button('Toon')
        assert not state['toon'] and not state['ink'], state
        frame('continuous_diffuse')
        button('Toon')
        button('Ink')
        assert state['toon'] and state['ink'], state
        button('Tourbillon')
        initial = state['tourbillon_angles']
        frame('tourbillon_initial')
        target('Start or stop the tourbillon')
        wait(65)
        assert state['tourbillon_running'], state
        delta = [after - before for before, after in zip(initial, state['tourbillon_angles'])]
        assert delta[0] > 0.16 and delta[1] > 0.27 and delta[2] < -0.5, state
        assert abs(delta[0] * 22 - delta[1] * 13) < 0.001, delta
        assert abs(delta[0] * 22 + delta[2] * 7) < 0.001, delta
        frame('tourbillon_running')
        target('Start or stop the tourbillon')
        stopped = state['tourbillon_angles']
        wait(8)
        assert not state['tourbillon_running'] and state['tourbillon_angles'] == stopped, state
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
        button('Walk')

        def walk_to(z, min_final_z=None):
            for _ in range(8):
                if state['player'][2] < z + 0.08:
                    break
                frames = max(1, min(85, round((state['player'][2] - z) * 60 / 3.3)))
                move('move_up', frames)
            if min_final_z is not None:
                assert min_final_z < state['player'][2] < z + 0.10, state

        walk_to(-8.68, -9.13)
        move('move_up', 14)
        assert -9.14 < state['player'][2] < -8.5, state
        button('Entrance')
        target('Open or close the hall door')
        wait(48)
        assert state['door_open'], state
        frame('open_door')
        button('Walk')
        walk_to(-10.7, -13.0)
        move('move_left', 15)
        walk_to(-16.12, -17.02)
        move('move_right', 16)
        walk_to(-22.25, -22.95)
        assert 1.61 < state['player'][1] < 1.70, state
        frame('climbed_stairs')
        button('Landing')
        frame('stairs')
        button('Entrance')
        target('Open or close the hall door')
        wait(48)
        assert not state['door_open'], state
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
        report = {'ok': True, 'session': run.id, 'metrics': metrics, 'composition': composition, 'views': views, 'log': str(run.log)}
        (run.directory / 'architecture-report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
        print(json.dumps(report, indent=2))
    except Exception:
        print(json.dumps({'session': run.id, 'views': views, 'log': str(run.log), 'last': state}, indent=2), file=sys.stderr)
        raise
    finally:
        run.close()


if __name__ == '__main__':
    check()
