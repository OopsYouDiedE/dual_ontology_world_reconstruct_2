"""Reproducible shared-lane adjudication and frozen roster enrollment."""
import argparse
from collections import Counter
from dataclasses import asdict
from hashlib import sha256
import json
from pathlib import Path
import platform

from . import benchlock
from .diagnostics import diagnose, sample, scoreboard
from .fuel import ENTRY_FUEL, STANDARD_FUEL
from .gates import evaluate_seed
from .oracle import reproducible
from .physics import Rng, digest
from .policies import REFLEX, reference_program
from .sandbox import LANE_ID, Program
from .world import Config, World


def load_data(path, limit=10_000_000):
    blob = path.read_bytes()
    if len(blob) > limit:
        raise ValueError(f'input {path} is too large')
    return json.loads(blob.decode('utf-8-sig')), sha256(blob).hexdigest()


def play(seed, policy, config, *, trace):
    w = World(seed, config)
    obs = w.observe()
    last_level = None
    decisions = []
    while w.status == 'RUNNING':
        level = obs['level']
        d = policy(obs, ENTRY_FUEL if last_level != level else STANDARD_FUEL)
        last_level = level
        decisions.append(sample(w, obs, d) if trace else dict(tick=w.tick, room=level,
                         exhaust=d.exhausted, candidates=d.candidates, fuel=d.fuel,
                         line=d.fuel_line, fault=d.fault, rejected=d.rejected, actions=d.actions))
        obs = w.step(d.actions)
    return w, decisions


def policy_chain(decisions):
    keys = ('tick','room','fuel','exhaust','candidates','line','fault','rejected','actions')
    return digest([[d[k] for k in keys] for d in decisions])


def score_run(seed, program, config=None, *, repeat_policy=False):
    w, timeline = play(seed,program.start(),config,trace=True)
    chain = policy_chain(timeline)
    if repeat_policy:
        again, repeated = play(seed,program.start(),config,trace=False)
        repeat_match = chain == policy_chain(repeated) and w.checkpoints == again.checkpoints
    else:
        repeat_match = None
    budget = dict(fuel=sum(d['fuel'] for d in timeline), exhausted=sum(d['exhaust'] for d in timeline),
                  exhausted_without_candidate=sum(d['exhaust'] and not d['candidates'] for d in timeline),
                  submitted=sum(d['candidates'] for d in timeline), decisions=len(timeline),
                  faults=sum(bool(d['fault']) for d in timeline),
                  rejected_candidates=sum(d['rejected'] for d in timeline))
    persuasion = sum(e['kind']=='PERSUADED' for e in w.events)
    false_persuasion = sum(e['kind']=='INVALID_EVIDENCE' for e in w.events)
    immature_retries = sum(e['kind']=='EVIDENCE_REJECTED' and e.get('reason')=='immature' for e in w.events)
    coupled = set()
    for room in w.rooms:
        i = room['index']
        used = [r for r in w.events if r['room']==i]
        targets = {p['id'] for p in room['phases']}
        phased = {(e['id'],op) for e in room['entities'] for op,b in e.get('ops',{}).items()
                  if any(f'"phase","{target}"' in json.dumps(b['when'],separators=(',',':')) for target in targets)}
        if (any(r['kind']=='INTERACT' and r['actor'] for r in used)
            and any(r['kind']=='PERSUADED' for r in used)
            and any((r.get('action',{}).get('target_entity_id'),r.get('action',{}).get('op_type')) in phased
                    for r in used if r['kind']=='INTERACT')):
            coupled.add(i)
    survived = w.status == 'CAMP'
    diagnostics = diagnose(w,timeline)
    stats = {'status':w.status,'completed':w.index,'tick':w.tick,'score':round(0.8*survived+0.02*w.index,4),
             'persuaded':persuasion,'immature_retries':immature_retries,'persuasion_accuracy':persuasion/(persuasion+false_persuasion) if persuasion+false_persuasion else None,
             'sanity_retained':sum(a.sanity for a in w.actors[1:])/(10000*(len(w.actors)-1)) if len(w.actors)>1 else None,
             'coupled_phase_persuasion_rooms':sorted(coupled),'compute':budget,
             'failure_tags':[d['tag'] for d in diagnostics],'failure_diagnostics':diagnostics,
             'unseen_registered_fixtures':w.unseen_required,'reproducible':reproducible(w),
             'policy_rerun_matches':repeat_match,'policy_chain_sha256':chain,'state_sha256':w.state_hash()}
    if not survived:
        rows = [e for e in w.events if e['room']==w.index+1]
        team_samples = w.seen[0] | {e for frame in w.query_frames.values() for e in frame['seen']}
        stats['failure_context'] = {'room':w.index+1,'room_tick':w.room_tick,'last_result':w.last_result,
            'events':dict(sorted(Counter(e['kind'] for e in rows).items())),
            'unseen_targets':sorted(w.required_targets()-team_samples),
            'open_rule_conflicts':[{'actor':a,'rule_ids':list(ids)} for a,ids in sorted(w.breakers)]}
    return w, stats, timeline


def summarize(results):
    n = len(results)
    if not n:
        return None
    tags = Counter(tag for r in results for tag in r['failure_tags'])
    depth = Counter(r['completed'] for r in results)
    midgame_cognitive = sum(4 <= r['completed'] < 10 and not r['compute']['faults'] and not r['compute']['rejected_candidates'] and
        bool(set(r['failure_tags']) & {'EVIDENCE_IMMATURE','RULE_DEADLOCK_STALL','TEMPORAL_PHASE_ERROR'})
        for r in results)
    summary = {'count':n,'clear_rate':sum(r['status']=='CAMP' for r in results)/n,
        'first_three_rate':sum(r['completed']>=3 for r in results)/n,
        'reached_midgame_rate':sum(r['completed']>=4 for r in results)/n,
        'midgame_rules_timing_failure_rate':midgame_cognitive/n,
        'mean_depth':sum(r['completed'] for r in results)/n,'depth_histogram':dict(sorted(depth.items())),
        'mean_score':sum(r['score'] for r in results)/n,'reproducible_rate':sum(r['reproducible'] for r in results)/n,
        'failure_counts':dict(sorted(tags.items())),
        'mechanism_coupling_rate':sum(len(r['coupled_phase_persuasion_rooms']) for r in results)/(n*10)}
    for k in ('execution_efficiency','persuasion_accuracy','sanity_retained','reasoning_operations_per_executed_action'):
        values = [r[k] for r in results if r[k] is not None]
        summary[k] = sum(values)/len(values) if values else None
    return summary


def acceptance(output):
    target, sol = (output['summary'].get(n) for n in ('target','sol'))
    size = len(output['seeds'])
    checks = {'blind_manifest':bool(output.get('blind_manifest_sha256')),
        'all_design_gates':output['validity']=={'zero_panic':1.,'reproducible':1.,'sampling_pass':1.,'invalid_failure_count':0},
        'all_action_replays_match':output['all_contestant_replays_match'],
        'all_policy_reruns_match':output['all_policy_reruns_match'],
        'target_clears_90pct':bool(target and target['count']==size and target['clear_rate']>=.9),
        'sol_no_full_clear':bool(sol and sol['count']==size and sol['clear_rate']==0),
        'sol_first_three_90pct':bool(sol and sol['first_three_rate']>=.9),
        'sol_reaches_r5_80pct':bool(sol and sol['reached_midgame_rate']>=.8),
        'sol_midgame_rule_or_phase_80pct':bool(sol and sol['midgame_rules_timing_failure_rate']>=.8)}
    return checks, all(checks.values())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite',choices=['standard','holdout','generalization','both'],default='standard')
    parser.add_argument('--seeds',nargs='+',type=int)
    parser.add_argument('--random-seeds',type=int,default=0)
    parser.add_argument('--seed-key',type=int,default=1)
    parser.add_argument('--roster',nargs='+',choices=['target','reflex','no_persuasion','no_phase_memory','sol'],default=None)
    parser.add_argument('--sol-policy',type=Path)
    parser.add_argument('--freeze-lock',type=Path)
    parser.add_argument('--blind-manifest',type=Path)
    parser.add_argument('--config',type=Path)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--gates-only',action='store_true')
    parser.add_argument('--require-acceptance',action='store_true')
    parser.add_argument('--verify-policy-rerun',action='store_true')
    args = parser.parse_args()
    if not 0 <= args.random_seeds <= 1000:
        parser.error('--random-seeds must be in [0,1000]')
    blind = args.suite != 'standard'
    if blind and (not all((args.sol_policy,args.freeze_lock,args.blind_manifest)) or args.seeds or args.random_seeds):
        parser.error('blind suites require --sol-policy, --freeze-lock and --blind-manifest, and use only their seeds')
    if not blind and any((args.sol_policy,args.freeze_lock,args.blind_manifest,args.require_acceptance)):
        parser.error('use a blind suite for frozen scoring; use the separate training CLI on public seeds')
    names = list(dict.fromkeys(args.roster or (['target','reflex','no_persuasion','no_phase_memory','sol'] if blind else ['target','reflex'])))
    if not blind and 'sol' in names:
        parser.error('score Sol with a blind suite; develop Sol with the public training CLI')
    output = {'schema':2,'suite':args.suite}
    try:
        if blind:
            program, lock, manifest = benchlock.verify(args.sol_policy,args.freeze_lock,args.blind_manifest)
            cohorts = manifest['cohorts']
            seeds = cohorts[args.suite] if args.suite != 'both' else cohorts['holdout']+cohorts['generalization']
            output.update(blind_manifest_sha256=benchlock.raw_hash(args.blind_manifest),
                          freeze_lock_sha256=benchlock.raw_hash(args.freeze_lock),
                          cohorts={k:v for k,v in cohorts.items() if args.suite in ('both',k)})
        else:
            rng = Rng(args.seed_key,'benchmark-debug')
            seeds = list(dict.fromkeys((args.seeds or list(benchlock.STANDARD_DEBUG)) +
                         [rng.randint(-(1<<63),(1<<63)-1) for _ in range(args.random_seeds)]))
        config = Config(**load_data(args.config)[0]) if args.config else Config()
    except (ValueError, TypeError, KeyError, OSError) as e:
        parser.error(str(e))
    makers = {'target':reference_program,'reflex':lambda:Program(REFLEX),
              'no_persuasion':lambda:reference_program(persuasion=False),
              'no_phase_memory':lambda:reference_program(phase_memory=False)}
    if blind:
        makers['sol'] = lambda:program
    roster = {seat:makers[seat]() for seat in names} if not args.gates_only else {}
    metadata = {seat:{'sha256':p.sha256,'lane':LANE_ID,'live_compute_certified':True} for seat,p in roster.items()}
    if 'sol' in metadata:
        metadata['sol'].update(author=lock['author'],frozen_source_sha256=lock['source_sha256'])
    args.out.mkdir(parents=True,exist_ok=True)
    replays = args.out/'replays'
    replays.mkdir(exist_ok=True)
    root = Path(__file__).parent
    source_hashes = {p.name:benchlock.raw_hash(p) for p in sorted(root.glob('*.py'))}
    room_hashes = {p.name:benchlock.raw_hash(p) for p in sorted((root/'rooms').glob('*.py'))}
    output.update(runtime={'implementation':platform.python_implementation(),'version':platform.python_version(),
                  'lane':LANE_ID,'standard_fuel':STANDARD_FUEL,'room_entry_fuel':ENTRY_FUEL,
                  'sources':source_hashes,'room_templates':room_hashes},config=asdict(config),roster=metadata,seeds=seeds,per_seed=[])
    for seed in seeds:
        try:
            oracle, gate = evaluate_seed(seed,config)
        except (ValueError,KeyError,TypeError) as e:
            oracle = None
            tag = 'HIDDEN_MECHANIC_LEAK_OR_CONFLICT' if any(x in str(e) for x in ('transfer function','operation catalog')) else 'DESIGN_SCHEMA_REJECTED'
            gate = {'seed':seed,'zero_panic':False,'reproducible':False,'sampling_pass':False,'witness_error':str(e),
                    'invalid_design_defects':[{'tag':tag,'detail':str(e)}]}
        row = {'gate':gate,'results':{}}
        output['per_seed'].append(row)
        if oracle is not None:
            save_replay(replays,seed,'oracle',oracle)
        admitted = all(gate[k] for k in ('zero_panic','reproducible','sampling_pass')) and not gate['invalid_design_defects']
        if admitted:
            for name,p in roster.items():
                run, stats, timeline = score_run(seed,p,config,repeat_policy=blind or args.verify_policy_rerun)
                row['results'][name] = stats
                stats['execution_efficiency'] = min(1.,oracle.tick/run.tick) if stats['status']=='CAMP' else None
                stats['reasoning_operations_per_executed_action'] = stats['compute']['fuel']/max(1,sum(e['kind']=='INTERACT' for e in run.events))
                stats['replay'] = 'replays/'+save_replay(replays,seed,name,run,timeline).name
        print(f'seed={seed} admitted={admitted} '+ ' '.join(f"{k}:{v['completed']}/10" for k,v in row['results'].items()),flush=True)
    gates = [r['gate'] for r in output['per_seed']]
    output['validity'] = {key:sum(r[key] for r in gates)/len(gates) for key in ('zero_panic','reproducible','sampling_pass')}
    output['validity']['invalid_failure_count'] = sum(len(r['invalid_design_defects']) for r in gates)
    output['summary'] = summaries = {name:summarize([row['results'][name] for row in output['per_seed'] if name in row['results']]) for name in names}
    if blind:
        output['cohort_summary'] = {cohort:{name:summarize([row['results'][name] for row in output['per_seed']
            if row['gate']['seed'] in members and name in row['results']]) for name in names}
            for cohort,members in output['cohorts'].items()}
    target,sol = (summaries.get(n) for n in ('target','sol'))
    output['discrimination'] = {k:target[k]-sol[k] if target and sol and target[k] is not None and sol[k] is not None else None
        for k in ('mean_score','execution_efficiency','persuasion_accuracy','sanity_retained')}
    scored = [v for row in output['per_seed'] for v in row['results'].values()]
    output['all_contestant_replays_match'] = all(v['reproducible'] for v in scored)
    output['all_policy_reruns_match'] = bool(scored) and all(v['policy_rerun_matches'] for v in scored)
    output['acceptance_checks'], output['release_accepted'] = acceptance(output)
    if blind:
        output['cohort_acceptance'] = {k:acceptance(dict(output,summary=s,seeds=output['cohorts'][k]))[0]
                                       for k,s in output['cohort_summary'].items()}
        output['release_accepted'] &= all(all(c.values()) for c in output['cohort_acceptance'].values())
    (args.out/'report.json').write_text(json.dumps(output,ensure_ascii=False,indent=2),encoding='utf-8')
    scoreboard(output,args.out/'triage.md')
    print(json.dumps({'validity':output['validity'],'summary':summaries,'acceptance_checks':output['acceptance_checks'],
                      'release_accepted':output['release_accepted']},indent=2))
    good_design = output['validity']=={'zero_panic':1.,'reproducible':1.,'sampling_pass':1.,'invalid_failure_count':0}
    return int(not good_design or (args.require_acceptance and not output['release_accepted']))


def save_replay(traces,seed,name,run,timeline=None):
    path = traces/f'{seed}.{name}.json'
    path.write_text(json.dumps({'schema':1,'seed':seed,'config':asdict(run.config),'policy':name,
        'packets':run.decision_packets,'hashes':run.checkpoints,'events':run.events,'state_sha256':run.state_hash(),
        **({'policy_telemetry':timeline} if timeline is not None else {})},separators=(',',':')),encoding='utf-8')
    return path


if __name__ == '__main__':
    raise SystemExit(main())
