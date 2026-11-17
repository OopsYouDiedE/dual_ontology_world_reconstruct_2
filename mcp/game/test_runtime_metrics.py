"""MCP close automatically summarizes eligible live-session telemetry."""
import json
from pathlib import Path
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import runtime


class FinalizeMetricsTests(unittest.TestCase):
    def test_slow_analysis_does_not_block_close_receipt_and_can_be_polled(self):
        entered, release, finished = threading.Event(), threading.Event(), threading.Event()
        def analyze(endpoint, graceful):
            entered.set()
            release.wait(5)
            finished.set()
            return {"metrics_status": "complete", "metrics_summary_path": "same-session.json"}
        with patch.object(runtime, "finalize_metrics", side_effect=analyze):
            result = runtime.collect_metrics_async("slow-test", object(), True)
            self.assertEqual(result["metrics_status"], "running")
            self.assertTrue(entered.wait(2))
            self.assertEqual(runtime.execute("metrics_status", {"session_id": "slow-test"})["metrics_status"], "running")
            release.set()
            self.assertTrue(finished.wait(2))
        import time
        for _ in range(100):
            result = runtime.execute("metrics_status", {"session_id": "slow-test"})
            if result["metrics_status"] == "complete":
                break
            time.sleep(.01)
        self.assertEqual(result["metrics_summary_path"], "same-session.json")

    def test_close_retry_returns_original_receipt(self):
        receipt = {"session_id": "closed-test", "closed": True, "graceful_exit": True}
        with patch.dict(runtime.COMPLETED, {"closed-test": receipt}):
            self.assertEqual(runtime.execute("close", {"session_id": "closed-test"}), receipt)

    def endpoint(self, directory, **changes):
        values = dict(backend="godot", snapshot_path=None, scenario_path=None, movie_path=None,
                      metrics_directory=directory, process=SimpleNamespace(pid=123), expected_source={})
        values.update(changes)
        return SimpleNamespace(**values)

    def test_scenario_ready_requires_matching_scene_test_and_recorder(self):
        with tempfile.TemporaryDirectory(dir=runtime.ROOT / ".runtime") as base:
            directory = Path(base) / "run-123"
            directory.mkdir()
            endpoint = self.endpoint(directory, assessment_plan={"test_id": "test-1"})
            observation = {"scene": "res://mcp/game/SegmentEntry.tscn", "scenario_ready": True,
                           "assessment_test_id": "test-1", "metrics_directory": str(directory)}
            self.assertTrue(runtime._scenario_start_ready(endpoint, observation))
            self.assertFalse(runtime._scenario_start_ready(endpoint, dict(observation, scenario_ready=False)))
            self.assertFalse(runtime._scenario_start_ready(endpoint, dict(observation, metrics_directory="")))
            self.assertFalse(runtime._scenario_start_ready(endpoint, dict(observation, scene="res://scenes/main/Boot.tscn")))
            for change in ({"scene": "res://scenes/main/Main.tscn"}, {"assessment_test_id": "wrong"},
                           {"metrics_directory": str(Path(base) / "run-456")}, {"scenario_error": "bad fixture"}):
                with self.subTest(change=change), self.assertRaises(RuntimeError):
                    runtime._scenario_start_ready(endpoint, dict(observation, **change))

    def test_close_reports_concurrency_write_error(self):
        endpoint = self.endpoint(None, backend="cli", lock=threading.Lock(), closed=True,
                                 last_source=None, server_source={},
                                 concurrency_observation_error="disk full", stop=lambda: None)
        with patch.dict(runtime.SESSIONS, {"test-session": endpoint}):
            result = runtime.execute("close", {"session_id": "test-session"})
        self.assertEqual(result["concurrency_observation_error"], "disk full")

    def test_movie_and_interrupted_runs_are_not_scored(self):
        self.assertEqual(runtime.finalize_metrics(self.endpoint(None, movie_path="movie"), True)["metrics_status"], "not_eligible")
        self.assertEqual(runtime.finalize_metrics(self.endpoint(None), False)["metrics_status"], "incomplete")
        partial = runtime.finalize_metrics(self.endpoint(None, snapshot_path="mock"), False)
        self.assertEqual(partial["metrics_status"], "incomplete")
        self.assertIs(partial["acceptance_eligible"], False)
        self.assertEqual(runtime.finalize_metrics(self.endpoint(None, backend="cli"), True)["metrics_status"], "not_applicable")

    def test_closed_live_run_produces_bound_segment_summary(self):
        with tempfile.TemporaryDirectory(dir=runtime.ROOT / ".runtime") as base:
            directory = Path(base) / "run-123"
            directory.mkdir()
            with patch.object(runtime.provenance, "project_path", side_effect=lambda path, root: Path(path)), \
                 patch.object(runtime.provenance, "validate_source") as validate, \
                 patch("importlib.import_module", return_value=SimpleNamespace(summarize=lambda path: {"source_identity": {"process_id": 123}, "segments": {"wake": {}}})):
                result = runtime.finalize_metrics(self.endpoint(directory), True)
            self.assertEqual(result["metrics_status"], "complete")
            self.assertEqual(result["metrics_segments"], ["wake"])
            self.assertFalse(result["acceptance_scored"])
            self.assertEqual(validate.call_args.kwargs["pid"], 123)

    def test_concurrency_context_is_bound_to_summary_and_survives_failure(self):
        with tempfile.TemporaryDirectory(dir=runtime.ROOT / ".runtime") as base:
            directory = Path(base) / "run-123"
            directory.mkdir()
            observation = directory / "concurrency-observation.json"
            observation.write_text(json.dumps({"host_pid": 123, "peak_observed_godot_processes": 2}), encoding="utf-8")
            endpoint = self.endpoint(directory, concurrency_observation_path=observation)
            with patch.object(runtime.provenance, "validate_source"), \
                 patch("importlib.import_module", return_value=SimpleNamespace(summarize=lambda path: {"source_identity": {}, "segments": {}})):
                result = runtime.finalize_metrics(endpoint, True)
            summary = json.loads(Path(result["metrics_summary_path"]).read_text(encoding="utf-8"))
            self.assertEqual(summary["concurrency_observation"]["host_pid"], 123)
            with patch("importlib.import_module", side_effect=RuntimeError("analysis failed")):
                failed = runtime.finalize_metrics(endpoint, True)
            self.assertEqual(failed["concurrency_observation_path"], str(observation))

    def test_snapshot_summary_is_separate_and_bound_to_host(self):
        with tempfile.TemporaryDirectory(dir=runtime.ROOT / ".runtime") as base:
            directory = Path(base) / "run-123"
            directory.mkdir()
            snapshot = Path(base) / "snapshot.json"
            data = {"source_identity": {"process_id": 123}, "segments": {"kitchen": {}},
                    "acceptance_eligible": False, "snapshot_path": str(snapshot)}
            from unittest.mock import Mock
            summarize = Mock(return_value=data)
            with patch.object(runtime.provenance, "validate_source") as validate, \
                 patch("importlib.import_module", return_value=SimpleNamespace(summarize=summarize)):
                result = runtime.finalize_metrics(self.endpoint(directory, snapshot_path=snapshot), True)
            self.assertEqual(result["metrics_status"], "complete")
            self.assertFalse(result["acceptance_eligible"])
            self.assertFalse(result["acceptance_scored"])
            self.assertEqual(Path(result["metrics_summary_path"]).name, "segment-metrics-development.json")
            self.assertEqual(json.loads(Path(result["metrics_summary_path"]).read_text(encoding="utf-8")), data)
            summarize.assert_called_once_with(directory, snapshot_path=snapshot)
            self.assertEqual(validate.call_args.kwargs["pid"], 123)

    def test_scenario_summary_is_bound_to_configured_entry_and_host(self):
        with tempfile.TemporaryDirectory(dir=runtime.ROOT / ".runtime") as base:
            directory = Path(base) / "run-123"
            directory.mkdir()
            scenario = Path(base) / "scenario.yaml"
            scenario.write_text("{}", encoding="utf-8")
            data = {"source_identity": {"process_id": 123}, "segments": {"wake": {}},
                    "entry": "scenario", "acceptance_eligible": False, "scenario_path": str(scenario)}
            from unittest.mock import Mock
            summarize = Mock(return_value=data)
            with patch.object(runtime.provenance, "validate_source") as validate, \
                 patch("importlib.import_module", return_value=SimpleNamespace(summarize=summarize)):
                result = runtime.finalize_metrics(self.endpoint(directory, scenario_path=scenario), True)
            self.assertEqual(result["metrics_status"], "complete")
            self.assertEqual(result["scenario_path"], str(scenario))
            summarize.assert_called_once_with(directory, scenario_path=scenario)
            self.assertEqual(validate.call_args.kwargs["pid"], 123)
            for change in ({"scenario_path": "other"}, {"entry": "production_title"}, {"acceptance_eligible": True}):
                with patch("importlib.import_module", return_value=SimpleNamespace(summarize=lambda *args, **kw: dict(data, **change))):
                    failed = runtime.finalize_metrics(self.endpoint(directory, scenario_path=scenario), True)
                self.assertEqual(failed["metrics_status"], "error")
                self.assertIn("provenance mismatch", failed["metrics_error"])

    def test_snapshot_summary_rejects_incorrect_provenance(self):
        with tempfile.TemporaryDirectory(dir=runtime.ROOT / ".runtime") as base:
            directory = Path(base) / "run-123"
            directory.mkdir()
            snapshot = Path(base) / "snapshot.json"
            for data in ({"acceptance_eligible": True, "snapshot_path": str(snapshot)},
                         {"acceptance_eligible": False, "snapshot_path": "other"}):
                with patch("importlib.import_module", return_value=SimpleNamespace(summarize=lambda *a, **kw: data)):
                    result = runtime.finalize_metrics(self.endpoint(directory, snapshot_path=snapshot), True)
                self.assertEqual(result["metrics_status"], "error")
                self.assertIs(result["acceptance_eligible"], False)
                self.assertFalse((directory / "segment-metrics-development.json").exists())

    def test_summary_failure_is_returned_without_fabricating_score(self):
        with tempfile.TemporaryDirectory(dir=runtime.ROOT / ".runtime") as base:
            directory = Path(base) / "run-123"
            directory.mkdir()
            with patch.object(runtime.provenance, "project_path", side_effect=lambda path, root: Path(path)), \
                 patch("importlib.import_module", side_effect=RuntimeError("analysis failed")):
                result = runtime.finalize_metrics(self.endpoint(directory), True)
            self.assertEqual(result["metrics_status"], "error")
            self.assertIn("analysis failed", result["metrics_error"])


if __name__ == "__main__":
    unittest.main()
