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
    output=ROOT/'.runtime/rule-arena'; output.mkdir(parents=True,exist_ok=True)
    params=StdioServerParameters(command=sys.executable,cwd=str(ROOT),args=[str(ROOT/'mcp/game/server.py')])
    async with stdio_client(params) as io, ClientSession(*io,read_timeout_seconds=timedelta(seconds=150)) as c:
        await c.initialize()
        async def call(name,**args): return data(await c.call_tool(name,args))
        run=await call('on',scene='rule_arena',seed=42,screenshot=False);sid=run['session_id'];print(run,flush=True)
        try:
            for _ in range(10):
                r=await call('step',operation='wait',session_id=sid,frames=40,screenshot=False)
                if r.get('state',{}).get('loaded'):break
            assert r['state']['loaded'],r
            samples=[]
            for i in range(11):
                if i: await call('step',operation='action',session_id=sid,action='arena_room',frames=4,screenshot=False)
                if i in (6,7): await call('step',operation='action',session_id=sid,action='arena_optics',frames=3,screenshot=False)
                r=await call('step',operation='wait',session_id=sid,frames=70,screenshot=i in (0,6,10));assert r['state']['stage']==i,r
                if 'screenshot' in r:shutil.copyfile(r['screenshot'],output/f'stage-{i:02}.png')
                samples.append(r['state'])
            (output/'viewport.json').write_text(json.dumps(samples,indent=2));print(samples[-1])
        finally:await call('close',session_id=sid)
if __name__=='__main__':asyncio.run(main())
