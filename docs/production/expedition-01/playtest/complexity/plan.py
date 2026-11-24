"""Budgeted expedition *design candidates*. No production scene mutations."""
import argparse
from collections import defaultdict
from functools import lru_cache
import itertools
import json
import math
from pathlib import Path
import random

# Order is progression order, not a prohibition on backtracking in the game.
SPINE=('hall','archive','trial','switch','shaft','core','stair','gallery','exit')
# Each extra is a decision with an actual consequence (knowledge, supply or route).
# Parallel alcoves rejoin the same fixed downstream landmark. No new story prerequisites.
WINGS=(('archive','window','trial','observe',1),('trial','store','switch','take_oil',2),
       ('trial','loft','switch','take_clock',4),('shaft','north_window','core','post_hale',0),
       ('shaft','south_walk','core','spend_oil',0),('gallery','records','exit','inspect_record',0))
PRESETS={'short':(12,3),'standard':(20,6),'dense':(28,9)}


def make(mask,segments):
    edges=[]
    def edge(a,b,act='walk',need=0,give=0): edges.append((a,b,act,need,give))
    for a,b in zip(SPINE,SPINE[1:]): edge(a,b,'self_cross' if a=='shaft' else 'walk')
    for i,(a,n,b,act,give) in enumerate(WINGS):
        if not (mask>>i)&1: continue
        need=2 if n=='south_walk' else 0
        edge(a,n,act,need,give); last=n
        for k in range(segments[i]):
            nxt=f'{n}_passage_{k+1}'; edge(last,nxt); last=nxt
        edge(last,b)
    # Two distinct ways to cross on the SAME floor plan if a clock was picked up.
    edge('shaft','core','throw_decoy',need=4)
    return edges


def measure(edges):
    outgoing=defaultdict(list); rooms=set(); links=set()
    for a,b,act,need,give in edges:
        outgoing[a].append((b,act,need,give)); rooms.update((a,b)); links.add((a,b))
    reachable_links=set(); candidates=[]; peak_options={}
    @lru_cache(None)
    def walk(a,state):
        if a=='exit': return (0.,[a],0)
        opts=[e for e in outgoing[a] if e[2]&state==e[2]]
        if not opts: raise ValueError(f'trapped at {a} inventory={state}')
        k=len(opts); peak_options[a]=max(k,peak_options.get(a,1)); cost=math.log2(k); results=[]
        if k>1: candidates.append((a,state,k))
        for b,act,need,give in opts:
            reachable_links.add((a,b)); sub,path,count=walk(b,(state|give)&(~2 if act=='spend_oil' else -1)); results.append((cost+sub,[f'{a}:{act}']+path,(k>1)+count))
        return max(results,key=lambda r:r[0])
    peak,path,count=walk('hall',0)
    if reachable_links!=links: raise ValueError('unreachable passage')
    loops=len(links)-len(rooms)+1
    return dict(rooms=len(rooms),links=len(links),independent_loops=loops,map_units=len(rooms)+2*loops,
                decision_bits=peak,global_decision_bits=sum(math.log2(k) for k in peak_options.values()),decisions_on_peak=count,peak_route=path,decision_states=sorted(candidates))


def choose(seed,map_cap,decision_cap,global_cap=None):
    if not math.isfinite(decision_cap) or decision_cap<0 or map_cap<1: raise ValueError('budgets must be finite and nonnegative; map cap must be positive')
    if global_cap is not None and (not math.isfinite(global_cap) or global_cap<0): raise ValueError('global decision cap must be finite and nonnegative')
    rng=random.Random(seed); best=None; feasible=0
    # Exhaust the 3^6 catalog: each optional space is absent, direct, or extended.
    for choices in itertools.product(range(3),repeat=len(WINGS)):
        mask=sum((x>0)<<i for i,x in enumerate(choices)); seg=[int(x==2) for x in choices]; e=make(mask,seg)
        try: m=measure(e)
        except ValueError: continue
        if m['map_units']>map_cap or m['decision_bits']>decision_cap+1e-9 or (global_cap is not None and m['global_decision_bits']>global_cap+1e-9): continue
        feasible+=1
        # Balance utilization of both budgets; seeded selection from similar candidates.
        fit=(m['map_units']/map_cap + (m['decision_bits']/decision_cap if decision_cap else 0))/2
        rank=fit+rng.uniform(0,.07)
        if best is None or rank>best[0]: best=(rank,m,e)
    if best is None: raise ValueError('no feasible candidate: fixed spine needs at least 9 map units')
    _,metrics,edges=best
    return dict(schema=1,seed=seed,budgets=dict(map_units=map_cap,decision_bits=decision_cap,global_decision_bits=global_cap),candidates_checked=3**len(WINGS),feasible=feasible,metrics=metrics,
                edges=[dict(src=a,dst=b,action=act,requires=need,grants=give,consumes=2 if act=='spend_oil' else 0) for a,b,act,need,give in edges],
                rooms=sorted({e[i] for e in edges for i in (0,1)}))


def main():
    p=argparse.ArgumentParser();p.add_argument('--seed',type=int,default=31);p.add_argument('--preset',choices=PRESETS,default='standard');p.add_argument('--map-cap',type=int);p.add_argument('--decision-cap',type=float);p.add_argument('--global-decision-cap',type=float);p.add_argument('--out',type=Path,required=True);a=p.parse_args();mc,dc=PRESETS[a.preset]
    try: result=choose(a.seed,mc if a.map_cap is None else a.map_cap,dc if a.decision_cap is None else a.decision_cap,a.global_decision_cap)
    except ValueError as ex: p.error(str(ex))
    a.out.parent.mkdir(parents=True,exist_ok=True);a.out.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8');print(result['metrics'])

if __name__=='__main__': main()
