"""Regression tests for objective telemetry and score evidence handling."""
import unittest

from audio_watch import update_metadata
from mainline_metrics import audio_score, frame_statistics


class ObjectiveTelemetryTests(unittest.TestCase):
    def test_zero_db_peak_is_retained_after_quieter_blocks(self):
        state = {}
        for line in ("lavfi.r128.true_peak=1.0", "lavfi.r128.sample_peak=1.0",
                     "lavfi.r128.true_peak=0.5", "lavfi.r128.sample_peak=0.5"):
            self.assertTrue(update_metadata(state, line))
        self.assertEqual(state["true_peak_dbtp"], 0.0)
        self.assertEqual(state["sample_peak_dbfs"], 0.0)
        self.assertTrue(state["signal_present"])
        state.update(status="complete", integrated_lufs=-25)
        self.assertEqual(audio_score(state)[0], 6)

    def test_clipping_does_not_require_integrated_loudness(self):
        state = dict(status="complete", signal_present=True, true_peak_dbtp=0.0)
        self.assertEqual(audio_score(state), (6, "Digital true-peak clipping"))
        state["status"] = "error"
        self.assertIsNone(audio_score(state)[0])

    def test_missing_or_boolean_measurements_stay_pending(self):
        for lufs, peak in [(None, -21), (-25, None), (True, -21), (-25, False)]:
            state = dict(status="complete", signal_present=True, integrated_lufs=lufs, true_peak_dbtp=peak)
            self.assertIsNone(audio_score(state)[0])

    def test_frame_statistics_include_tail_and_threshold(self):
        stats = frame_statistics([10.0] * 99 + [40.0])
        self.assertEqual(stats["frame_samples"], 100)
        self.assertEqual(stats["spikes_over_33_3_ms"], 1)
        self.assertEqual(stats["frame_p99_ms"], 10.0)
        self.assertEqual(stats["low_1_fps"], 25.0)
        self.assertAlmostEqual(stats["avg_fps"], 100000 / 1030)


if __name__ == "__main__":
    unittest.main()
