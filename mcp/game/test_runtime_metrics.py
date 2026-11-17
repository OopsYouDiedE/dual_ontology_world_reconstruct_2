"""MCP close automatically summarizes eligible live-session telemetry."""
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import runtime


class FinalizeMetricsTests(unittest.TestCase):
    def endpoint(self, directory, **changes):
        values = dict(backend="godot", snapshot_path=None, movie_path=None,
                      metrics_directory=directory, process=SimpleNamespace(pid=123), expected_source={})
        values.update(changes)
        return SimpleNamespace(**values)

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
