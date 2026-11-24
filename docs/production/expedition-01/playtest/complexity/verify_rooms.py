"""Generate a budgeted proposal and physically gate its new two-port room prototypes."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
from plan import choose, SPINE


def verify(seed, map_cap, decision_cap, evaluate, global_cap=None, density=1.0, max_layers=3):
    if not 0<=density<=1 or type(max_layers) is not int or not 1<=max_layers<=5: raise ValueError('expected density in [0,1] and max_layers in 1..5')
    design=choose(seed,map_cap,decision_cap,global_cap)
    rooms=sorted(set(design['rooms'])-set(SPINE))
    # Stable per-room seeds: reordering rooms never reshuffles existing props.
    requests=[dict(room_id=r,density=density,max_layers=max_layers,seed=int.from_bytes(hashlib.sha256(f'{seed}:{r}'.encode()).digest()[:4],'big')) for r in rooms]
    evidence=evaluate(requests) if rooms else dict(ok=True,rooms=[])
    rows=evidence['rooms']
    passed=bool(evidence['ok'] and len(rows)==len(requests) and all(
        (row['room_id'],row['seed'])==(req['room_id'],req['seed']) and row['status']=='pass'
        and {t['direction'] for t in row['traversals']}=={'west_to_east','east_to_west'}
        and not row['layout_errors'] and len(row['traversals'])==2 and all(t['status']=='pass' for t in row['traversals'])
        for row,req in zip(rows,requests)))
    return dict(schema='expedition-proposal/v1',accepted=passed,plan=design,clutter=evidence,
                scope='Topology model plus isolated two-port clutter prototypes. Fixed landmarks, links between rooms, specific set pieces and interactions require production integration tests.')


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--seed',type=int,default=31);ap.add_argument('--map-cap',type=int,default=20);ap.add_argument('--decision-cap',type=float,default=6);ap.add_argument('--global-decision-cap',type=float);ap.add_argument('--density',type=float,default=1.0);ap.add_argument('--max-layers',type=int,default=3);ap.add_argument('--out',type=Path,required=True);a=ap.parse_args()
    spec=importlib.util.spec_from_file_location('clutter_runner',Path(__file__).resolve().parents[1]/'clutter/run.py');mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
    try: evidence=verify(a.seed,a.map_cap,a.decision_cap,mod.evaluate_rooms,a.global_decision_cap,a.density,a.max_layers)
    except ValueError as ex: ap.error(str(ex))
    a.out.parent.mkdir(parents=True,exist_ok=True);a.out.write_text(json.dumps(evidence,indent=2),encoding='utf8');print('accepted:',evidence['accepted'],'tested two-port rooms:',len(evidence['clutter']['rooms']));return 0 if evidence['accepted'] else 1

if __name__=='__main__': raise SystemExit(main())
