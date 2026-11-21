"""Line-framed adapter for Godot. The renderer owns no gameplay state."""
import argparse
import json
import sys

from bellflower import read_config, World, Run
from verify import Brain, proposal


def main(config=read_config, world_type=World, run_type=Run):
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--seed',type=int,default=1)
    p.add_argument('--strong',action='store_true')
    args=p.parse_args()
    w=world_type(config(),args.seed,args.strong)
    a=run_type(w)
    brain=Brain(w.c,'B4')
    diagnostic=False

    def send(doc):
        print(json.dumps(doc,separators=(',',':')),flush=True)

    send({'init':w.packet(),'state':a.display()})
    for line in sys.stdin:
        try:
            req=json.loads(line)
            op=req['op']
            if op=='quit':
                return
            if op=='preview':
                options={key:req[key] for key in ('uncovered','frame_tick') if key in req}
                send(a.preview(req['view'],req.get('hidden',False),req.get('phase','pinch'),**options))
                continue
            if op=='reset':
                a=run_type(w); brain=Brain(w.c,'B4'); diagnostic=False
            elif op=='hide':
                a.hidden=not a.hidden
                diagnostic=True
                a.lease=-1
                a.frames.clear()
                brain.frames.clear()
                a.last_scan,a.beams=w.scan(a)
            elif op=='step':
                if req.get('auto'):
                    m,d,pr,j=brain.choose(a.obs())
                else:
                    m,d,j=req['move'],req['turn'],req.get('join',False)
                    found=proposal(a.c,a.frames,a.t) if req.get('persuade') else None
                    pr=found[0] if found else None
                a.step(m,d,pr,j)
            else:
                raise ValueError(op)
            send(dict(a.display(),diagnostic=diagnostic))
        except (KeyError, ValueError, AssertionError, TypeError) as exc:
            send({'error':f'{type(exc).__name__}: {exc}'})


if __name__=='__main__':
    main()
