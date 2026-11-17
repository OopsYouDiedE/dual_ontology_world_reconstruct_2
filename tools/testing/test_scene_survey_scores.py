"""Tests for bounded, evidence-backed scene scoring and aggregation."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import yaml

import scene_survey_scores as scoring


class SceneSurveyScoresTests(unittest.TestCase):
    def setUp(self):
        base = scoring.ROOT / ".runtime" / "scene-score-unit-tests"
        base.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=base)
        self.addCleanup(self.temp.cleanup)
        self.run = Path(self.temp.name)
        self.job = "survey-test-case"
        self.case = self.run / self.job / "test-case"
        self.metrics = self.case / "metrics"
        self.metrics.mkdir(parents=True)
        self.row = {"state": "passed", "segment_id": "wake", "host_pid": 123, "detail": {"room": "R05"}}
        self.doc = {"metadata": {"case_id": "test-case", "measurement_context": "rendered_runtime", "source_identity": {}},
                    "summary": {"audio_discarded_frames": 0, "audio_writer": {"error": 0}}, "timeline": []}
        self.save_timeline()
        (self.metrics / "frames.csv").write_text("frame_ms,measurement_phase\n400,loading_warmup\n16,steady\n20,steady\n", encoding="utf-8")
        self.audio = {"status": "complete", "signal_present": True, "integrated_lufs": -24, "true_peak_dbtp": -25}
        (self.metrics / "audio.json").write_text(json.dumps(self.audio), encoding="utf-8")
        self.patches = [patch.object(scoring.provenance, "project_identity", return_value={}),
                        patch.object(scoring.provenance, "validate_source")]
        for p in self.patches: p.start(); self.addCleanup(p.stop)

    def save_timeline(self):
        (self.metrics / "timeline.yaml").write_text(yaml.safe_dump(self.doc), encoding="utf-8")

    def score(self):
        return scoring.score_case(self.run, self.job, self.row, "revision")

    def test_warmup_excluded_and_unclassified_text_left_missing(self):
        result = self.score()
        self.assertEqual(result["scores"]["fluidity"], 8)
        self.assertEqual(result["scores"]["audio_loudness"], 8)
        self.assertIsNone(result["scores"]["text_density"])
        self.assertEqual(result["metrics"]["steady_frames"]["frame_samples"], 2)
        self.assertEqual(len(result["scores"]), 7)

    def test_steady_spike_fails_even_when_case_incomplete(self):
        (self.metrics / "frames.csv").write_text("frame_ms,measurement_phase\n40,steady\n", encoding="utf-8")
        self.row["state"] = "failed"
        result = self.score()
        self.assertEqual(result["scores"]["fluidity"], 6)
        self.assertIsNone(result["scores"]["audio_loudness"])

    def test_lost_audio_or_missing_final_summary_is_not_scored(self):
        self.doc["summary"]["audio_discarded_frames"] = 1
        self.save_timeline()
        self.assertIsNone(self.score()["scores"]["audio_loudness"])
        del self.doc["summary"]
        self.save_timeline()
        self.assertIsNone(self.score()["scores"]["fluidity"])

    def test_conservative_aggregation(self):
        first = self.score()
        second = self.score()
        second["case_id"] = "another"
        second["scores"]["fluidity"] = None
        combined = scoring.aggregate([first, second])["wake"]
        self.assertIsNone(combined["scores"]["fluidity"])
        first["scores"]["fluidity"] = 6
        combined = scoring.aggregate([first, second])["wake"]
        self.assertEqual(combined["scores"]["fluidity"], 6)
        self.assertIn("another", combined["reasons"]["fluidity"])

    def test_independent_assessment_requires_supported_category_reason_evidence(self):
        evidence = self.case / "review.txt"
        evidence.write_text("independent review", encoding="utf-8")
        review = {"action_sfx_integrity": {"score": 6, "reason": "Visible overlap", "evidence": [str(evidence)]}}
        result = scoring.score_case(self.run, self.job, self.row, "revision", review)
        self.assertEqual(result["scores"]["action_sfx_integrity"], 6)
        with self.assertRaises(ValueError):
            scoring.score_case(self.run, self.job, self.row, "revision", {"fluidity": review["action_sfx_integrity"]})
        review["action_sfx_integrity"]["evidence"] = []
        with self.assertRaises(ValueError):
            scoring.score_case(self.run, self.job, self.row, "revision", review)

    def test_collect_requires_completed_unchanged_run(self):
        path = self.run / "status.json"
        status = {"profile": "scene_survey", "state": "running", "run_id": "run", "revision": "abc", "jobs": {self.job: self.row}}
        path.write_text(json.dumps(status), encoding="utf-8")
        with self.assertRaises(ValueError): scoring.collect(self.run)
        status.update(state="blocked", source_changed_during_run=True)
        path.write_text(json.dumps(status), encoding="utf-8")
        with self.assertRaises(ValueError): scoring.collect(self.run)
        status["source_changed_during_run"] = False
        path.write_text(json.dumps(status), encoding="utf-8")
        self.assertEqual(len(scoring.collect(self.run)["cases"]), 1)


if __name__ == "__main__":
    unittest.main()
