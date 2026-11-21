"""Capture each cast member and verify their own animation through the project GameMcp."""
import asyncio
from datetime import timedelta
import json
import math
from pathlib import Path
import sys

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

from r05_native_motion import rotation_delta

ROOT = Path(__file__).resolve().parents[2]
CAST = {
    'r05': ('base', 'suit', 'jacket', 'shirt'),
    'halvard': ('base', 'jacket', 'workwear'),
    'jane': ('base', 'shorts', 'sport'),
    'qingyue': ('base', 'skirt', 'jeans'),
    'lucian': ('base', 'shirt', 'fitted'),
    'ward': ('base', 'suit', 'fitted'),
    'shending': ('base', 'workwear', 'fitted'),
    'caretaker': ('base', 'suit', 'fitted'),
}
POSES = {'front': 0.0, 'reach': 0.75, 'knee': 2.25, 'side': 0.0, 'back': 0.0}


async def review():
    params = StdioServerParameters(command=sys.executable, cwd=str(ROOT), args=[
        '-B', str(ROOT/'mcp/game/server.py'), '--service', 'input', '--expected-project-root', str(ROOT),
    ])
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write, read_timeout_seconds=timedelta(seconds=90)) as client:
            await client.initialize()

            async def call(tool, **args):
                result = await client.call_tool(tool, args)
                text = next(part.text for part in result.content if part.type == 'text')
                if result.isError:
                    raise RuntimeError(text)
                return result.structuredContent or json.loads(text)

            initial = await call('on', scene='mpfb_wardrobe', screenshot=False)
            sid = initial['session_id']
            try:
                assert initial['renderer'] == 'forward_plus', initial
                state = initial['state']
                assert state.get('ready') and set(state['cast_buttons']) == set(CAST), state
                shots, layering, faces = {}, {}, {}

                async def click(coords, screenshot=False):
                    x, y = coords
                    return await call('step', session_id=sid, operation='click', x=x, y=y, screenshot=screenshot)

                for who, outfits in CAST.items():
                    state = (await click(state['cast_buttons'][who]))['state']
                    assert (state['character'], state['outfit'], state['test_mode']) == (who, 'base', 'native_motion'), state
                    assert set(state['wardrobe_buttons']) - {'before'} == set(outfits), state
                    shots[who], neutral_tracks = {}, {}
                    for outfit in outfits:
                        state = (await click(state['wardrobe_buttons'][outfit]))['state']
                        assert not state['wardrobe_error'] and state['outfit'] == outfit, state
                        assert state['bones'] == 53 and state['clips'] == ['MPFB_Pose_Check'], state
                        assert state['garment_meshes'] == (0 if outfit == 'base' else 2), state
                        expected = (f'/{who}_{outfit}.glb' if outfit != 'base' else
                                    '/r05_styled.glb' if who == 'r05' else f'/{who}-fit.glb')
                        assert state['model'].endswith(expected), state
                        shots[who][outfit] = {}
                        for pose, time in POSES.items():
                            frame = await click(state['pose_buttons'][pose], screenshot=True)
                            state = frame['state']
                            assert (state['character'], state['outfit'], state['pose']) == (who, outfit, pose), state
                            assert not state['playing'] and state['seconds'] == time, state
                            sample = state['right_elbow'], state['right_knee']
                            if outfit == 'base':
                                neutral_tracks[pose] = sample
                            else:
                                assert all(rotation_delta(a, b) < math.radians(0.15)
                                           for a, b in zip(sample, neutral_tracks[pose], strict=True)), state
                            shots[who][outfit][pose] = frame['screenshot']
                        if (who, outfit) in {('jane', 'sport'), ('qingyue', 'jeans')}:
                            assert state['pose'] == 'back' and state['shoes_visible'], state
                            hidden = await click(state['shoe_button'], screenshot=True)
                            state = hidden['state']
                            assert not state['shoes_visible'] and state['pose'] == 'back', state
                            layering[who] = {'shoes_on': shots[who][outfit]['back'], 'shoes_off': hidden['screenshot']}
                            state = (await click(state['shoe_button']))['state']
                            assert state['shoes_visible'], state
                        if outfit != 'base':
                            state = (await click(state['replay_center']))['state']
                            assert state['playing'] and state['seconds'] < 0.25, state
                            live = await call('step', session_id=sid, operation='wait', frames=36, screenshot=False)
                            state = live['state']
                            assert state['playing'] and state['seconds'] > 0.3, state
                            assert rotation_delta(neutral_tracks['front'][0], state['right_elbow']) > 0.35, state
                            for _ in range(2):
                                live = await call('step', session_id=sid, operation='wait', frames=120, screenshot=False)
                                state = live['state']
                                if state['finished']:
                                    break
                            assert state['finished'] and not state['playing'], state
                    assert rotation_delta(neutral_tracks['front'][0], neutral_tracks['reach'][0]) > .5
                    assert rotation_delta(neutral_tracks['front'][1], neutral_tracks['knee'][1]) > .5
                for who in ('lucian', 'ward', 'shending', 'caretaker'):
                    state = (await click(state['cast_buttons'][who]))['state']
                    faces[who] = {}
                    for version in ('before', 'base'):
                        if version not in state['wardrobe_buttons']:
                            continue
                        state = (await click(state['wardrobe_buttons'][version]))['state']
                        assert state['outfit'] == version and state['bones'] == 53, state
                        faces[who][version] = {}
                        for angle in ('portrait', 'profile'):
                            snapshot = await click(state['pose_buttons'][angle], screenshot=True)
                            state = snapshot['state']
                            assert state['pose'] == angle and state['seconds'] == 0, state
                            faces[who][version][angle] = snapshot['screenshot']
                state = (await click(state['cast_buttons']['r05']))['state']
                assert state['character'] == 'r05' and state['outfit'] == 'base', state
                print(json.dumps({'status': 'MPFB_WARDROBE_VIEWPORT_PASS', 'session': sid,
                                  'screenshots': shots, 'shoe_isolation': layering, 'faces': faces,
                                  'log': initial['log']}, indent=2))
            finally:
                await call('close', session_id=sid)


if __name__ == '__main__':
    asyncio.run(review())
