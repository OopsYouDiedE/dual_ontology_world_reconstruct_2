"""Project-local unit tests for evaluation boundaries; no acceptance scores."""
from __future__ import annotations

import base64
import hashlib
import json
import os
import subprocess
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import psutil

import common as c
import server


class ProjectFixture(unittest.TestCase):
    def setUp(self):
        c.assert_project()
        parent = c.project_path(c.ROOT / ".runtime/evaluation-tests")
        parent.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=parent)
        self.directory = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)


class WorkerLaunchTests(ProjectFixture):
    def test_actual_worker_pid_matches_python_runtime(self):
        command = [sys.executable, "-c", "import time; time.sleep(15)"]
        process = subprocess.Popen(command, cwd=c.ROOT)
        identity = None
        try:
            identity = server.worker_identity(process, command[1:])
            actual = psutil.Process(identity["pid"])
            self.assertEqual(Path(actual.exe()).resolve(), Path(identity["executable"]).resolve())
            if os.name == "nt":
                self.assertEqual(Path(actual.exe()).resolve(), Path(sys._base_executable).resolve())
        finally:
            if identity:
                try:
                    psutil.Process(identity["pid"]).terminate()
                except psutil.NoSuchProcess:
                    pass
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=5)


class BudgetTests(ProjectFixture):
    def setUp(self):
        super().setUp()
        self.window = c.documented_goal()
        patcher = patch.object(c, "STATE", self.directory / "state")
        patcher.start()
        self.addCleanup(patcher.stop)
        clock = patch.object(server.time, "time", return_value=self.window["started_epoch"] + 3600)
        clock.start()
        self.addCleanup(clock.stop)

    def test_documented_window_is_timezone_aware_and_bounded(self):
        self.assertEqual(self.window["deadline_epoch"] - self.window["started_epoch"], 28800)
        for text in ("", "本 Goal 创建时间：2026-11-16 10:51:07。既定熔断检查时间为 2026-11-16 18:51:07。",
                     "本 Goal 创建时间：2026-11-16 10:51:07 +08:00。既定熔断检查时间为 2026-11-16 20:51:07 +08:00。",
                     "本 Goal 创建时间：2026-11-16 10:51:07 +08:00。既定熔断检查时间为 2026-11-16 09:51:07 +08:00。"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                c.parse_goal_window(text)

    def test_missing_receipt_inherits_document_not_now(self):
        goal, remaining = server._goal()
        self.assertEqual(goal["started_epoch"], self.window["started_epoch"])
        self.assertEqual(goal["deadline_epoch"], self.window["deadline_epoch"])
        self.assertEqual(remaining, 7 * 3600)

    def test_existing_earlier_start_cannot_be_extended(self):
        earlier = self.window["started_epoch"] - 120
        c.write_json(c.STATE / "active-goal.json", {"schema_version": 1, "project_root": str(c.ROOT),
                     "started_epoch": earlier, "deadline_epoch": self.window["deadline_epoch"] + 3600})
        goal, _ = server._goal()
        self.assertEqual(goal["started_epoch"], earlier)
        self.assertEqual(goal["deadline_epoch"], earlier + 8 * 3600)

    def test_later_receipt_is_clamped_to_documented_window(self):
        c.write_json(c.STATE / "active-goal.json", {"schema_version": 1, "project_root": str(c.ROOT),
                     "started_epoch": self.window["started_epoch"] + 3600,
                     "deadline_epoch": self.window["deadline_epoch"] + 3600})
        goal, _ = server._goal()
        self.assertEqual(goal["started_epoch"], self.window["started_epoch"])
        self.assertEqual(goal["deadline_epoch"], self.window["deadline_epoch"])

    def test_expired_goal_refuses_start(self):
        with patch.object(server.time, "time", return_value=self.window["deadline_epoch"] + 1):
            with self.assertRaisesRegex(RuntimeError, "limit reached"):
                server._goal()

    def test_malformed_or_wrong_project_receipt_fails_closed(self):
        for record in ({"schema_version": 1, "project_root": str(self.directory), "started_epoch": 1, "deadline_epoch": 2},
                       {"schema_version": 1, "project_root": str(c.ROOT), "started_epoch": 2, "deadline_epoch": 1}):
            c.write_json(c.STATE / "active-goal.json", record)
            with self.assertRaises(ValueError):
                server._goal()


class ProvenanceTests(ProjectFixture):
    def test_only_this_checkout_and_project_paths(self):
        self.assertEqual(c.assert_project(), c.ROOT)
        with self.assertRaises(ValueError):
            c.assert_project(self.directory)
        with self.assertRaises(ValueError):
            c.project_path(c.ROOT.parent / "__forbidden_output__")
        self.assertTrue(c.project_path(self.directory).is_relative_to(c.ROOT))

    def test_snapshot_payload_hash_and_project(self):
        raw = b"synthetic test payload only"
        good = {"format": "story-checkpoint-v1", "project": c.ROOT.name,
                "payload": base64.b64encode(raw).decode(), "sha256": hashlib.sha256(raw).hexdigest(), "host_pid": 1}
        path = self.directory / "snapshot.json"
        c.write_json(path, good)
        self.assertEqual(c.validate_snapshot(path)["sha256"], good["sha256"])
        for changed in (dict(good, project="other"), dict(good, sha256="0" * 64), dict(good, host_pid=0)):
            c.write_json(path, changed)
            with self.assertRaises(ValueError):
                c.validate_snapshot(path)

    def test_fixture_image_never_becomes_acceptance_evidence(self):
        image = self.directory / "synthetic.png"
        image.write_bytes(b"test bytes, not gameplay pixels")
        identity = dict(c.provenance.project_identity(c.ROOT), process_id=os.getpid(),
                        executable_path=str(Path(sys.executable).resolve()))
        c.write_json(str(image) + ".json", {"source_identity": identity,
                     "image_sha256": hashlib.sha256(image.read_bytes()).hexdigest(), "acceptance_eligible": False})
        with self.assertRaises(ValueError):
            c.provenance.verify_image(image, c.ROOT)
        self.assertTrue(c.provenance.verify_image(image, c.ROOT, allow_fixture=True)["provenance_valid"])
        image.write_bytes(b"tampered")
        with self.assertRaises(ValueError):
            c.provenance.verify_image(image, c.ROOT, allow_fixture=True)

    def test_real_process_identity_and_pid_reuse_guard(self):
        import psutil
        process = psutil.Process(os.getpid())
        observed = c.inspect_process(os.getpid(), expected_exe=process.exe(), created=process.create_time())
        self.assertEqual(observed["pid"], os.getpid())
        with self.assertRaises(ValueError):
            c.inspect_process(os.getpid(), expected_exe=process.exe(), created=process.create_time() - 10)
        with self.assertRaises(ValueError):
            c.inspect_process(os.getpid(), expected_exe=process.exe(), required=["__not_this_command__"])


class ProfileTests(ProjectFixture):
    def test_focused_chapter_one_profile_is_exposed(self):
        from jsonschema import Draft202012Validator, ValidationError
        schema = server.SCHEMAS["evaluation_start"]
        Draft202012Validator(schema).validate({"profile": "chapter1_flow"})
        with self.assertRaises(ValidationError):
            Draft202012Validator(schema).validate({"profile": "chapter1_flow_fake"})

    def test_motion_cap_is_bounded_and_chapter_only(self):
        from jsonschema import Draft202012Validator, ValidationError
        validator = Draft202012Validator(server.SCHEMAS["evaluation_start"])
        validator.validate({"profile": "chapter1_flow", "motion_time_scale": 1.0})
        for value in (0, -1, 121, True, "1"):
            with self.subTest(value=value), self.assertRaises(ValidationError):
                validator.validate({"profile": "chapter1_flow", "motion_time_scale": value})
        with self.assertRaisesRegex(ValueError, "only applicable"):
            server.start({"profile": "room_fast", "motion_time_scale": 1.0})

    def test_pretransit_target_is_bounded_and_chapter_only(self):
        from jsonschema import Draft202012Validator, ValidationError
        validator = Draft202012Validator(server.SCHEMAS["evaluation_start"])
        validator.validate({"profile": "chapter1_flow", "pretransit_to": "T01"})
        for value in ("B-P", "../outside", "", 3):
            with self.subTest(value=value), self.assertRaises(ValidationError):
                validator.validate({"profile": "chapter1_flow", "pretransit_to": value})
        with self.assertRaisesRegex(ValueError, "only applicable"):
            server.start({"profile": "room_fast", "pretransit_to": "T01"})
        with self.assertRaisesRegex(ValueError, "Unsupported"):
            server.start({"profile": "chapter1_flow", "pretransit_to": "B-P"})

    def test_kitchen_click_profile_is_bounded_and_headless(self):
        from jsonschema import Draft202012Validator, ValidationError
        validator = Draft202012Validator(server.SCHEMAS["evaluation_start"])
        validator.validate({"profile": "kitchen_click", "interaction_id": "e_b_seal"})
        for invalid in ("../seal", "E B", "x" * 65):
            with self.subTest(value=invalid), self.assertRaises(ValidationError):
                validator.validate({"profile": "kitchen_click", "interaction_id": invalid})
        with self.assertRaisesRegex(ValueError, "only applicable"):
            server.start({"profile": "room_fast", "interaction_id": "e_b_seal"})
        with self.assertRaisesRegex(ValueError, "headless"):
            server.start({"profile": "kitchen_click", "rendered": True})
        with patch.object(c, "executable", return_value=self.directory / "synthetic-godot"):
            with self.assertRaisesRegex(ValueError, "needs snapshot_path"):
                server.start({"profile": "kitchen_click"})

    def test_kitchen_click_worker_uses_validated_snapshot(self):
        from worker import Evaluation
        raw = b"synthetic checkpoint only"
        snapshot = self.directory / "snapshot.json"
        c.write_json(snapshot, {"format": "story-checkpoint-v1", "project": c.ROOT.name,
                     "payload": base64.b64encode(raw).decode(), "sha256": hashlib.sha256(raw).hexdigest(), "host_pid": 1})
        worker = Evaluation.__new__(Evaluation)
        worker.directory = self.directory
        worker.root = c.ROOT
        worker.godot = self.directory / "synthetic-godot"
        worker.run_id = "eval-20261116t000000-1234abcd"
        worker.launch = {"snapshot_path": str(snapshot), "interaction_id": "e_b_seal"}
        command, headless, _, output = worker._job_spec("kitchen-click")
        self.assertTrue(headless)
        self.assertIn("--dv-interaction-id=e_b_seal", command)
        self.assertIn("--dv-snapshot=" + str(snapshot), command)
        self.assertEqual(output, self.directory / "kitchen-click" / "result.json")

    def test_kitchen_diagnostic_rejection_is_blocked_not_pass(self):
        from worker import Evaluation, EvaluationBlocked
        worker = Evaluation.__new__(Evaluation)
        worker.directory = self.directory
        worker.root = c.ROOT
        worker.godot = Path(sys.executable).resolve()
        output = self.directory / "kitchen-click" / "result.json"
        output.parent.mkdir(parents=True, exist_ok=True)
        source = dict(c.provenance.project_identity(c.ROOT), process_id=os.getpid(), executable_path=str(worker.godot))
        data = {"format": "kitchen-click-diagnostic-v1", "source_identity": source,
                "acceptance_eligible": False, "guards_pass": True,
                "approach": {"ok": False}, "handler_accepted": False, "reason": "no_reachable_inspection_stand"}
        c.write_json(output, data)
        with self.assertRaisesRegex(EvaluationBlocked, "no_reachable"):
            worker._validate_output("kitchen-click", output, os.getpid(), False)
        data.update(approach={"ok": True}, handler_accepted=True)
        c.write_json(output, data)
        result = worker._validate_output("kitchen-click", output, os.getpid(), False)
        self.assertIn("not a mouse click", result["scope"])
        data["acceptance_eligible"] = True
        c.write_json(output, data)
        with self.assertRaisesRegex(ValueError, "development-only"):
            worker._validate_output("kitchen-click", output, os.getpid(), False)

    def test_worker_passes_motion_cap_only_when_requested(self):
        from worker import Evaluation
        worker = Evaluation.__new__(Evaluation)
        worker.directory = self.directory
        worker.root = c.ROOT
        worker.godot = self.directory / "synthetic-godot"
        worker.run_id = "eval-20261116t000000-1234abcd"
        worker.launch = {"motion_time_scale": 1.0}
        command, headless, _, _ = worker._job_spec("chapter1-flow")
        self.assertTrue(headless)
        self.assertIn("--dv-motion-scale=1.0", command)
        self.assertIn("--dv-stall-snapshot=" + str(self.directory / "chapter1-flow/stall-snapshot.json"), command)
        self.assertIn("--dv-pretransit-snapshot=" + str(self.directory / "chapter1-flow/pretransit-snapshot.json"), command)
        self.assertIn("--dv-pretransit-from=2F-cross-M", command)
        self.assertIn("--dv-pretransit-to=1F-Shaft-Monitor", command)
        worker.launch = {"pretransit_to": "T01"}
        alternate, _, _, _ = worker._job_spec("chapter1-flow")
        self.assertIn("--dv-pretransit-to=T01", alternate)
        worker.launch = {"pretransit_to": "B-P"}
        with self.assertRaisesRegex(ValueError, "Unsupported"):
            worker._job_spec("chapter1-flow")
        worker.launch = {}
        command, _, _, _ = worker._job_spec("chapter1-flow")
        self.assertFalse(any(value.startswith("--dv-motion-scale=") for value in command))

    def test_stall_snapshot_failure_evidence_requires_the_host_pid(self):
        from worker import Evaluation
        worker = Evaluation.__new__(Evaluation)
        worker.directory = self.directory
        worker.root = c.ROOT
        worker.godot = Path(sys.executable)
        raw = b"synthetic checkpoint only"
        path = self.directory / "chapter1-flow/stall-snapshot.json"
        record = {"format": "story-checkpoint-v1", "project": c.ROOT.name,
                  "payload": base64.b64encode(raw).decode(), "sha256": hashlib.sha256(raw).hexdigest(),
                  "host_pid": os.getpid(), "acceptance_eligible": False}
        c.write_json(path, record)
        detail = worker._failure_evidence("chapter1-flow", os.getpid())
        self.assertEqual(detail["stall_snapshot"], str(path.relative_to(c.ROOT)))
        self.assertEqual(detail["stall_snapshot_sha256"], c.sha256(path))
        with self.assertRaisesRegex(ValueError, "PID"):
            worker._failure_evidence("chapter1-flow", os.getpid() + 100)
        record["acceptance_eligible"] = True
        c.write_json(path, record)
        with self.assertRaisesRegex(ValueError, "development-only"):
            worker._failure_evidence("chapter1-flow", os.getpid())

    def test_pretransit_snapshot_requires_matching_marker_and_host(self):
        from worker import Evaluation
        worker = Evaluation.__new__(Evaluation)
        worker.directory = self.directory
        worker.root = c.ROOT
        worker.godot = Path(sys.executable)
        directory = self.directory / "chapter1-flow"
        path = directory / "pretransit-snapshot.json"
        log = directory / "godot.log"
        raw = b"synthetic envelope only; not a restored Godot state"
        record = {"format": "story-checkpoint-v1", "project": c.ROOT.name,
                  "payload": base64.b64encode(raw).decode(), "sha256": hashlib.sha256(raw).hexdigest(),
                  "host_pid": os.getpid(), "acceptance_eligible": False,
                  "room": "1F-Shaft-Monitor", "stage": "room"}
        marker = {"saved": True, "planned": True, "detective_camera_rules_unchanged": True,
                  "explicit_watcher_before_next_frame": True, "from": "2F-cross-M", "to": "1F-Shaft-Monitor",
                  "detective": [1.25, 2.5], "path_points": 4, "path": str(path), "acceptance_eligible": False}
        c.write_json(path, record)
        prefix = "[DEV DIAGNOSTIC] PRETRANSIT_SNAPSHOT "
        log.write_text(prefix + json.dumps(marker) + "\nRESULT fails=0\n", encoding="utf-8")
        failure = worker._failure_evidence("chapter1-flow", os.getpid())
        success = worker._validate_output("chapter1-flow", None, os.getpid(), False)
        for detail in (failure, success):
            self.assertEqual(detail["pretransit_snapshot"], str(path.relative_to(c.ROOT)))
            self.assertEqual(detail["pretransit_snapshot_sha256"], c.sha256(path))
            self.assertTrue(detail["pretransit_observation"]["explicit_watcher_before_next_frame"])
        log.write_text(prefix + json.dumps(dict(marker, path=path.as_posix())) + "\n", encoding="utf-8")
        self.assertEqual(worker._failure_evidence("chapter1-flow", os.getpid())["pretransit_snapshot_sha256"], c.sha256(path))
        with self.assertRaisesRegex(ValueError, "PID"):
            worker._failure_evidence("chapter1-flow", os.getpid() + 1)
        worker.launch = {"pretransit_to": "T01"}
        with self.assertRaisesRegex(ValueError, "inconsistent"):
            worker._failure_evidence("chapter1-flow", os.getpid())
        c.write_json(path, dict(record, room="T01"))
        log.write_text(prefix + json.dumps(dict(marker, to="T01")) + "\n", encoding="utf-8")
        alternate = worker._failure_evidence("chapter1-flow", os.getpid())
        self.assertEqual(alternate["pretransit_observation"]["to"], "T01")
        worker.launch = {}
        c.write_json(path, record)
        for change in ({"planned": False}, {"detective_camera_rules_unchanged": False},
                       {"explicit_watcher_before_next_frame": False}, {"from": "B-P"},
                       {"path": str(self.directory / "other.json")}, {"path_points": 1},
                       {"detective": [float("nan"), 2.5]}, {"acceptance_eligible": True}):
            with self.subTest(change=change):
                log.write_text(prefix + json.dumps(dict(marker, **change)) + "\n", encoding="utf-8")
                with self.assertRaises(ValueError):
                    worker._failure_evidence("chapter1-flow", os.getpid())
        log.write_text("no marker\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "lacks"):
            worker._failure_evidence("chapter1-flow", os.getpid())
        log.write_text((prefix + json.dumps(marker) + "\n") * 2, encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Multiple"):
            worker._failure_evidence("chapter1-flow", os.getpid())
        log.write_text(prefix + json.dumps(marker) + "\n", encoding="utf-8")
        for change in ({"room": "B-P"}, {"stage": "kitchen"}, {"acceptance_eligible": True}, {"sha256": "0" * 64}):
            with self.subTest(change=change):
                c.write_json(path, dict(record, **change))
                with self.assertRaises(ValueError):
                    worker._failure_evidence("chapter1-flow", os.getpid())
        path.unlink()
        with self.assertRaisesRegex(ValueError, "missing"):
            worker._failure_evidence("chapter1-flow", os.getpid())
        log.write_text(prefix + json.dumps(dict(marker, saved=False)) + "\n", encoding="utf-8")
        self.assertNotIn("pretransit_snapshot", worker._failure_evidence("chapter1-flow", os.getpid()))


class GateTests(ProjectFixture):
    def setUp(self):
        super().setUp()
        self.run_id = "eval-20261116t000000-1234abcd"
        patcher = patch.object(c, "RUNS", self.directory / "runs")
        patcher.start()
        self.addCleanup(patcher.stop)
        self.run = c.run_dir(self.run_id)
        self.run.mkdir(parents=True)
        self.revision = "a" * 40
        self.data = {"state": "completed", "revision": self.revision, "working_tree_changes": "",
                     "source_changed_during_run": False, "source_identity": c.provenance.project_identity(c.ROOT),
                     "jobs": {k: {"state": "passed"} for k in
                              ("chapter1-flow", "bedroom-fast", "corridor-fast", "kitchen-fast")}}
        c.write_json(self.run / "launch.json", {"run_id": self.run_id, "project_root": str(c.ROOT)})
        state = patch.object(c, "revision_state", return_value={"revision": self.revision, "working_tree_changes": ""})
        state.start()
        self.addCleanup(state.stop)

    def gate(self):
        c.write_json(self.run / "status.json", self.data)
        return server.gate(self.run_id)

    def test_clean_complete_fast_run_is_only_slow_run_ready(self):
        result = self.gate()
        self.assertTrue(result["ready_for_independent_slow_run"])
        self.assertEqual(result["formal_acceptance"], "pending_independent_terra_review")

    def test_chapter_only_never_satisfies_room_gates(self):
        self.data["jobs"] = {"chapter1-flow": {"state": "passed"}}
        result = self.gate()
        self.assertFalse(result["ready_for_independent_slow_run"])
        self.assertEqual(result["formal_acceptance"], "pending_independent_terra_review")
        self.assertFalse(result["fast_checks"]["corridor-fast"])

    def test_kitchen_click_only_never_satisfies_room_gates(self):
        self.data["jobs"] = {"kitchen-click": {"state": "passed"}}
        result = self.gate()
        self.assertFalse(result["ready_for_independent_slow_run"])
        self.assertFalse(result["fast_checks"]["kitchen-fast"])
        self.assertEqual(result["formal_acceptance"], "pending_independent_terra_review")

    def test_blocked_corridor_or_dirty_sources_stop_slow_run(self):
        self.data["jobs"]["corridor-fast"]["state"] = "blocked"
        self.assertFalse(self.gate()["ready_for_independent_slow_run"])
        self.data["jobs"]["corridor-fast"]["state"] = "passed"
        self.data["working_tree_changes"] = "modified"
        self.assertFalse(self.gate()["ready_for_independent_slow_run"])
        self.data["working_tree_changes"] = ""
        self.data["source_changed_during_run"] = True
        self.assertFalse(self.gate()["ready_for_independent_slow_run"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
