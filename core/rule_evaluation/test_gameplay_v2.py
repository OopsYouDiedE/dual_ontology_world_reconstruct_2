"""Gameplay v2 admission, cross-manual proofs, and warning regressions."""
from copy import deepcopy
from unittest import TestCase

from .gates import evaluate_seed, hazard_checkpoint, run_hazard_exercise
from .layout import CAMPAIGN_MAX_TICKS
from .oracle import execute_witness, resolve_witness_packet
from .physics import DECISION_TICKS, TELEGRAPH_TICKS
from .world import World


WAIT = {"type": "Wait"}


def room_five_after_demo():
    world = World(1)
    world.observe()
    while world.index < 4:
        current = world.index
        for row in world.room["witness"]:
            world.step(resolve_witness_packet(world, row))
            if world.index != current:
                break
    for row in world.room["witness"][:2]:
        world.step(row)
    return world


def attempt(ref):
    return {"type": "PersuadeWithEvidence", "agent_id": 1,
            "rule_node_id": "shuttle_never_shift_loaded", "evidence_ref": ref,
            "proposed_ast_patch": {"mode": "EXEMPT_ACTION"}}


class GameplayV2(TestCase):
    def test_admission_certifies_all_live_handoffs_and_hazards(self):
        world, report = evaluate_seed(1)
        self.assertIsNone(report["witness_error"])
        self.assertEqual(report["invalid_design_defects"], [])
        self.assertTrue(report["reproducible"])
        self.assertTrue(0.30 <= report["witness_budget_ratio"] <= 0.45)
        self.assertEqual(set(report["cross_manual_handoffs"]), set(range(5, 10)))
        for rows in report["cross_manual_handoffs"].values():
            for handoff in rows.values():
                self.assertTrue(handoff["lead_blocked_live"])
                self.assertTrue(handoff["operator_blocked_without_patch"])
                self.assertTrue(handoff["evidence_ref"].startswith("E"))
        proofs = [p for p in world.accepted_patches if "deduction" in p]
        self.assertEqual(len(proofs), 6)
        for proof in proofs:
            self.assertTrue(proof["deduction"]["observed_changes"])
        for level in range(5, 10):
            result = report["hazard_exercises"][level]
            self.assertTrue(result["warning_visible"] and result["recoverable"])
            self.assertGreaterEqual(result["observed_warning_ticks"], TELEGRAPH_TICKS)

    def test_hazard_branches_change_mechanisms_and_restore_them(self):
        fields = {5: ("shuttle", "docked"), 7: ("counterweight", "raised"),
                  8: ("right_link", "extended"), 9: ("mask", "raised")}
        reached = []

        def probe(world, packet):
            level = world.index + 1
            if not 5 <= level <= 9 or not (spec := hazard_checkpoint(world, packet)):
                return
            before, warning, recovery = run_hazard_exercise(world, spec)
            reached.append(level)
            if level in fields:
                entity, field = fields[level]
                self.assertEqual([x.states[entity][field] for x in (before, warning, recovery)], [1, 0, 1])
            else:
                self.assertFalse(warning.test(warning.entities["handle"]["ops"]["retract"]["when"], 1))
                self.assertTrue(recovery.test(recovery.entities["handle"]["ops"]["retract"]["when"], 1))

        _, error = execute_witness(1, check_before=probe)
        self.assertIsNone(error)
        self.assertEqual(reached, list(range(5, 10)))

    def test_pending_evidence_retry_and_forgery_have_distinct_telemetry(self):
        world = room_five_after_demo()
        obs = world.observe()
        self.assertEqual(obs["evidence"], [])
        row, = obs["evidence_pending"]
        forged = deepcopy(world)
        forged.step(attempt("forged"))
        event = next(e for e in reversed(forged.events) if e["kind"] == "EVIDENCE_REJECTED")
        self.assertEqual(event["reference_status"], {"forged": "unknown_reference"})
        obs = world.step(attempt(row["id"]))
        self.assertEqual(obs["last_result"], "EVIDENCE_IMMATURE")
        self.assertEqual(world.actors[1].panic, 0)
        self.assertEqual(world.tick, row["ready_tick"])
        event = next(e for e in reversed(world.events) if e["kind"] == "EVIDENCE_REJECTED")
        self.assertEqual(event["reference_status"], {row["id"]: "immature"})
        self.assertEqual(event["reason"], "immature")
        unqueried = deepcopy(world)
        unqueried.step(attempt(row["id"]))
        self.assertEqual(next(e for e in reversed(unqueried.events) if e["kind"] == "EVIDENCE_REJECTED")["reason"],
                         "manual_not_queried")
        world.step({"type": "QueryCompanion", "agent_id": 1})
        self.assertEqual(world.step(attempt(row["id"]))["last_result"], "PERSUADED")
        rule = next(r for r in world.rules[1] if r["rule_id"] == attempt(row["id"])["rule_node_id"])
        self.assertEqual(rule["exceptions"][0]["when"], world.room["handoffs"][rule["rule_id"]]["live"])

    def test_gantry_can_eliminate_the_off_phase_case_without_running_a_dry_stroke(self):
        world = World(1)
        world.observe()
        while world.index < 7:
            room = world.index
            for packet in world.room["witness"]:
                world.step(resolve_witness_packet(world,packet))
                if world.index != room:
                    break
        rows = world.room["witness"]
        for packet in rows[:9]:
            world.step(WAIT if packet["type"] in {"Interact","PersuadeWithEvidence"} else packet)
        docs, = world.observe()["logic_proofs"]
        self.assertEqual(world.observe()["evidence"],[])
        proof = {"type":"PersuadeWithEvidence","agent_id":docs["agent_id"],"rule_node_id":docs["rule_node_id"],
                 "evidence_ref":docs["evidence_ref"],"proposed_ast_patch":{"mode":docs["mode"]}}
        forged = deepcopy(world)
        forged.step(dict(proof,evidence_ref=proof["evidence_ref"][:-1]))
        self.assertEqual(forged.last_result,"INVALID_EVIDENCE")
        world.step(proof)
        self.assertEqual(world.last_result,"PERSUADED")
        self.assertEqual(world.accepted_patches[-1]["deduction"]["kind"],"DOCUMENT_ENTAILMENT")
        self.assertEqual(world.actors[2].panic,0)
        mesh_at = next(i for i,p in enumerate(rows) if p.get("action_spec",{}).get("op_type")=="mesh")
        for packet in rows[9:mesh_at]: world.step(packet)
        for _ in range(64):
            if world.test(docs["window"]): break
            world.step(WAIT)
        else: self.fail("joint phase never became active")
        world.step(rows[mesh_at])
        self.assertEqual(world.last_result,"OK")
        transfer_at = next(i for i,p in enumerate(rows) if p.get("op_type")=="transfer")
        for _ in range(64):
            if world.test(docs["window"]): break
            world.step(WAIT)
        for packet in rows[transfer_at:]: world.step(packet)
        self.assertEqual(world.index,8)
        self.assertEqual(world.actors[2].panic,0)
        self.assertFalse(any(e["room"]==8 and e["kind"]=="INTERACT" and e["actor"]==0 and
                             e["action"].get("op_type")=="mesh" for e in world.events))

    def test_exact_campaign_deadline(self):
        world = World(1)
        for _ in range(CAMPAIGN_MAX_TICKS // DECISION_TICKS):
            world.step(WAIT)
        self.assertEqual((world.tick, world.status), (CAMPAIGN_MAX_TICKS, "TIMEOUT"))
        self.assertEqual(len(world.checkpoints), CAMPAIGN_MAX_TICKS // DECISION_TICKS)
