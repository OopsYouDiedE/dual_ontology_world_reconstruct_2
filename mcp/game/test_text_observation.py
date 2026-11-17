import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from text_observation import append_text_observation

ROOT = Path(__file__).resolve().parents[2]


class _Process:
    pid = 12345
    def poll(self): return None


class _Endpoint:
    backend = "godot"
    closed = False
    process = _Process()
    def request(self, operation): return self.observation


class TextObservationTests(unittest.TestCase):
    def setUp(self):
        base = ROOT / ".runtime" / "text-observation-tests"
        base.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=base)
        directory = Path(self.temporary.name) / "run-12345"
        directory.mkdir()
        plan_path = Path(self.temporary.name) / "plan.json"
        plan_path.write_text("{}", encoding="utf-8")
        self.endpoint = _Endpoint()
        self.endpoint.metrics_directory = directory
        self.endpoint.assessment_plan = {"test_id": "t1", "revision": "rev", "plan_path": str(plan_path),
            "plan_sha256": hashlib.sha256(plan_path.read_bytes()).hexdigest(),
            "blind_observer": {"identity": "blind"}, "cases": [{"id": "c1", "segment_id": "wake"}]}
        self.endpoint.observation = {"assessment_test_id": "t1", "assessment_case_index": 0,
            "assessment_segment": "wake/bedroom", "metrics_directory": str(directory),
            "metrics": {"elapsed_s": 1.5}, "controls": [{"path": "/prompt", "text": "Open"}]}

    def tearDown(self): self.temporary.cleanup()

    def test_live_entry_is_bound_to_current_visible_text(self):
        result = append_text_observation(self.endpoint, "session", "/prompt", "Open", "prompt", True, ROOT)
        row = json.loads(Path(result["evidence_path"]).read_text(encoding="utf-8"))
        self.assertEqual((row["test_id"], row["host_pid"], row["reviewer"]), ("t1", 12345, "blind"))
        self.assertEqual((row["case_id"], row["segment_id"], row["monitor_elapsed_s"]), ("c1", "wake", 1.5))
        self.assertEqual((row["path"], row["text"], row["category"]), ("/prompt", "Open", "prompt"))

    def test_rejects_missing_text_and_unready_host(self):
        with self.assertRaises(ValueError):
            append_text_observation(self.endpoint, "session", "/prompt", "Closed", "prompt", True, ROOT)
        self.endpoint.closed = True
        with self.assertRaises(ValueError):
            append_text_observation(self.endpoint, "session", "/prompt", "Open", "prompt", True, ROOT)


if __name__ == "__main__": unittest.main()
