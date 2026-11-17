"""Verify that warmup exemptions never hide a steady exploration stall."""
import csv
import json
from pathlib import Path
import tempfile
import unittest
import os
import yaml

from mainline_metrics import summarize, provenance, audio_score

ROOT = Path(__file__).resolve().parents[2]


class MainlineMetricsTests(unittest.TestCase):
    def measure(self, rows, *, legacy=False, text_count=None, metadata_override=None, snapshot_path=None, full=False):
        base = ROOT / ".runtime/metrics-unit-tests"
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            path = Path(directory)
            metadata = dict(mock=False, entry="production_title", measurement_context="rendered_runtime",
                            source_identity=dict(provenance.project_identity(ROOT), process_id=os.getpid()))
            if metadata_override:
                metadata.update(metadata_override)
            if text_count is not None:
                metadata["content_text_policy"] = "visible_active_viewports"
            sample = "" if text_count is None else "  - " + json.dumps({"gameplay_segment": "kitchen_evidence", "total_visible_characters": text_count}) + "\n"
            (path / "timeline.yaml").write_text(yaml.safe_dump({"metadata": metadata}) + "timeline:\n" + sample + "summary: {}\n", encoding="utf-8")
            with (path / "frames.csv").open("w", newline="", encoding="utf-8") as stream:
                fields = ["node", "elapsed_s", "frame_ms"] + ([] if legacy else ["measurement_phase"])
                writer = csv.DictWriter(stream, fieldnames=fields)
                writer.writeheader()
                for index, (milliseconds, phase) in enumerate(rows):
                    row = dict(node="kitchen_evidence/B-P", elapsed_s=index + 1, frame_ms=milliseconds)
                    if not legacy:
                        row["measurement_phase"] = phase
                    writer.writerow(row)
            result = summarize(path, snapshot_path=snapshot_path)
            return result if full else result["segments"]["kitchen_evidence"]

    def test_snapshot_metrics_are_explicitly_development_only(self):
        snapshot = ROOT / ".runtime" / "fixture.json"
        metadata = dict(mock=True, entry="snapshot", snapshot_path=str(snapshot), acceptance_eligible=False)
        result = self.measure([(200, "loading_warmup"), (16, "steady")],
                              metadata_override=metadata, snapshot_path=snapshot, full=True)
        self.assertIs(result["acceptance_eligible"], False)
        self.assertIs(result["acceptance_scored"], False)
        self.assertEqual(result["snapshot_path"], str(snapshot))
        self.assertEqual(result["entry"], "snapshot")
        self.assertEqual(result["source_identity"]["process_id"], os.getpid())
        self.assertEqual(set(result["source_sha256"]), {"timeline.yaml", "frames.csv"})
        self.assertEqual(result["segments"]["kitchen_evidence"]["steady"]["frame_samples"], 1)
        with self.assertRaises(ValueError):
            self.measure([(16, "steady")], metadata_override=metadata)
        for change in (dict(acceptance_eligible=True), dict(mock=False), dict(entry="production_title"),
                       dict(snapshot_path=str(ROOT / ".runtime" / "other.json"))):
            with self.subTest(change=change), self.assertRaises(ValueError):
                self.measure([(16, "steady")], metadata_override=dict(metadata, **change), snapshot_path=snapshot)

    def test_production_cannot_use_snapshot_mode(self):
        with self.assertRaises(ValueError):
            self.measure([(16, "steady")], snapshot_path=ROOT / ".runtime" / "fixture.json")

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

    def test_unclassified_visible_text_is_not_scored(self):
        for count in (0, 26, 61):
            result = self.measure([(16, "steady")], text_count=count)
            self.assertEqual(result["max_recorded_visible_characters"], count)
            self.assertIsNone(result["measured_scores"][1])
            self.assertIn("classification", result["text_score_reason"])

    def test_audio_requires_signal_and_completed_analysis(self):
        self.assertIsNone(audio_score({"status": "error", "signal_present": True, "integrated_lufs": -25, "true_peak_dbtp": -30})[0])
        self.assertIsNone(audio_score({"status": "complete", "signal_present": False, "integrated_lufs": -25, "true_peak_dbtp": -30})[0])

    def test_audio_thresholds_and_unisolated_ambient(self):
        def score(lufs, peak):
            return audio_score({"status": "complete", "signal_present": True, "integrated_lufs": lufs, "true_peak_dbtp": peak})[0]
        self.assertEqual(score(-25, -21), 8)
        self.assertEqual(score(-20, -21), 6)
        self.assertEqual(score(-25, 0), 6)
        self.assertIsNone(score(-25, -20))
        self.assertIsNone(score(-25, -3))

    def test_legacy_frames_get_no_inferred_exemption(self):
        result = self.measure([(200, "steady"), (16, "steady")], legacy=True)
        self.assertEqual(result["loading_warmup"]["frame_samples"], 0)
        self.assertEqual(result["measured_scores"][0], 6)


if __name__ == "__main__":
    unittest.main()
