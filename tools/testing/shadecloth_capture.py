"""Capture the actual Forward+ shadow sweep with the game MCP."""
import argparse
import asyncio
from datetime import timedelta
import json
from pathlib import Path
import shutil
import sys

from PIL import Image, ImageChops
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from rogue_smoke import ROOT, data


async def capture(seed, output):
    output.mkdir(parents=True, exist_ok=True)
    params = StdioServerParameters(command=sys.executable, cwd=str(ROOT), args=[
        str(ROOT / 'mcp/game/server.py'), '--service', 'input', '--expected-project-root', str(ROOT)])
    async with stdio_client(params) as (reader, writer):
        async with ClientSession(reader, writer, read_timeout_seconds=timedelta(seconds=110)) as session:
            await session.initialize()
            start = data(await session.call_tool('on', {'scene':'shadecloth','seed':seed,'screenshot':False}))
            async def call(tool, **args):
                return data(await session.call_tool(tool, {'session_id':start['session_id'], **args}))

            async def press(action):
                return await call('step', operation='action', action='shade_'+action, frames=3, screenshot=False)

            async def shot(name):
                report = await call('step', operation='wait', frames=14, screenshot=True)
                assert report['renderer']=='forward_plus', report
                shutil.copyfile(report['screenshot'],output/f'{name}.png')
                print(name,report['state']['tick'],flush=True)
                return report['state']

            try:
                frames = {}
                for name in ('A-section','B-floor','C-folds','D-sweep'):
                    await press(name[0].lower())
                    frames[name] = state = await shot(name)
                    assert state['view']==name and state['cloth_visible'] and state['cloth_vertices']==299, state
                    assert state['diagnostic'] and state['ray_count']==27, state
                assert frames['A-section']['first_vertex_mm']!=frames['D-sweep']['first_vertex_mm']
                await press('a')
                await press('uncover')
                assert not (await shot('E-uncovered'))['cloth_visible']
                with Image.open(output/'A-section.png') as covered, Image.open(output/'E-uncovered.png') as uncovered:
                    # Crop out the diagnostic title and cloth; measure only the lower half of the hall.
                    w,h = covered.size
                    assert uncovered.size == (w,h) and w >= 1280
                    box = (int(w*.22),int(h*.57),int(w*.81),int(h*.89))
                    gain = ImageChops.subtract(uncovered.crop(box).convert('L'), covered.crop(box).convert('L'))
                    relit = sum(gain.histogram()[30:])
                assert relit > 1500, relit
                await press('uncover')
                initial = (await call('observe', screenshot=False))['state']
                await press('play')
                animated = (await call('step',operation='wait',frames=40,screenshot=False))['state']
                assert animated['view']=='A-section' and animated['tick']>initial['tick'] and animated['diagnostic'], animated
                live = (await press('live'))['state']
                later = (await call('step',operation='wait',frames=40,screenshot=False))['state']
                assert live['view']==later['view']=='live' and later['tick']>live['tick'], (live,later)
                assert live['first_vertex_mm']!=later['first_vertex_mm'], (live,later)
                log = Path(start['log'])
                errors = [line for line in log.read_text(encoding='utf-8').splitlines()
                          if 'ERROR:' in line and not (
                              line.startswith('ERROR: Error opening gamepad at index ')
                              and 'Failed to obtain XInput device capabilities' in line)]
                assert not errors, (log, errors)
                (output/'report.json').write_text(json.dumps({'views':frames,'relit_pixels':relit,'log':str(log)},indent=2)+'\n')
            finally:
                await call('close')


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seed', type=int, default=1)
    parser.add_argument('--output', type=Path, default=ROOT/'.runtime/shadecloth/plates')
    args = parser.parse_args()
    asyncio.run(capture(args.seed,args.output.resolve()))
