"""Regression suite for policy parity, sealing, and each requested failure tag."""
import json
import os
from pathlib import Path
from subprocess import check_output
import sys
from tempfile import TemporaryDirectory
from unittest import TestCase

from .batch import policy_chain, sample
from .benchlock import draw, seal, verify
from .diagnostics import diagnose, loop_evidence
from .dsl import compound
from .fuel import Decision
from .gates import hazard_checkpoint, run_hazard_exercise
from .oracle import execute_witness, resolve_witness_packet
from .policies import REFLEX, reference_program
from .sandbox import PolicyFault, Program
from .test_gameplay_v2 import attempt, room_five_after_demo
from .world import World

WAIT = {'type':'Wait'}


def move(x,z,t):
    return {'type':'Move','dir_vec':[x,z],'duration_ticks':t}


def op(target,verb):
    return {'type':'Interact','target_entity_id':target,'op_type':verb}


def failure_tags(w, steps):
    return {d['tag']:d['evidence'] for d in diagnose(w,steps)}


def append(w, packet, log, **telemetry):
    decision = Decision(compound(packet),fuel=0,candidates=1,exhausted=False,**telemetry)
    log.append(sample(w,w.observe(),decision))
    w.step(packet)


def to_room(room):
    w = World(1)
    w.observe()
    while w.index < room - 1:
        index = w.index
        for p in w.room['witness']:
            w.step(resolve_witness_packet(w,p))
            if w.index != index:
                break
    return w


class CommonLane(TestCase):
    def test_candidate_is_preserved_but_failed_state_is_not(self):
        program = Program('''\
def decide(o, state):
    if o['work']:
        state['count'] = 9
        emit({'type':'RotateYaw','delta_angle':30})
        emit({'type':'unknown'})
        while True:
            pass
    return {'type':'RotateYaw','delta_angle':state.get('count',0)}
''')
        lane = program.start()
        run = lane({'work':True},450)
        self.assertEqual(run.actions[0]['delta_angle'],30)
        self.assertEqual((run.fuel,run.exhausted,run.rejected,run.candidates),(450,True,1,1))
        self.assertGreater(run.fuel_line,0)
        self.assertEqual(lane({'work':False},450).actions[0]['delta_angle'],0)
        self.assertEqual(program.start()({'work':False},450).actions[0]['delta_angle'],0)
        self.assertEqual(Program('def decide(o,s):\n    while True: pass\n').start()({},80).actions,compound(WAIT))

    def test_policy_compiler_blocks_privileged_or_unbounded_operations(self):
        for body in ('import os','open("x")','o.__class__','state.get.__self__',
                     'eval("1")','[v for v in ().__class__]','state.get(**o)','__iterate(o)'):
            with self.subTest(body=body), self.assertRaises(PolicyFault):
                Program('def decide(o,state):\n    '+body+'\n')
        for body in ('"%1000000s" % "a"','"a" * 1000000','10 ** 100000','o["list"].append(o["list"])\n    state["loop"] = o["list"]'):
            with self.subTest(body=body):
                d = Program('def decide(o,state):\n    '+body+'\n').start()({'list':[]},10000)
                self.assertIsNotNone(d.fault)
                self.assertEqual(d.actions,compound(WAIT))

    def test_position_and_policy_results_are_deterministic_across_hash_randomization(self):
        body = '''\
def decide(o,state):
    a, b = {'north','south'}
    pairs = [{'gamma','alpha'},{'theta','beta'}]
    for x,y in pairs:
        state[x] = y
    return {'type':'RotateYaw','delta_angle':len(a)+len(list(state)[0])}
'''
        code = ('import json; from core.rule_evaluation.sandbox import Program; '
                f'print(json.dumps(Program({body!r}).start()({{}},10000).__dict__,sort_keys=True))')
        results = [check_output([sys.executable,'-c',code],env={**os.environ,'PYTHONHASHSEED':n}) for n in ('7','171')]
        self.assertEqual(results[0],results[1])
        self.assertIsNone(json.loads(results[0])['fault'])

    def test_reference_and_all_ablations_compile_in_same_lane(self):
        src = (reference_program(),reference_program(persuasion=False),
               reference_program(phase_memory=False),Program(REFLEX))
        self.assertEqual({type(p.start()) for p in src},{type(src[0].start())})
        self.assertEqual(len({p.sha256 for p in src}),len(src))
        obs = World(1).observe()
        for p in src:
            d = p.start()(obs,60_000)
            self.assertTrue(d.actions)
            self.assertIsNone(d.fault)

    def test_freeze_separates_training_and_rejects_changed_source(self):
        # Temp files must stay under the repository workspace.
        Path('.runtime').mkdir(exist_ok=True)
        with TemporaryDirectory(dir='.runtime') as folder:
            root = Path(folder)
            source, ident, lock, cohorts = (root/n for n in ('source','author','lock','cohorts'))
            text = 'def decide(o,state):\n    return WAIT\n'
            source.write_bytes(text.encode())
            ident.write_text(json.dumps({'model':'gpt-6.2-sol','revision':'test','provenance':'test',
                                        'ability_profile':'test'}),encoding='utf-8')
            frozen = seal(source,ident,lock)
            result = draw(lock,cohorts,8,8)
            self.assertFalse(set(result['holdout']) & (set(frozen['training']) | set(result['generalization'])))
            source.write_bytes(text.replace('\n','\r\n').encode())
            verify(source,lock,cohorts)
            source.write_bytes((text+'\n').encode())
            with self.assertRaisesRegex(ValueError,'mismatches freeze'):
                verify(source,lock,cohorts)


class Attribution(TestCase):
    def test_fuel_cap_point_and_loop_not_confused_with_one_wait(self):
        w = World(1)
        policy = Program('def decide(o,s):\n    while True: pass').start()
        d = policy(w.observe(),200)
        steps = [sample(w,w.observe(),d)]
        w.step(d.actions)
        self.assertEqual(failure_tags(w,steps)['VM_FUEL_CAP_HIT']['no_candidate'],1)
        rows = []
        for _ in range(16):
            append(w,{'type':'RotateYaw','delta_angle':0},rows)
        self.assertEqual(failure_tags(w,rows)['NO_PROGRESS_LOOP']['cycle_steps'],1)
        idle = []
        for _ in range(16):
            append(w,WAIT,idle)
        self.assertIsNone(loop_evidence(idle))
        self.assertNotEqual(policy_chain(rows),policy_chain(idle))

    def test_wrong_bay_is_a_successful_wrong_selection_not_a_missed_press(self):
        w = to_room(2)
        rows = []
        # Approach a physically reachable concordant bay, then actually select it.
        by_id = {e['id']:e for e in w.room['entities']}
        bay = next(f'bay_{i}' for i in range(1,4) if by_id[f'bay_{i}_arm']['y']==by_id['master_arm']['y'])
        x = by_id[bay]['pos'][0]
        append(w,move(0,1,10),rows)
        n = abs(x)//100
        for ticks in (min(20,n),max(0,n-20)):
            if ticks:
                append(w,move(1 if x>0 else -1,0,ticks),rows)
        append(w,op(bay,'reject'),rows)
        self.assertEqual(w.last_result,'OK')
        self.assertEqual(failure_tags(w,rows)['WRONG_TARGET_SELECTED']['selected'],bay)

    def test_immature_and_deadlock_are_distinct(self):
        w = room_five_after_demo()
        pending, = w.observe()['evidence_pending']
        rows = []
        append(w,attempt(pending['id']),rows)
        self.assertIn('EVIDENCE_IMMATURE',failure_tags(w,rows))
        room = to_room(3)
        rows = []
        cmd = {'type':'CommandCompanion','agent_id':1,'action_spec':op('bolt','throw')}
        append(room,cmd,rows)
        append(room,cmd,rows)
        self.assertIn('RULE_DEADLOCK_STALL',failure_tags(room,rows))

    def test_unanswered_visible_warning_differs_from_attempted_recovery(self):
        starts = []

        def capture(world,packet):
            if world.index==4 and (exercise := hazard_checkpoint(world,packet)):
                starts.append(run_hazard_exercise(world,exercise)[1])

        execute_witness(1,check_before=capture)
        warned, = starts
        rows = []
        while warned.status == 'RUNNING':
            append(warned,WAIT,rows)
        ignored = failure_tags(warned,rows)['HAZARD_IGNORED']
        self.assertGreaterEqual(ignored['fatal']['observable_ticks'],40)
        self.assertLessEqual(ignored['first_seen_tick'],ignored['fatal']['tick']-40)
