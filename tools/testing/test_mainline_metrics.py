"""Verify that warmup exemptions never hide a steady exploration stall."""
import csv
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import subprocess
import os
import yaml

from mainline_metrics import summarize, provenance, audio_score, _load_text_reviews, _load_live_text_reviews, file_hash

ROOT = Path(__file__).resolve().parents[2]


class MainlineMetricsTests(unittest.TestCase):
    def measure(self, rows, *, legacy=False, text_count=None, metadata_override=None, snapshot_path=None, scenario_path=None, full=False, text_records=None, text_summary=None, live_review=False, audio_fixture=False):
        base = ROOT / ".runtime/metrics-unit-tests"
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            path = Path(directory)
            metadata = dict(mock=False, entry="production_title", measurement_context="rendered_runtime",
                            source_identity=dict(provenance.project_identity(ROOT), process_id=os.getpid()))
            if metadata_override:
                metadata.update(metadata_override)
            if live_review:
                plan = path / "plan.json"
                plan.write_text(json.dumps({"blind_observer": {"identity": "blind"}, "cases": [{"id": "case", "segment_id": "kitchen_evidence"}]}), encoding="utf-8")
                metadata.update(test_id="one", revision="abc", assessment_plan=str(plan), assessment_plan_sha256=file_hash(plan))
                review = {"schema_version": 1, "test_id": "one", "revision": "abc", "host_pid": os.getpid(),
                          "assessment_plan_sha256": file_hash(plan), "reviewer": "blind", "session_id": "session",
                          "case_id": "case", "segment_id": "kitchen_evidence", "monitor_elapsed_s": 1,
                          "path": "/p", "text": "Hello", "category": "dialogue", "english_verified": True}
                (path / "visible-text-reviews.jsonl").write_text(json.dumps(review) + "\n", encoding="utf-8")
            if text_count is not None:
                metadata["content_text_policy"] = "visible_active_viewports"
            sample = "" if text_count is None else "  - " + json.dumps({"gameplay_segment": "kitchen_evidence", "total_visible_characters": text_count}) + "\n"
            (path / "timeline.yaml").write_text(yaml.safe_dump({"metadata": metadata}) + "timeline:\n" + sample + yaml.safe_dump({"summary": text_summary or {}}), encoding="utf-8")
            if audio_fixture:
                (path / "audio.json").write_text(json.dumps({"status": "complete", "sample_rate": 100}), encoding="utf-8")
                (path / "mix.f32le").write_bytes(bytes(8 * 300))
            if text_records is not None:
                (path / "visible-text-changes.jsonl").write_text("".join(json.dumps(item, ensure_ascii=False) + "\n" for item in text_records), encoding="utf-8")
            with (path / "frames.csv").open("w", newline="", encoding="utf-8") as stream:
                fields = ["node", "elapsed_s", "frame_ms"] + ([] if legacy else ["measurement_phase"])
                writer = csv.DictWriter(stream, fieldnames=fields)
                writer.writeheader()
                for index, (milliseconds, phase) in enumerate(rows):
                    row = dict(node="kitchen_evidence/B-P", elapsed_s=index + 1, frame_ms=milliseconds)
                    if not legacy:
                        row["measurement_phase"] = phase
                    writer.writerow(row)
            result = summarize(path, snapshot_path=snapshot_path, scenario_path=scenario_path)
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

    def test_scenario_metadata_requires_existing_matching_project_file(self):
        scenario = ROOT / "assets/data/test_scenarios/wake.yaml"
        self.assertTrue(scenario.is_file())
        metadata = dict(mock=True, entry="scenario", scenario_path=str(scenario))
        result = self.measure([(16, "steady")], metadata_override=metadata, scenario_path=scenario, full=True)
        self.assertEqual(result["scenario_path"], str(scenario))
        for change in (dict(mock=False), dict(entry="production_title"), dict(scenario_path=str(scenario.parent / "other.yaml")),
                       dict(measurement_context="fixed_step_movie")):
            with self.subTest(change=change), self.assertRaises(ValueError):
                self.measure([(16, "steady")], metadata_override=dict(metadata, **change), scenario_path=scenario)
        with self.assertRaises(ValueError):
            self.measure([(16, "steady")], metadata_override=metadata, scenario_path=scenario.parent / "missing.yaml")
        with self.assertRaises(ValueError):
            self.measure([(16, "steady")], metadata_override=metadata, scenario_path=scenario, snapshot_path=ROOT / ".runtime" / "fixture.json")

    def test_production_cannot_use_snapshot_mode(self):
        with self.assertRaises(ValueError):
            self.measure([(16, "steady")], snapshot_path=ROOT / ".runtime" / "fixture.json")

    def test_loading_spike_retained_but_separate(self):
        result = self.measure([(200, "loading_warmup"), (16, "steady")])
        self.assertEqual(result["raw_spikes_over_33_3_ms"], 1)
        self.assertEqual(result["loading_warmup"]["max_frame_ms"], 200)
        self.assertEqual(result["steady"]["max_frame_ms"], 16)
        self.assertEqual(result["measured_scores"][0], 8)

    def test_audio_timeout_preserves_frame_measurements(self):
        route = {"stable": True, "snapshot": {"any_solo": False, "buses": {
            "Master": {"muted": False, "bypass": False, "capture_active": True, "volume_db": 0}}}}
        summary = {"audio_route": route, "master_start_offset_s": 0}
        with patch('mainline_metrics.find_ffmpeg', return_value='ffmpeg'), \
             patch('mainline_metrics.subprocess.run', side_effect=subprocess.TimeoutExpired('ffmpeg', 180)):
            result = self.measure([(16, "steady"), (35, "steady")], text_summary=summary, audio_fixture=True)
        self.assertEqual(result['steady']['frame_samples'], 2)
        self.assertEqual(result['measured_scores'][0], 6)
        self.assertIsNone(result['measured_scores'][3])
        self.assertEqual(result['audio']['status'], 'error')
        self.assertIn('timed out', result['audio_score_reason'])

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

    def test_visible_text_scoring_requires_complete_same_session_collection(self):
        record = {"frame": 1, "elapsed_s": 1.0, "scene_node": "kitchen_evidence/B-P", "entries": []}
        complete = {"frames": 2, "visible_text_collection": {"complete": True, "checked_frames": 2, "write_errors": 0}}
        result = self.measure([(16, "steady"), (16, "steady")], text_records=[record], text_summary=complete, full=True)
        self.assertEqual(result["segments"]["kitchen_evidence"]["measured_scores"][1], 10)
        self.assertIn("visible-text-changes.jsonl", result["source_sha256"])
        broken = {"frames": 2, "visible_text_collection": {"complete": True, "checked_frames": 1, "write_errors": 0}}
        result = self.measure([(16, "steady"), (16, "steady")], text_records=[record], text_summary=broken)
        self.assertIsNone(result["measured_scores"][1])
        self.assertIn("coverage was not verified", result["text_score_reason"])

    def test_visible_text_failure_and_unreviewed_strings_are_preserved(self):
        complete = {"frames": 1, "visible_text_collection": {"complete": True, "checked_frames": 1, "write_errors": 0}}
        entry = {"path": "/dialogue", "text": "你好", "category": "dialogue"}
        record = {"frame": 1, "elapsed_s": 1.0, "scene_node": "kitchen_evidence/B-P", "entries": [entry]}
        result = self.measure([(16, "steady")], text_records=[record], text_summary=complete)
        self.assertEqual(result["measured_scores"][1], 6)
        entry["text"] = "Hello"
        entry["category"] = "unknown"
        result = self.measure([(16, "steady")], text_records=[record], text_summary=complete)
        self.assertEqual(result["measured_scores"][1], 8)
        self.assertIn("counted conservatively", result["text_score_reason"])

    def test_settlement_automatically_uses_live_session_review(self):
        complete = {"frames": 1, "visible_text_collection": {"complete": True, "checked_frames": 1, "write_errors": 0}}
        record = {"frame": 1, "elapsed_s": 1.0, "scene_node": "kitchen_evidence/B-P",
                  "entries": [{"path": "/p", "text": "Hello", "category": "unknown"}]}
        result = self.measure([(16, "steady")], text_records=[record], text_summary=complete, full=True, live_review=True)
        self.assertEqual(result["segments"]["kitchen_evidence"]["measured_scores"][1], 8)
        self.assertIn("visible-text-reviews.jsonl", result["source_sha256"])
        self.assertEqual(result["test_id"], "one")

    def test_review_requires_same_test_revision_pid_and_timeline(self):
        base = ROOT / ".runtime/metrics-unit-tests"
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            path = Path(directory)
            timeline = path / "visible-text-changes.jsonl"
            timeline.write_text("{}\n", encoding="utf-8")
            metadata = {"test_id": "one", "revision": "abc", "source_identity": {"process_id": 123}}
            document = {"schema_version": 1, "test_id": "one", "revision": "abc", "process_id": 123,
                        "timeline_sha256": file_hash(timeline), "reviewer": "observer",
                        "entries": [{"path": "/p", "text": "Hello", "category": "dialogue", "english_verified": True}]}
            review = path / "review.json"
            review.write_text(json.dumps(document), encoding="utf-8")
            self.assertTrue(_load_text_reviews(review, metadata, timeline)[("/p", "Hello")]["english_verified"])
            for key, value in (("test_id", "other"), ("revision", "other"), ("process_id", 124), ("timeline_sha256", "other")):
                changed = dict(document, **{key: value})
                review.write_text(json.dumps(changed), encoding="utf-8")
                with self.subTest(key=key), self.assertRaises(ValueError):
                    _load_text_reviews(review, metadata, timeline)

    def test_live_review_requires_exact_session_and_captured_text(self):
        base = ROOT / ".runtime/metrics-unit-tests"
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            path = Path(directory)
            plan = path / "plan.json"
            plan.write_text(json.dumps({"blind_observer": {"identity": "blind"}, "cases": [{"id": "case", "segment_id": "kitchen_evidence"}]}), encoding="utf-8")
            metadata = {"test_id": "one", "revision": "abc", "source_identity": {"process_id": 123},
                        "assessment_plan": str(plan), "assessment_plan_sha256": file_hash(plan)}
            timeline = path / "visible-text-changes.jsonl"
            timeline.write_text(json.dumps({"scene_node": "kitchen_evidence/room", "entries": [{"path": "/p", "text": "Hello"}]}) + "\n", encoding="utf-8")
            document = {"schema_version": 1, "test_id": "one", "revision": "abc", "host_pid": 123,
                        "assessment_plan_sha256": file_hash(plan), "reviewer": "blind", "session_id": "session",
                        "case_id": "case", "segment_id": "kitchen_evidence", "monitor_elapsed_s": 1,
                        "path": "/p", "text": "Hello", "category": "dialogue", "english_verified": True}
            review = path / "visible-text-reviews.jsonl"
            review.write_text(json.dumps(document) + "\n", encoding="utf-8")
            self.assertTrue(_load_live_text_reviews(review, metadata, timeline)["kitchen_evidence"][("/p", "Hello")]["english_verified"])
            for key, value in (("test_id", "other"), ("revision", "other"), ("host_pid", 124), ("text", "other"), ("reviewer", "other")):
                review.write_text(json.dumps(dict(document, **{key: value})) + "\n", encoding="utf-8")
                with self.subTest(key=key), self.assertRaises(ValueError):
                    _load_live_text_reviews(review, metadata, timeline)

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
