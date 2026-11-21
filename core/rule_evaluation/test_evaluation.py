"""Regressions for the evaluation contract (stdlib unittest)."""
import json
import os
import subprocess
import sys
import unittest
from copy import deepcopy

from .assemble import assemble
from .bridge import risk_samples
from .dsl import compound
from .fuel import Meter, PolicyVM, TrustedPython
from .gates import evaluate_seed
from .layout import compile_room
from .oracle import execute_witness, reproducible, resolve_witness_packet
from .physics import MAX_TICKS, WITNESS_TICKS, Rng, ray_box, ray_dir
from .solver import TargetSolver
from .world import Config, World

WAIT = {"type":"Wait"}


def use(target, action):
    return {"type":"Interact", "target_entity_id":target, "op_type":action}


def command(actor, action):
    return {"type":"CommandCompanion", "agent_id":actor, "action_spec":action}


def fixture(eid, pos, size, **kw):
    return {"id":eid,"label":eid,"kind":"test","pos":pos,"size":size,**kw}


def sandbox(targets=(), *, manual=None, stage=1, exit_when=None, **extra):
    raw = dict(title="Test chamber", start=[0,1500],size=[7000,9400], entities=[*targets,
        fixture("exit",[0,8700],[1800,2400,230])], room_rules=[],manuals=manual or {},
        exit_when=exit_when or ["false"], witness=[], **extra)
    return compile_room(raw, stage)


def to_room(seed, level):
    w = World(seed)
    w.observe()
    for room in w.rooms[:level-1]:
        for a in room["witness"]:
            w.step(resolve_witness_packet(w,a))
    if w.index != level-1: raise AssertionError(w.events[-5:])
    return w


class LockstepContract(unittest.TestCase):
    def test_delay_and_simultaneous_compound_order(self):
        w = World(4,rooms=[sandbox()])
        w.observe()
        move = {"type":"Move","dir_vec":[1,0],"duration_ticks":5,"delay_ticks":19}
        w.step([move,{"type":"RotateYaw","delta_angle":90,"delay_ticks":19},
                {"type":"RotateYaw","delta_angle":-15,"delay_ticks":19}])
        self.assertEqual((w.tick,w.actors[0].pos,w.actors[0].yaw),(20,[100,1500],75))
        w.step(WAIT)
        self.assertEqual((w.tick,w.actors[0].pos),(40,[500,1500]))
        self.assertEqual(len(w.physics_chain),32)

    def test_swept_ticks_never_pass_solid_masonry(self):
        w = World(0,rooms=[sandbox([fixture("wall",[0,3100],[4500,3200,200],solid=True)])])
        w.step({"type":"Move","dir_vec":[0,1],"duration_ticks":20})
        self.assertLessEqual(w.actors[0].pos[1], 2770)
        self.assertEqual(w.actors[0].contacts,["wall"])

    def test_open_portal_can_be_crossed_in_world_space(self):
        run = World(0,rooms=[sandbox(exit_when=["true"])])
        command = {"type":"Move","dir_vec":[0,1],"duration_ticks":20}
        for _ in range(4): run.step(command)
        self.assertEqual(run.status,"CAMP")
        self.assertTrue(any(e["kind"]=="PORTAL_THRESHOLD_CROSSED" for e in run.events))

    def test_assisted_portal_crossing_is_delayed_and_physical(self):
        run = World(0,rooms=[sandbox(exit_when=["true"])])
        walk = {"type":"Move","dir_vec":[0,1],"duration_ticks":20}
        for _ in range(3): run.step(walk)
        run.step(dict(use("exit","traverse"),delay_ticks=19))
        self.assertEqual(run.status,"RUNNING")
        self.assertEqual(run.actors[0].pos,[0,7600])
        self.assertFalse(any(e["kind"]=="PORTAL_THRESHOLD_CROSSED" for e in run.events))
        run.step(WAIT)
        self.assertEqual(run.status,"CAMP")
        self.assertTrue(any(e["kind"]=="PORTAL_THRESHOLD_CROSSED" for e in run.events))

    def test_only_clock_correctable_interlocks_are_phase_failures(self):
        clock = fixture("clock",[0,4200],[1400,1800,290],state={"active":0,"armed":0})
        run = World(0,rooms=[sandbox([clock],phases=[{"id":"clock","period":160,"offset":0,"window":70}])])
        run.states["clock"]["active"] = 0
        timed = ["and",["phase","clock"],["eq","clock","armed",1]]
        self.assertFalse(run.time_can_unlock(timed,0))
        run.states["clock"]["armed"] = 1
        self.assertTrue(run.time_can_unlock(timed,0))

    def test_checkpoint_records_hidden_noninteractive_clue(self):
        with self.assertRaisesRegex(ValueError, "ray-sampling"):
            sandbox(sampling_required=["wrong_id"])
        clue = fixture("reading",[0,4400],[1450,2850,200],dark=True)
        run = World(0,rooms=[sandbox([clue],exit_when=["true"],sampling_required=["reading"])])
        run.observe()
        move = {"type":"Move","dir_vec":[0,1],"duration_ticks":20}
        for _ in range(4): run.step(move)
        self.assertEqual(run.status,"CAMP")
        self.assertIn("reading",run.unseen_required[1])

    def test_timeout_at_exact_budget(self):
        w = World(0,rooms=[sandbox()])
        for i in range(MAX_TICKS//20): w.step(WAIT)
        self.assertEqual((w.tick,w.status,len(w.checkpoints)),(MAX_TICKS,"TIMEOUT",1800))
        with self.assertRaises(ValueError): w.step(WAIT)

    def test_state_and_replay_ignore_python_hash_seed(self):
        code = "from core.rule_evaluation.oracle import execute_witness; w,e=execute_witness(107); assert e is None; print(w.state_hash(),w.physics_chain.hex())"
        results = [subprocess.check_output([sys.executable,"-c",code],env={**os.environ,"PYTHONHASHSEED":n}) for n in ("3","888")]
        self.assertEqual(results[0],results[1])

    def test_seed_streams_are_independent_and_versioned(self):
        a,b,c = Rng(-5,"room"),Rng(-5,"room"),Rng(-5,"psych")
        values = [a.next() for _ in range(64)]
        self.assertEqual(values,[b.next() for _ in range(64)])
        self.assertNotEqual(values,[c.next() for _ in range(64)])


class ObservationIsolation(unittest.TestCase):
    def test_dark_first_hit_is_identical_to_out_of_range_and_occludes_beyond(self):
        screen = fixture("secret",[0,3400],[1750,3600,300],dark=True,state={"lethal":812})
        bright = fixture("success",[0,6500],[1100,2950,300],state={"active":1})
        w = World(0,rooms=[sandbox([screen,bright])]); o=w.observe()
        self.assertEqual(len(o["rays"]),27)
        self.assertEqual(o["rays"][13],"UNOBSERVABLE")
        self.assertNotIn("success",o["equipment"])
        self.assertNotIn("secret",json.dumps(o))
        self.assertNotIn("hazard",o)
        self.assertIsNone(ray_box((0,1560,1500),ray_dir(0,0),((-1,1),(1500,1600),(16000,16100))))

    def test_export_returns_value_objects_not_world_refs(self):
        w=World(3); before=w.observe(); expected=w.state_hash()
        before["manual"][0]["condition"]=["true"]
        before["self"]["pos"][0]=999999
        next(r for r in before["rays"] if isinstance(r,dict))["primitive_geometry"]["size"][0]=-5
        before["equipment"]["latch"]["operations"]["latch"]["effects"].clear()
        self.assertEqual(w.state_hash(),expected)
        self.assertGreater(w.entities["latch"]["size"][0],0)
        self.assertTrue(w.observe()["equipment"]["latch"]["operations"]["latch"]["effects"])

    def test_comparison_answer_not_in_public_switch_effects(self):
        w=to_room(2,2)
        expected=[o for e in w.room["entities"] for o in e.get("public_ops",{}).values()]
        self.assertEqual(len(expected),3)
        for op in expected:
            self.assertTrue(all(field=="selected" for _,field,_ in op["effects"]))

    def test_compiler_rejects_contradictory_transfer_function_and_cycles(self):
        valve=fixture("valve",[0,3000],[1300,1200,420],state={"open":0},ops={"turn":{"when":["true"],"effects":[["valve","open",1]]}},
                           public_ops={"turn":{"when":["true"],"effects":[["valve","open",0]]}})
        with self.assertRaisesRegex(ValueError,"contradicts"):
            sandbox([valve])
        valve.pop("public_ops")
        valve["light_when"]=["lit","valve"]
        with self.assertRaisesRegex(ValueError,"cyclic"):
            sandbox([valve])


class CrewAndFairHazards(unittest.TestCase):
    def test_rule_projection_observed_action_and_forgery(self):
        w=to_room(1,3); room=w.room
        for a in room["witness"][:2]: w.step(a)
        r=room["manuals"][1][0]["rule_id"]
        w.step(WAIT); w.step(WAIT)
        ev=w.observe()["evidence"][0]
        self.assertEqual(ev["action"]["op_type"],"throw")
        patch={"type":"PersuadeWithEvidence","agent_id":1,"rule_node_id":r,
               "proposed_ast_patch":{"mode":"EXEMPT_ACTION"}, "evidence_ref":ev["id"]}
        clone=deepcopy(w)
        clone.step(dict(patch,evidence_ref="E-forged"))
        self.assertGreater(clone.actors[1].panic,0)
        self.assertEqual(clone.last_result,"INVALID_EVIDENCE")
        w.step(patch)
        self.assertEqual(w.actors[1].panic,0)
        self.assertTrue(w.observe()["companions"][0]["declared_rules"][0]["exceptions"])
        self.assertTrue(reproducible(w))

    def test_coercion_draws_seeded_risk_and_does_not_broadcast_tampering(self):
        w=to_room(4,3)
        c={"type":"CoerceOverride","agent_id":1,"temp_action_spec":WAIT}
        report=w.observe()["companions"][0]["declared_rules"]
        for _ in range(28):
            if w.status != "RUNNING": break
            w.step(c)
        self.assertTrue(w.actors[1].tampered)
        self.assertEqual(w.declared[1],report)
        self.assertNotEqual(w.rules[1],report)
        self.assertLess(w.actors[1].sanity,10000)
        self.assertTrue(reproducible(w))

    def test_lit_warning_recovery_and_at_least_two_observation_intervals(self):
        for level in (4,10):
            w=to_room(1,level)
            trigger=None
            for a in w.room["witness"]:
                if level==4 and a.get("op_type")=="traverse":
                    trigger=("release","double_feed",1); break
                if level==10 and a.get("op_type")=="index":
                    trigger=("console","advance_against_stop",0); break
                w.step(resolve_witness_packet(w,a))
            self.assertIsNotNone(trigger)
            rows=risk_samples(w,level)
            self.assertEqual([name for name,_ in rows],["before-warning","warning","recovered"])
            self.assertTrue(rows[1][1]["observation"]["warning"])
            self.assertFalse(rows[-1][1]["observation"]["warning"])
            eid, op, actor=trigger
            while not w.test(w.entities[eid]["ops"][op]["when"],actor): w.step(WAIT)
            w.step(command(actor,use(eid,op)) if actor else use(eid,op))
            first=w.tick
            self.assertTrue(w.observe()["warning"])
            w.step(WAIT)
            self.assertEqual(w.status,"RUNNING")
            w.step(WAIT)
            self.assertEqual((w.tick-first,w.status),(40,"FAILED"))
            self.assertEqual(w.events[-1]["observable_ticks"],40)
            self.assertTrue(reproducible(w))

    def test_nonlethal_probe_response_and_replay(self):
        w=to_room(5,4)
        for a in w.room["witness"]:
            if a.get("target_entity_id")=="receiver" and a.get("op_type")=="arm": break
            w.step(resolve_witness_packet(w,a))
        o=w.step({"type":"DeployProbe","target_entity_id":"receiver"})
        self.assertEqual(o["probe_response"]["value"],65)
        self.assertFalse(o["warning"])
        self.assertEqual(w.states["receiver"]["charged"],1)  # probe never feeds the live reservoir
        self.assertTrue(reproducible(w))


class EvaluationContract(unittest.TestCase):
    def test_vm_assembler_resolves_labels_only(self):
        source='["jump","run"]\n["stop"]\nrun:\n["const",0,{"type":"Wait"}]\n["emit",0]'
        self.assertEqual(assemble(source)[0],["jump",2])
        self.assertEqual(PolicyVM(assemble(source))({},20).actions,compound(WAIT))
        with self.assertRaises(ValueError): assemble('["jump","missing"]')
        with self.assertRaises(ValueError): assemble('["copy",31,-1]')

    def test_anytime_preserves_latest_legal_candidate(self):
        vm=PolicyVM([["const",0,{"type":"RotateYaw","delta_angle":45}], ["emit",0],
                     ["const",0,{"type":"Move","duration_ticks":0}], ["emit",0], ["jump",4]])
        d=vm({},50)
        self.assertTrue(d.exhausted)
        self.assertEqual(d.candidates,1)
        self.assertEqual(d.actions,compound({"type":"RotateYaw","delta_angle":45}))
        self.assertEqual(PolicyVM([["jump",0]])({},5).actions,compound(WAIT))

    def test_trusted_reference_fuel_interrupts_reentrant_python(self):
        class Loops:
            def decide(self, o, publish):
                publish({"type":"RotateYaw","delta_angle":12})
                while True:
                    x=4
        d=TrustedPython(Loops())({},1500)
        self.assertTrue(d.exhausted)
        self.assertEqual(d.candidates,1)
        self.assertEqual(d.actions[0]["delta_angle"],12)
        self.assertIsNone(sys.gettrace())

    def test_witness_sets_and_biases(self):
        for i in (1,2,7,42):
            w,r=evaluate_seed(i)
            self.assertTrue(r["zero_panic"],r["witness_error"])
            self.assertTrue(r["reproducible"])
            self.assertEqual(r["invalid_design_defects"],[])
            self.assertEqual(set(r["live_counterexamples"]),set(range(3,11)))
            self.assertEqual(sum(e["kind"]=="PORTAL_THRESHOLD_CROSSED" for e in w.events),10)
            self.assertLessEqual(w.tick,WITNESS_TICKS)
            self.assertEqual([e["room"] for e in w.events if e["kind"]=="JOIN"],[3,7])
        for bias in (-20,40):
            _,g=evaluate_seed(41,Config(phase_window_bias=bias))
            self.assertTrue(g["zero_panic"] and g["sampling_pass"],g)

    def test_target_from_blackbox_only(self):
        w=World(-17); policy=TrustedPython(TargetSolver()); o=w.observe()
        for _ in range(430):
            if w.status!="RUNNING": break
            o=w.step(policy(o,60_000).actions)
        self.assertEqual(w.status,"CAMP",w.events[-12:])
        self.assertTrue(all(a.panic==0 and a.sanity==10000 for a in w.actors))


if __name__ == "__main__":
    unittest.main()
