"""Run after export_whole.py using the game MCP Python environment."""
import json, shutil, sys
from pathlib import Path
root=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(root/'mcp/game'))
from server import Run
out=root/'.runtime/french-gn/main'
h=Run(1,scene_key='whole_church')
try:
    report=[]
    for i,name in enumerate(['front','rear','open','nave','nave-open','chevet']):
        if i: h.request('action',action='ui_accept',frames=2,timeout=90)
        msg,_=h.request('wait',frames=65,screenshot=True,timeout=120)
        r=json.loads(msg); s=r['state']; assert s['view']==i and set(s['parts'])=={'Exterior','Nave','Vault_webs','Aisles_and_galleries','Transept','Chevet','Timber_frames','Flying_buttresses','Tower_access'} and s['shell']==(i not in (2,4,5)) and r['renderer']=='forward_plus' and s['sdfgi'] and s['ssao'] and s['scale']==1, r
        shutil.copyfile(r['screenshot'],out/('godot-whole-'+name+'.png'));report.append(r)
    assert 'ERROR:' not in h.log.read_text(encoding='utf-8'),h.log
    (out/'godot-whole.json').write_text(json.dumps(report,indent=2));print(report)
finally:h.close()
