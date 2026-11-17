import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from types import SimpleNamespace

from blind_observation import append_observation


class FakeEndpoint:
    def __init__(self, root):
        self.root = Path(root)
        plan_path = self.root / "plan.json"
        plan_path.write_text('{"test_id":"t1"}', encoding="utf-8")
        self.assessment_plan = {
            "test_id": "t1", "revision": "abc", "plan_path": str(plan_path),
            "plan_sha256": hashlib.sha256(plan_path.read_bytes()).hexdigest(),
            "blind_observer": {"identity": "terra"},
            "cases": [{"id": "case-a", "segment_id": "wake"},
                      {"id": "case-b", "segment_id": "wake"}],
        }
        self.closed = False
        self.backend = "godot"
        self.process = SimpleNamespace(pid=123, poll=lambda: None)
        self.metrics_directory = self.root / "run-123"
        self.metrics_directory.mkdir()
        self.observed = {"assessment_test_id": "t1", "assessment_case_index": 0,
                         "assessment_segment": "wake/bedroom", "metrics": {"elapsed_s": 2.5},
                         "metrics_directory": str(self.metrics_directory)}

    def request(self, operation):
        assert operation == {"type": "observe", "wait_ms": 0, "capture_image": False}
        return self.observed


class BlindObservationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parents[2])
        self.root = Path(self.temp.name)
        self.endpoint = FakeEndpoint(self.root)

    def tearDown(self):
        self.temp.cleanup()

    def test_notes_are_appended_with_same_session_case_and_monitor_timestamp(self):
        first = append_observation(self.endpoint, "session", "event_script", "The door opens.", self.root)
        self.endpoint.observed["assessment_case_index"] = 1
        second = append_observation(self.endpoint, "session", "charactor_script", "Hello there.", self.root)
        rows = [json.loads(line) for line in Path(first["evidence_path"]).read_text(encoding="utf-8").splitlines()]
        self.assertEqual([row["kind"] for row in rows], ["event", "character"])
        self.assertEqual([row["case_id"] for row in rows], ["case-a", "case-b"])
        self.assertEqual(rows[0]["monitor_elapsed_s"], 2.5)
        self.assertEqual(rows[0]["host_pid"], 123)
        self.assertEqual(rows[0]["test_id"], "t1")
        self.assertEqual(second["case_id"], "case-b")

    def test_changed_plan_or_wrong_host_cannot_record(self):
        Path(self.endpoint.assessment_plan["plan_path"]).write_text("{}", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "plan changed"):
            append_observation(self.endpoint, "session", "event_script", "The door opens.", self.root)
        self.endpoint.assessment_plan["plan_sha256"] = hashlib.sha256(b"{}").hexdigest()
        self.endpoint.observed["assessment_test_id"] = "other"
        with self.assertRaisesRegex(ValueError, "test ID mismatch"):
            append_observation(self.endpoint, "session", "event_script", "The door opens.", self.root)
        self.endpoint.observed["assessment_test_id"] = "t1"
        self.endpoint.observed["metrics_directory"] = str(self.root)
        with self.assertRaisesRegex(ValueError, "Monitor directory"):
            append_observation(self.endpoint, "session", "event_script", "The door opens.", self.root)

    def test_unavailable_monitor_case_or_process_cannot_record(self):
        self.endpoint.observed["assessment_case_index"] = 2
        with self.assertRaisesRegex(ValueError, "case index"):
            append_observation(self.endpoint, "session", "event_script", "The door opens.", self.root)
        self.endpoint.observed["assessment_case_index"] = 0
        self.endpoint.observed["metrics"] = {}
        with self.assertRaisesRegex(ValueError, "timestamped"):
            append_observation(self.endpoint, "session", "event_script", "The door opens.", self.root)
        self.endpoint.process.poll = lambda: 1
        with self.assertRaisesRegex(ValueError, "not running"):
            append_observation(self.endpoint, "session", "event_script", "The door opens.", self.root)

    def test_text_validation(self):
        for text in ("", "1234", "A door 打开", "A door\x00"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                append_observation(self.endpoint, "session", "character_script", text, self.root)
        with self.assertRaisesRegex(ValueError, "Unsupported observation"):
            append_observation(self.endpoint, "session", "unknown", "hello", self.root)


if __name__ == "__main__":
    unittest.main()
