"""Referee-only attribution; decision samples and evidence never enter contestant packets."""
from collections import Counter, defaultdict
from pathlib import Path

from .physics import digest, TELEGRAPH_TICKS

GROUPS = {
    'VM_FUEL_CAP_HIT': 'compute', 'POLICY_RUNTIME_FAULT': 'policy/interface',
    'ACTION_SCHEMA_REJECTED': 'policy/interface', 'INTERACTION_CONTRACT_MISMATCH': 'policy/interface',
    'NO_PROGRESS_LOOP': 'stalled (inspect replay)', 'NO_EFFECTIVE_ACTION': 'stalled (inspect replay)',
    'WRONG_TARGET_SELECTED': 'geometry/selection', 'EVIDENCE_IMMATURE': 'rules/time',
    'RULE_DEADLOCK_STALL': 'rules/team', 'HAZARD_IGNORED': 'hazard response',
    'HAZARD_RESPONSE_FAILED': 'hazard response', 'TEMPORAL_PHASE_ERROR': 'rules/time',
    'PSYCH_RISK_COLLAPSE': 'rules/team', 'ACTIVE_SENSING_DEFICIT': 'perception/coverage',
    'UNTELEGRAPHED_DEATH': 'design defect', 'UNRESOLVED_PLANNING_FAILURE': 'insufficient evidence',
}


def underlying(a):
    return a.get('action_spec', a.get('temp_action_spec', a))


def sample(world, observation, decision):
    nonperiodic = {k:v for k,v in world.states.items() if k not in {p['id'] for p in world.room['phases']}}
    return dict(tick=world.tick, room=world.index+1, warning=observation['warning'], result=world.last_result,
                exhaust=decision.exhausted, candidates=decision.candidates, fuel=decision.fuel,
                line=decision.fuel_line, fault=decision.fault, rejected=decision.rejected, actions=decision.actions,
                signature=digest([[(a.pos,a.yaw,a.pose,a.carry) for a in world.actors], nonperiodic,
                                  [sorted(s) for s in world.seen], len(world.accepted_patches)]))


def anchors(items, limit=6):
    return items if len(items) <= limit else [*items[:limit//2], *items[-(limit//2):]]


def loop_evidence(samples):
    # Compare exact small endpoint cycles. Passive time windows do not enter the signature.
    # Pure waits and actual phase-interlock retries get their own classifications.
    keys = [(s['signature'], digest(s['actions']), s['result']) for s in samples]
    for period in range(1, 17):
        length = period * max(4, (12+period-1)//period)
        tail = keys[-length:]
        if len(tail) != length or any(a != b for a,b in zip(tail, tail[period:])):
            continue
        window = samples[-length:]
        if not any(underlying(a)['type'] != 'Wait' for s in window for a in s['actions']):
            continue
        if any(s['result'] == 'PHASE_INTERLOCK' for s in window):
            continue
        return dict(from_tick=window[0]['tick'], to_tick=window[-1]['tick'], cycle_steps=period,
                    repeats=length//period, actions=[s['actions'] for s in window[:period]])
    return None


def wrong_bay(room, events):
    if room['index'] != 2:
        return None
    by_id = {e['id']:e for e in room['entities']}
    master = by_id['master_arm']['y']
    selected = [e for e in events if e['kind'] == 'INTERACT' and e.get('action',{}).get('op_type') == 'reject']
    if not selected:
        return None
    last = selected[-1]
    eid = last['action']['target_entity_id']
    arm = by_id.get(eid+'_arm')
    if arm and arm['y'] == master:
        return dict(selected=eid, selected_arm_mm=arm['y'], master_arm_mm=master, tick=last['tick'],
                    rejected_same_bay=sum(e['action']['target_entity_id']==eid for e in selected))
    return None


def diagnose(world, decisions):
    if world.status == 'CAMP':
        return []
    room = world.index+1
    rows = [e for e in world.events if e['room'] == room]
    tail = [d for d in decisions if d['room'] == room]
    kinds = defaultdict(list)
    for e in rows:
        kinds[e['kind']].append(e)
    found = []

    def add(tag, **evidence):
        found.append(dict(tag=tag, group=GROUPS[tag], evidence=evidence))

    if kinds['HAZARD_DEATH']:
        fatal = kinds['HAZARD_DEATH'][-1]
        if fatal.get('observable_ticks',0) < TELEGRAPH_TICKS:
            add('UNTELEGRAPHED_DEATH', event=fatal)
        after_clear = kinds['HAZARD_CLEARED'][-1]['tick'] if kinds['HAZARD_CLEARED'] else -1
        warned = [d for d in tail if after_clear < d['tick'] <= fatal['tick'] and d['warning']]
        if warned:
            recovery = world.room.get('hazard_exercise',{}).get('recover')
            tried = [d for d in warned if any([underlying(a).get('target_entity_id'), underlying(a).get('op_type')] == recovery
                                              for a in d['actions'])]
            add('HAZARD_RESPONSE_FAILED' if tried else 'HAZARD_IGNORED', first_seen_tick=warned[0]['tick'],
                warning_decisions=len(warned), fatal=fatal, recovery=recovery,
                submitted=[{'tick':d['tick'],'actions':d['actions']} for d in anchors(warned)])
    if kinds['PSYCH_RISK_COLLAPSE'] or (len(kinds['REBELLION'])+len(kinds['INTERFERENCE'])) > 1:
        add('PSYCH_RISK_COLLAPSE', events=anchors([e for e in rows if e['kind'] in ('PSYCH_RISK_COLLAPSE','REBELLION','INTERFERENCE')]))
    hit_caps = [d for d in tail if d['exhaust']]
    if hit_caps:
        add('VM_FUEL_CAP_HIT', count=len(hit_caps), no_candidate=sum(not d['candidates'] for d in hit_caps),
            decisions=[{k:d[k] for k in ('tick','line','fuel','candidates')} for d in anchors(hit_caps)])
    faults = [d for d in tail if d['fault']]
    if faults:
        add('POLICY_RUNTIME_FAULT', count=len(faults), decisions=[{'tick':d['tick'], **d['fault']} for d in anchors(faults)])
    rejected = [d for d in tail if d['rejected']]
    if rejected:
        add('ACTION_SCHEMA_REJECTED', count=sum(d['rejected'] for d in rejected),
            decisions=[{k:d[k] for k in ('tick','rejected','candidates')} for d in anchors(rejected)])
    bay = wrong_bay(world.room,rows)
    if bay:
        add('WRONG_TARGET_SELECTED',**bay)
    last_patch = {(e['actor'], e['rule']):e['tick'] for e in kinds['PERSUADED']}
    immature = [e for e in kinds['EVIDENCE_REJECTED'] if e.get('reason')=='immature' and
                e['tick'] > last_patch.get((e['actor'],e['rule']), -1)]
    if immature:
        add('EVIDENCE_IMMATURE', count=len(immature), events=anchors(immature))
    # Re-test the original action at the final state. Historical standoffs may have
    # been resolved by moving a blocker or changing the room rather than persuading.
    unresolved = [e for e in kinds['RULE_STANDOFF'] if world.blocked(e['actor'],e['action'])]
    if unresolved and (len(unresolved) >= 2 or world.tick-unresolved[-1]['tick'] < 120 or world.breakers):
        add('RULE_DEADLOCK_STALL', count=len(unresolved), events=anchors(unresolved),
            current_rules=world.blocked(unresolved[-1]['actor'],unresolved[-1]['action']))
    if len(kinds['PHASE_INTERLOCK']) >= 2:
        add('TEMPORAL_PHASE_ERROR', count=len(kinds['PHASE_INTERLOCK']), events=anchors(kinds['PHASE_INTERLOCK']))
    rejects = sorted(kinds['UNKNOWN_OPERATION']+kinds['OUT_OF_REACH'], key=lambda e:e['tick'])
    if len(rejects) >= 3 and len([d for d in tail if d['tick'] >= rejects[-1]['tick']]) <= 16:
        add('INTERACTION_CONTRACT_MISMATCH', count=len(rejects), events=anchors(rejects),
            note='Check target selection, facing and reach against the public contract and footage.')
    loop = loop_evidence(tail)
    if loop:
        add('NO_PROGRESS_LOOP', **loop)
    elif len(tail) >= 12 and all(all(a['type']=='Wait' for a in d['actions']) for d in tail[-12:]):
        add('NO_EFFECTIVE_ACTION', from_tick=tail[-12]['tick'], to_tick=tail[-1]['tick'])
    queried = {eid for frame in world.query_frames.values() for eid in frame['seen']}
    missing = sorted(world.required_targets() - world.seen[0] - queried)
    if missing and world.status == 'TIMEOUT':
        add('ACTIVE_SENSING_DEFICIT', unseen_targets=missing)
    if not found:
        add('UNRESOLVED_PLANNING_FAILURE', last_result=world.last_result)
    return found


def scoreboard(output, path: Path):
    rows = ['# Rule evaluation — failure triage', '',
            f"Suite: `{output['suite']}` · Lane: `{output['runtime']['lane']}` · Release accepted: **{output['release_accepted']}**", '',
            'Counts below are per seed and may overlap. Groups describe observed symptoms; compare the linked replay before blaming an interface or a puzzle.',
            '', '| Seat | Clears | Passed first 3 | Reached R5+ | Mean depth |', '|---|---:|---:|---:|---:|']
    for seat, s in output['summary'].items():
        if s:
            rows.append(f"| {seat} | {s['clear_rate']:.0%} | {s['first_three_rate']:.0%} | {s['reached_midgame_rate']:.0%} | {s['mean_depth']:.2f} |")
    rows += ['', '| Seat | Room | Group | Tag | Seeds | Example replay / tick |', '|---|---:|---|---|---:|---|']
    table = defaultdict(list)
    for r in output['per_seed']:
        for seat, result in r['results'].items():
            for d in result['failure_diagnostics']:
                table[(seat,result['completed']+1,d['group'],d['tag'])].append((result['replay'],d['evidence']))
    for (seat,room,group,tag), items in sorted(table.items()):
        replay, ev = items[0]
        tick = ev.get('tick',ev.get('first_seen_tick',ev.get('from_tick','—')))
        if tick == '—':
            samples = ev.get('events',ev.get('decisions',[]))
            if samples:
                tick = samples[0].get('tick','—')
        rows.append(f'| {seat} | {room} | {group} | `{tag}` | {len(items)} | [record]({replay}) / {tick} |')
    path.write_text('\n'.join(rows)+'\n', encoding='utf-8')
