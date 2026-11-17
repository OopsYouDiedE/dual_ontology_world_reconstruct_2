import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch

import concurrency_observer as observer


class ObserverTests(unittest.TestCase):
    def test_process_observations_and_saved_summary(self):
        processes = [type("P", (), {"info": {"pid": pid, "name": name}})()
                     for pid, name in [(4, "Godot.exe"), (5, "godot.other"), (6, "other")]]
        instance = observer.ConcurrencyObserver(4, interval=0.01)
        with patch.object(observer.psutil, "process_iter", return_value=processes), \
             patch.object(observer.psutil, "cpu_percent", return_value=12.0), \
             patch.object(observer.psutil, "virtual_memory", return_value=type("M", (), {"available": 1024})()):
            sampled = threading.Event()
            original = instance._sample
            def sample():
                result = original()
                sampled.set()
                return result
            instance._sample = sample
            instance.start()
            self.assertTrue(sampled.wait(2))
            with tempfile.TemporaryDirectory() as directory:
                path = instance.stop(directory)
                result = json.loads(Path(path).read_text(encoding="utf-8"))
        self.assertTrue(result["sampler_stopped"])
        self.assertEqual(result["observed_godot_pids"], [4, 5])
        self.assertEqual(result["peak_observed_godot_processes"], 2)
        self.assertEqual(result["samples"][0]["available_memory_bytes"], 1024)

    def test_failure_is_recorded_and_thread_stops(self):
        instance = observer.ConcurrencyObserver(1, interval=0.01)
        failed = threading.Event()
        def fail():
            failed.set()
            raise OSError("unavailable")
        instance._sample = fail
        instance.start()
        self.assertTrue(failed.wait(2))
        with tempfile.TemporaryDirectory() as directory:
            result = json.loads(instance.stop(directory).read_text(encoding="utf-8"))
        self.assertGreaterEqual(result["sampling_failures"], 1)
        self.assertIsNone(result["peak_observed_godot_processes"])
        self.assertTrue(result["sampler_stopped"])


if __name__ == "__main__":
    unittest.main()
