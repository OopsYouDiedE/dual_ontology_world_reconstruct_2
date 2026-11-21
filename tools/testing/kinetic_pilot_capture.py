"""Real Forward+ capture via the project game MCP; saves only local test output."""
import asyncio
from datetime import timedelta
import json
from pathlib import Path
import shutil
import sys
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from rogue_smoke import ROOT, data

async def main():
    output=ROOT/'.runtime/kinetic'; output.mkdir(parents=True,exist_ok=True)
    params=StdioServerParameters(command=sys.executable,cwd=str(ROOT),args=[str(ROOT/'mcp/game/server.py')])
    async with stdio_client(params) as io, ClientSession(*io,read_timeout_seconds=timedelta(seconds=150)) as c:
        await c.initialize()
        async def call(name,**args): return data(await c.call_tool(name,args))
        run=await call('on',scene='kinetic_pilot',seed=42,screenshot=False);sid=run['session_id'];print(run,flush=True)
        try:
            samples=[]
            async def action(name):
                return await call('step',operation='action',session_id=sid,action=name,frames=4,screenshot=False)
            for stage in (3,6):
                if stage==6: await action('kin_next')
                for _ in range(50):
                    r=await call('step',operation='wait',session_id=sid,frames=40,screenshot=False)
                    if r['state'].get('loaded') and r['state'].get('stage')==stage: break
                assert r['state']['loaded'] and r['state']['stage']==stage,r
                await action('kin_pause')
                if not r['state']['optics']: await action('kin_optics')
                for j in range(5):
                    if j: await action('kin_seek')
                    if j==2 or j==3: await action('kin_wide')
                    if stage==6 and j==4: await action('kin_wide')
                    r=await call('step',operation='wait',session_id=sid,frames=5,screenshot=True)
                    assert r['state']['optics'],r
                    shutil.copyfile(r['screenshot'],output/f'stage-{stage}-{j}.png');samples.append(r['state']);print(r['state'],flush=True)
                    if j==1:
                        await action('kin_eye')
                        r=await call('step',operation='wait',session_id=sid,frames=4,screenshot=True)
                        shutil.copyfile(r['screenshot'],output/f'stage-{stage}-eye.png');await action('kin_eye')
                await action('kin_home')
                await action('kin_pause')
                for _ in range(2):
                    perf=await call('step',operation='wait',session_id=sid,frames=120,screenshot=False)
                    print('steady',perf['state'],flush=True)
            (output/'viewport.json').write_text(json.dumps(samples,indent=2));print(samples[-1])
        finally:await call('close',session_id=sid)
if __name__=='__main__':asyncio.run(main())
