"""Regression tests for objective telemetry and score evidence handling."""
import unittest

from audio_watch import update_metadata
from mainline_metrics import audio_score, frame_statistics, route_for_intervals


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

    def test_background_measured_failure_and_multitrack_upper_bound(self):
        mix = dict(status="complete", signal_present=True, integrated_lufs=-25, true_peak_dbtp=-10)
        isolated = dict(complete=True, signal_present=True, measured_peak_dbtp=-20.0, peak_upper_bound_dbtp=-20.0)
        self.assertEqual(audio_score(mix, isolated)[0], 6)
        mix["true_peak_dbtp"] = -21
        self.assertEqual(audio_score(mix, isolated)[0], 6)
        mix["true_peak_dbtp"] = -10
        isolated["measured_peak_dbtp"] = -21
        isolated["peak_upper_bound_dbtp"] = -21
        self.assertEqual(audio_score(mix, isolated)[0], 8)
        combined_upper_bound = dict(complete=True, signal_present=True, peak_upper_bound_dbtp=-15)
        self.assertIsNone(audio_score(mix, combined_upper_bound)[0])
        isolated["complete"] = False
        self.assertIsNone(audio_score(mix, isolated)[0])
        mix["signal_present"] = False
        isolated["complete"] = True
        self.assertIsNone(audio_score(mix, isolated)[0])

    def test_route_changes_only_invalidate_overlapping_scenes(self):
        one = {"buses": {"Master": {"volume_db": 0}}}
        two = {"buses": {"Master": {"volume_db": -3}}}
        route = {"stable": False, "changes": [{"elapsed_s": 0, "snapshot": one},
                 {"elapsed_s": 10, "snapshot": two}]}
        self.assertEqual(route_for_intervals(route, [[1, 5]])["snapshot"], one)
        self.assertEqual(route_for_intervals(route, [[11, 15]])["snapshot"], two)
        self.assertEqual(route_for_intervals(route, [[9, 11]]), {})
        self.assertEqual(route_for_intervals(route, [[1, 5], [11, 15]]), {})
        self.assertEqual(route_for_intervals(route, [[10.02, 11]]), {})
        self.assertEqual(route_for_intervals({"stable": False}, [[1, 5]]), {})

    def test_frame_statistics_include_tail_and_threshold(self):
        stats = frame_statistics([10.0] * 99 + [40.0])
        self.assertEqual(stats["frame_samples"], 100)
        self.assertEqual(stats["spikes_over_33_3_ms"], 1)
        self.assertEqual(stats["frame_p99_ms"], 10.0)
        self.assertEqual(stats["low_1_fps"], 25.0)
        self.assertAlmostEqual(stats["avg_fps"], 100000 / 1030)


if __name__ == "__main__":
    unittest.main()
