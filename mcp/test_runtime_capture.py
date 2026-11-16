"""Movie output reservations must survive neither invalid input nor failed startup."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent / "game"))
import runtime


class MovieReservationTests(unittest.TestCase):
    def setUp(self):
        local_temp = runtime.ROOT / ".runtime"
        local_temp.mkdir(exist_ok=True)
        temporary = tempfile.TemporaryDirectory(dir=local_temp)
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        (self.root / "project.godot").write_text(
            '[application]\nrun/main_scene="res://scenes/main/Boot.tscn"\n', encoding="utf-8")
        patcher = patch.object(runtime, "ROOT", self.root)
        patcher.start()
        self.addCleanup(patcher.stop)
        # The fixture tests reservation behaviour only. The separate isolation
        # test below exercises the real guard without mocking it.
        guard = patch.object(runtime.provenance, "assert_runtime_root", return_value=self.root)
        guard.start()
        self.addCleanup(guard.stop)
        self.arguments = {"mode": "godot_manual", "movie_filename": "capture.avi"}
        self.movie = self.root / "artifacts/recordings/capture.avi"

    def test_missing_snapshot_does_not_reserve_movie(self):
        with patch.object(runtime, "build") as build:
            with self.assertRaisesRegex(ValueError, "Snapshot file does not exist"):
                runtime.start(dict(self.arguments, snapshot_path="missing.json"))
            build.assert_not_called()
        self.assertFalse(self.movie.exists())

    def test_failed_startup_releases_empty_reservation(self):
        def fail_build(*_):
            self.assertTrue(self.movie.is_file())
            self.assertEqual(self.movie.stat().st_size, 0)
            raise RuntimeError("fixture build failure")

        with patch.object(runtime, "build", side_effect=fail_build):
            with self.assertRaisesRegex(RuntimeError, "fixture build failure"):
                runtime.start(self.arguments)
        self.assertFalse(self.movie.exists())

    def test_existing_recording_is_preserved(self):
        self.movie.parent.mkdir(parents=True)
        self.movie.write_bytes(b"existing recording")
        with patch.object(runtime, "build") as build:
            with self.assertRaisesRegex(ValueError, "already exists"):
                runtime.start(self.arguments)
            build.assert_not_called()
        self.assertEqual(self.movie.read_bytes(), b"existing recording")


class RuntimeIsolationTests(unittest.TestCase):
    def test_foreign_root_is_rejected_before_host_or_output_creation(self):
        local_temp = runtime.ROOT / ".runtime"
        local_temp.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=local_temp) as directory:
            foreign = Path(directory).resolve()
            (foreign / "project.godot").write_text(
                '[application]\nrun/main_scene="res://scenes/main/Boot.tscn"\n', encoding="utf-8")
            with patch.object(runtime, "ROOT", foreign), \
                 patch.object(runtime, "build") as build, \
                 patch.object(runtime, "Endpoint") as endpoint:
                with self.assertRaisesRegex(ValueError, "Unauthorized runtime project root"):
                    runtime.start({"mode": "godot_manual", "movie_filename": "capture.avi"})
                build.assert_not_called()
                endpoint.assert_not_called()
            self.assertFalse((foreign / "artifacts").exists())


if __name__ == "__main__":
    unittest.main()
