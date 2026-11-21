"""Headless test runner and observation-only reference controllers for Bellflower 03."""
from __future__ import annotations

import argparse
import gc
from collections import Counter, deque
from copy import copy, deepcopy
import json
import math
from pathlib import Path
import random
from statistics import median
import time

from bellflower import Run, World, eval_ast, read_config, refs

MODES=('B0','B2','B3_no_phase','B3_no_evidence','B3_no_joint','B4')


def readings(frame, limit):
    values={}
    if frame:
        for k,h in enumerate(frame['rays']):
            if h and h['kind']=='device' and 'q_um' in h['state'] and h['distance_um']<=1000*limit:
                slot='left' if h['point_um'][0]<0 else 'right'
                values.setdefault(slot,(k,h))
    return values


def proposal(c, frames, t):
    v=c['native']['waiver']; bind={}; support=[]; values={}
    for slot,field,off in sorted(refs(v['claim'])):
        tick=t+off*c['scan_every']
        h=readings(frames.get(tick),c['evidence_range_mm']).get(slot)
        if not h:
            return None
        k,h=h
        if bind.setdefault(slot,h['track'])!=h['track']:
            return None
        support.append([slot,field,tick,k]); values[slot,field,off]=h['state'][field]
    if eval_ast(v['claim'],lambda s,f,o:values.get((s,f,o))) is not True:
        return None
    return {'rule_id':c['native']['id'],'waiver_id':v['id'],'actor':c['native']['actor'],
            'bind':bind,'support':support},values


class Brain:
    """No seed, phase oracle, true mate position, world mesh or future reads."""
    def __init__(self,c,mode):
        public=('spawn_s_mm','rendezvous_s_mm','plate_s_mm','end_s_mm','move_mm_tick',
                'scan_every','lift_mm','public_ready_cam_mm','public_max_lead_ticks','native',
                'evidence_range_mm')
        self.c,self.mode={k:c[k] for k in public},mode
        self.frames={}
        self.mate_s=c['spawn_s_mm'][1]
        self.go=None
        self.witness=[]

    def choose(self,obs):
        c=self.c; mode=self.mode; t=obs['tick']; s=obs['s_mm']; yaw=obs['yaw_deg']
        if obs['scan'] is not None:
            self.frames[t]=obs['scan']
            self.frames.pop(t-4*c['scan_every'],None)
        if s<c['rendezvous_s_mm']:
            return ((1,0),0,None,False)
        if mode=='B0':
            return ((1,1),0,None,True)
        lip=c['plate_s_mm'][1]
        mate_move=1 if self.mate_s<lip or (self.go is not None and t>=self.go and obs['receipt']!='UNSUPPORTED') else 0
        if self.mate_s<lip:
            self.mate_s+=mate_move*c['move_mm_tick']
        turn=1 if s==c['end_s_mm'] and yaw<180 and mode!='B3_no_joint' else 0
        new=None
        if self.go is None and self.mate_s==lip and obs['scan'] and mode!='B3_no_evidence':
            found=proposal(c,self.frames,t)
            if found and (s==c['end_s_mm'] or mode=='B3_no_joint'):
                packet,values=found
                now=values['left','q_um',0]/1000-c['lift_mm']
                if mode in ('B0','B2') or (mode=='B3_no_phase' and now>=180):
                    delay=0
                elif mode in ('B4','B3_no_joint'):
                    # Estimate a rising cam slope from the last two signed hits. A leaf that
                    # may already have crossed the cusp is still checked by the safety margin
                    # band's lower end; no clock offset or spring range is supplied to the AI.
                    prev=values['left','q_um',-1]/1000-c['lift_mm']
                    slope=(now-prev)/c['scan_every']
                    delay=max(0,math.ceil((c['public_ready_cam_mm']-now)/slope)) if slope>0 else 1000
                    # A smaller measured secant can straddle the peak. In that case wait
                    # for a fresh rising flank instead of projecting across a reversal.
                    if slope<2.1:
                        delay=1000
                else:
                    delay=1000
                if delay<=c['public_max_lead_ticks']:
                    self.go=t+delay
                    new=packet
                    self.witness.append({'t':t,'proposal':packet,'release_planned':self.go,
                                         'observed':[values['left','q_um',-1],values['left','q_um',0],values['right','q_um',0]]})
                    mate_move=int(delay==0)
        return ((int(s<c['end_s_mm']),mate_move),turn,new,True)


def trial(w,mode, *, keep=False, timing="cpu", enforce=True):
    # The reducer owns an acyclic graph. Avoid unrelated generational collection
    # inside the charged section (reference counting still reclaims its objects).
    was_enabled=gc.isenabled()
    gc.disable()
    try:
        return _trial(w,mode,keep=keep,timing=timing,enforce=enforce)
    finally:
        if was_enabled:
            gc.enable()


def _trial(w,mode, *, keep=False, timing="cpu", enforce=True):
    clock=time.thread_time_ns if timing=="cpu" else time.perf_counter_ns
    a=Run(w,tick_limit=w.c['benchmark_ticks'], scan_initial=False)
    brain=Brain(a.c,mode); tape=[]
    # Setup is outside the match; the first scan is inside step zero like all others.
    window=0; peak=0; peak_window=0; wall_peak=0
    while a.result=='running':
        t=a.t
        if t%a.c['scan_every']==0:
            window=0
        wall_start=time.perf_counter_ns()
        start=clock()
        m,d,p,j=brain.choose(a.obs())
        a.step(m,d,p,j)
        used=clock()-start
        wall_peak=max(wall_peak,time.perf_counter_ns()-wall_start)
        window+=used; peak=max(peak,used); peak_window=max(peak_window,window)
        if keep:
            tape.append([m,d,p,j])
        if enforce and (used>a.c['step_ns'] or window>a.c['cycle_ns']):
            a.result='budget_exceeded'
    return {'result':a.result,'ticks':a.t,'applied':a.applied,'release':a.release_tick,
            'last_clear':a.clear_tick,'last_margin_ticks':a.forecast_margin if a.clear_tick is not None else None,
            'peak_wall_step_ms':round(wall_peak/1e6,3),'peak_step_ms':round(peak/1e6,3),'peak_cycle_ms':round(peak_window/1e6,3),
            'witness':brain.witness, **({'tape':tape} if keep else {})}


def stage_sweep_certificate(w):
    """Validate the geometric side conditions for a closed, exact lane hazard abstraction."""
    c=w.c; body_top=c['half_actor_mm'][1]*2
    assert c['gate_half_depth_mm']==max(radius for _,radius in c['low_bells']['profile_mm'])
    assert c['low_bells']['x_mm']==max(c['lane_x_mm']) and c['lane_x_mm'][0]==-c['low_bells']['x_mm']
    loaded_clearance=min(w.gate_min)-140+c['lift_mm']-body_top  # Include the visible clappers.
    assert loaded_clearance>0
    assert all(g+c['cam_amplitude_mm']<body_top for g in w.gate_min)
    assert c['plate_s_mm'][1]+c['move_mm_tick']<c['approach_s_mm']
    assert c['approach_s_mm']+c['move_mm_tick']<c['gate_s_mm']-c['gate_half_depth_mm']-c['half_actor_mm'][2]
    assert c['end_s_mm']>c['gate_s_mm']+c['gate_half_depth_mm']+c['half_actor_mm'][2]
    assert c['move_mm_tick'] < c['plate_s_mm'][1]-c['plate_s_mm'][0]
    hx,_,hz=c['half_actor_mm']
    def lane_clear(lo,hi):
        return (lo[1]>=body_top or hi[1]<=0 or hi[2]<=-c['end_s_mm']-hz or
                lo[2]>=-min(c['spawn_s_mm'])+hz or all(
                    lo[0]>=x+hx or hi[0]<=x-hx for x in c['lane_x_mm']))

    def swept(points,axis,lo,hi):
        """Exact coordinate extrema of each vertex over a continuous roll interval."""
        az,axis_y,r,_,_=axis
        ca,sa=math.cos(az),math.sin(az)
        rx,_,rz=c['root_mm']
        low,high=[math.inf]*3,[-math.inf]*3
        for x,y,z in points:
            center=(rx+ca*(r+x),axis_y,rz+sa*(r+x))
            for dim,(p,u,v) in enumerate(zip(center,(-sa*z,y,ca*z),(sa*y,z,-ca*y))):
                angles=[lo,hi]
                stationary=math.atan2(v,u)
                angles.extend(k for k in (stationary-math.pi,stationary,stationary+math.pi) if lo<k<hi)
                values=[p+u*math.cos(a)+v*math.sin(a) for a in angles]
                low[dim]=min(low[dim],min(values)); high[dim]=max(high[dim],max(values))
        return low,high

    lowest_moving=math.inf
    for g,axis in w.arm_axes.items():
        angle=math.radians(c['crown']['twist_deg'][axis[3]])
        attachments=[(w.group_bounds[h],tap) for h,(owner,tap) in w.hangers.items() if owner==g]
        for i in range(8):
            a,b=-angle+i*angle/4,-angle+(i+1)*angle/4
            for h in w.groups[g]:
                lo,hi=swept(h.verts,axis,a,b)
                lowest_moving=min(lowest_moving,lo[1])
                assert lane_clear(lo,hi),h.key
            for (lo,hi),tap in attachments:
                p0,p1=swept([tap],axis,a,b)
                lowest_moving=min(lowest_moving,lo[1]+p0[1])
                assert lane_clear([x+y for x,y in zip(lo,p0)],[x+y for x,y in zip(hi,p1)]),g
    assert lowest_moving>0
    for g in ('room','flower','latch','carriage','plate'):
        for h in w.groups[g]:
            if h.key.startswith('pedal') or h.key=='floor' or 'marker' in h.key:
                continue
            assert lane_clear(h.low,h.high),h.key
    assert c['lane_x_mm'][1]-c['lane_x_mm'][0]>2*c['half_actor_mm'][0]
    return {'loaded_min_clearance_mm':round(loaded_clearance,3),
            'crown_min_floor_clearance_mm':round(lowest_moving,3), 'solid_sweep_validated':True}


def strict(c,active):
    """Reachability over ordered regions, over-approximating all strict tick inputs.

    At most one physical transition per lane per step. Load delay is nondeterministic
    (0..actual lift time); full lift implies plate pressed. High-open movement is
    possible only while loaded. With no previous legal release, a grace window is
    unreachable. The proof is inductive, so a timeout is not needed for this BFS.
    """
    # 0 inlet, 1 plate, 2 approach, 3 shutter slab, 4 far side.
    left={0:(0,2),2:(0,2,3),3:(2,3,4),4:(3,4)}
    right={0:(0,1),1:(0,1,2),2:(1,2,3),3:(2,3,4),4:(3,4)}
    start=0,0,False
    q=deque([start]); seen={start}; win=impact=False
    while q:
        l,m,opened=q.popleft()
        both_far=all((l,m)[i]==4 for i in active)
        win |= both_far
        impact |= not opened and any((l,m)[i]==3 for i in active)
        denied=eval_ast(c['native']['deny'],lambda s,f,o:both_far)
        for a in left[l] if 0 in active else [0]:
            for b in right[m] if 1 in active else [0]:
                if m==1 and b!=1 and denied:
                    continue
                if not opened and ((a==3 and l!=3) or (b==3 and m!=3)):
                    continue
                for ready in (False,True) if b==1 and not opened else (b==1,):
                    to=(a,b,ready)
                    if to not in seen:
                        seen.add(to); q.append(to)
    return {'states':len(seen),'can_finish':win,'impact_reachable':impact}


def observability(w):
    """Every aligned 3 Hz sample across a full cam revolution, from the same alcove."""
    c=w.c; counts=Counter(); misses=Counter(); twins=Counter()
    a=Run(w); a.pos[0]=c['alcove_s_mm']; a.pos[1]=c['plate_s_mm'][1]
    for armed in (False,True):
        a.lift=c['lift_mm'] if armed else 0
        a.held=armed
        # Enumerate all 20 scan-grid phase offsets: exactly one visit per physical tick of the cam.
        for alignment in range(c['scan_every']):
            for t in range(alignment,2*w.half,c['scan_every']):
                a.t=t
                truth='ring' if a.ring() else ('pinch' if a.pinch() else 'other')
                if truth=='other':
                    continue
                counts[truth]+=1
                scan,_=w.scan(a)
                hit=readings(scan,c['range_mm'])
                if len(hit)<2:
                    misses[truth]+=1
                    continue
                twins[truth]+=1
                q0,q1=(hit[s][1]['state']['q_um']//1000 for s in ('left','right'))
                seen='ring' if q0>=c['lift_mm']+c['ring_cam_mm'] else ('pinch' if max(q0,q1)<=c['cam_amplitude_mm'] else 'other')
                misses[truth]+=truth!=seen
    return {k:{'samples':counts[k],'two_hits':twins[k],'misses':misses[k],
               'miss_rate':round(misses[k]/max(1,counts[k]),7)} for k in ('ring','pinch')}


def collapse(w):
    c=w.c; a=Run(w); before,_=w.scan(a,eye=c['views']['D-ray-scan']['scan_p_mm'],yaw=0)
    # Look outside the two lanes as well: the diagonal spots project silhouettes sideways.
    probes=[(x,30,z) for x in range(-6500,6501,250) for z in range(-9100,5101,250)]
    poses=w.poses(a); tree=w.scene_tree(poses)
    before_light=[w.light(poses,p,tree) for p in probes]
    contact=all(a.contact(i,c['gate_s_mm'],c['gate_s_mm'],a.wings()[i],a.wings()[i]) for i in range(2))
    a.hidden=True
    after,_=w.scan(a,eye=c['views']['D-ray-scan']['scan_p_mm'],yaw=0)
    poses=w.poses(a); tree=w.scene_tree(poses)
    after_light=[w.light(poses,p,tree) for p in probes]
    assert before!=after and all(x<=y for x,y in zip(before_light,after_light))
    assert all(g not in w.poses(a) for g in ('wing0','wing1','flower','latch','carriage','plate'))
    assert all(not h or h['kind']!='device' for h in after['rays'])
    for _ in range(math.ceil((c['end_s_mm']-min(c['spawn_s_mm']))/c['move_mm_tick'])+math.ceil(c['recruit_range_mm']/c['move_mm_tick'])+1):
        a.step((1,1),join=True)
    return {'hazard_before':contact,'after':a.result,'brighter_probes':sum(x<y for x,y in zip(before_light,after_light))}


def validate(c,seeds,full,out,timing):
    rows=[]
    for idx,seed in enumerate(seeds):
        strong=idx>=len(seeds)//2
        gc.collect()
        w=World(c,seed,strong)
        geo=stage_sweep_certificate(w)
        solo=[strict(c,[i]) for i in range(2)]; team=strict(c,[0,1])
        cases={m:trial(w,m,keep=m=='B4',timing=timing) for m in (MODES if full else ('B4',))}
        witness=cases['B4']
        tape=witness.pop('tape')
        if witness['result']=='budget_exceeded':
            # Prove existence independently of this host's timing; never upgrade
            # the timed outcome or count this replay as a benchmark win.
            witness=trial(w,'B4',keep=True,timing=timing,enforce=False)
            tape=witness.pop('tape')
        replay=Run(w,tick_limit=c['benchmark_ticks'])
        tamper_rejected=False
        for move,turn,p,j in tape:
            if p and not tamper_rejected:
                replay.request_scan()
                probe=copy(replay)
                probe.proposal_used=replay.proposal_used.copy()
                swapped=deepcopy(p)
                swapped['bind']['left']=swapped['bind']['right']
                tamper_rejected=(probe.judge(swapped)=='UNSUPPORTED' and probe.sanity==replay.sanity-8)
            replay.step(move,turn,p,j)
        replays=(replay.result==witness['result']=='win' and replay.applied and replay.t==witness['ticks'])
        row={'seed':seed,'band':'strong' if strong else 'normal','geometry':geo,
             'native_solo':solo,'native_team':team,'witness_replay':replays,
             'tamper_rejected':tamper_rejected, 'legal_witness':witness['witness'],
             'vision':observability(w) if full else {},'ablation':cases}
        rows.append(row)
        print(row['band'],seed, {m:(v['result'],v['last_margin_ticks']) for m,v in cases.items()},row['vision'],flush=True)
    summary={}
    for band in ('normal','strong'):
        cohort=[r for r in rows if r['band']==band]
        if cohort:
            summary[band]={m:{'wins':sum(r['ablation'][m]['result']=='win' for r in cohort),'n':len(cohort),
                              'results':dict(Counter(r['ablation'][m]['result'] for r in cohort))} for m in rows[0]['ablation']}
            for m,v in summary[band].items():
                v['win_rate']=v['wins']/v['n']
                margins=[r['ablation'][m]['last_margin_ticks'] for r in cohort
                         if r['ablation'][m]['result']=='win']
                if margins:
                    v['last_margin_ticks']={'min':min(margins),'median':median(margins),'max':max(margins)}
    vision_summary={}
    if full:
        for k in ('ring','pinch'):
            samples=sum(r['vision'][k]['samples'] for r in rows)
            misses=sum(r['vision'][k]['misses'] for r in rows)
            vision_summary[k]={'samples':samples,'misses':misses,'miss_rate':misses/max(1,samples)}
    collapse_results=collapse(World(c,seeds[0]))
    structure_passed=all(not r['native_team']['can_finish'] and not r['native_team']['impact_reachable'] and
               not any(s['impact_reachable'] for s in r['native_solo']) and r['witness_replay'] and r['tamper_rejected'] and
               all(v['misses']==0 for v in r['vision'].values()) for r in rows)
    structure_passed &= collapse_results['hazard_before'] and collapse_results['after']=='win' and collapse_results['brighter_probes']>0
    passed=structure_passed and all(r['ablation']['B4']['result']=='win' for r in rows)
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps({'passed':passed,'structure_passed':structure_passed,'timing':timing,'summary':summary,'vision':vision_summary,'collapse':collapse_results,'seeds':rows},indent=2),encoding='utf8')
    print(json.dumps({'passed':passed,'structure_passed':structure_passed,'summary':summary,'vision':vision_summary,'collapse':collapse_results},indent=2))
    return int(not passed)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--master-seed',type=int,default=3103)
    ap.add_argument('--count',type=int,default=20)
    ap.add_argument('--timing',choices=['cpu','wall'],default='cpu',
                    help='Charge the single referee thread, or use strict elapsed wall time.')
    ap.add_argument('--quick',action='store_true')
    ap.add_argument('--out',type=Path,default=Path('.runtime/bellflower/report.json'))
    args=ap.parse_args()
    if not 1<=args.count<=100:
        ap.error('--count must be in 1..100')
    seeds=random.Random(args.master_seed).sample(range(1,2**31),args.count)
    return validate(read_config(),seeds,not args.quick,args.out,args.timing)


if __name__=='__main__':
    raise SystemExit(main())
