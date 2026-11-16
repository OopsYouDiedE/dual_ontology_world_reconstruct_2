"""Verify that warmup exemptions never hide a steady exploration stall."""
import csv
from pathlib import Path
import tempfile
import unittest
import os
import yaml

from mainline_metrics import summarize, provenance

ROOT = Path(__file__).resolve().parents[2]


class MainlineMetricsTests(unittest.TestCase):
    def measure(self, rows, *, legacy=False):
        base = ROOT / ".runtime/metrics-unit-tests"
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            path = Path(directory)
            metadata = dict(mock=False, entry="production_title", measurement_context="rendered_runtime",
                            source_identity=dict(provenance.project_identity(ROOT), process_id=os.getpid()))
            (path / "timeline.yaml").write_text(yaml.safe_dump({"metadata": metadata}) + "timeline:\nsummary: {}\n", encoding="utf-8")
            with (path / "frames.csv").open("w", newline="", encoding="utf-8") as stream:
                fields = ["node", "elapsed_s", "frame_ms"] + ([] if legacy else ["measurement_phase"])
                writer = csv.DictWriter(stream, fieldnames=fields)
                writer.writeheader()
                for index, (milliseconds, phase) in enumerate(rows):
                    row = dict(node="kitchen_evidence/B-P", elapsed_s=index + 1, frame_ms=milliseconds)
                    if not legacy:
                        row["measurement_phase"] = phase
                    writer.writerow(row)
            return summarize(path)["segments"]["kitchen_evidence"]

    def test_loading_spike_retained_but_separate(self):
        result = self.measure([(200, "loading_warmup"), (16, "steady")])
        self.assertEqual(result["raw_spikes_over_33_3_ms"], 1)
        self.assertEqual(result["loading_warmup"]["max_frame_ms"], 200)
        self.assertEqual(result["steady"]["max_frame_ms"], 16)
        self.assertEqual(result["measured_scores"][0], 8)

    def test_one_steady_spike_vetoes(self):
        result = self.measure([(200, "loading_warmup"), (33.3, "steady"), (33.31, "steady")])
        self.assertEqual(result["spikes_over_33_3_ms"], 1)
        self.assertEqual(result["measured_scores"][0], 6)

    def test_only_loading_has_no_performance_score(self):
        result = self.measure([(200, "loading_warmup")])
        self.assertEqual(result["steady"]["frame_samples"], 0)
        self.assertIsNone(result["measured_scores"][0])

    def test_legacy_frames_get_no_inferred_exemption(self):
        result = self.measure([(200, "steady"), (16, "steady")], legacy=True)
        self.assertEqual(result["loading_warmup"]["frame_samples"], 0)
        self.assertEqual(result["measured_scores"][0], 6)


if __name__ == "__main__":
    unittest.main()
