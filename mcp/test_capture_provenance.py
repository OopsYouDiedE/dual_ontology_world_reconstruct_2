"""Capture regression: a wrong checkout must never produce accepted evidence."""
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import capture_provenance as capture


class CaptureProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve() / "project"
        self.root.mkdir()
        (self.root / "project.godot").write_text('[application]\nrun/main_scene="res://scenes/main/Boot.tscn"\n', encoding="utf-8")
        self.expected = capture.project_identity(self.root)
        self.source = dict(self.expected, process_id=1234, executable_path=str(self.root / "Godot.exe"),
                           launch_scene=self.expected["configured_main_scene"])

    def test_correct_host(self):
        self.assertEqual(capture.validate_source(self.source, self.expected, pid=1234,
            executable=self.root / "Godot.exe", launch_scene=self.source["launch_scene"]), self.source)

    def test_foreign_project_same_scene_rejected(self):
        foreign = dict(self.source, project_root=str(self.root.parent / "engine"))
        with self.assertRaisesRegex(ValueError, "root mismatch"):
            capture.validate_source(foreign, self.expected)

    def test_wrong_pid_executable_and_scene_rejected(self):
        for options in ({"pid": 5678}, {"executable": self.root / "other.exe"}, {"launch_scene": "res://wrong.tscn"}):
            with self.subTest(options=options), self.assertRaises(ValueError):
                capture.validate_source(self.source, self.expected, **options)

    def test_missing_and_forged_hash_rejected(self):
        for source in (None, {}, dict(self.source, project_sha256="0" * 64)):
            with self.subTest(source=source), self.assertRaises(ValueError):
                capture.validate_source(source, self.expected)

    def test_file_changed_mid_session_rejected(self):
        (self.root / "project.godot").write_text("changed", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "changed during capture"):
            capture.validate_source(self.source, self.expected)

    def test_startup_wrong_root_rejected(self):
        with self.assertRaisesRegex(ValueError, "MCP project root mismatch"):
            capture.assert_root(self.root, self.root.parent / "engine")

    def test_paths_bind_to_project_independent_of_cwd(self):
        with patch("pathlib.Path.cwd", return_value=self.root.parent):
            self.assertEqual(capture.project_path(".runtime/screens/test.png", self.root), self.root / ".runtime/screens/test.png")
            self.assertEqual(capture.project_path("res://.runtime/screens/test.png", self.root), self.root / ".runtime/screens/test.png")

    def test_escape_and_cross_project_outputs_rejected(self):
        for path in ("../engine/test.png", self.root.parent / "engine/test.png"):
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, "escapes"):
                capture.project_path(path, self.root)

    @unittest.skipUnless(os.name == "nt", "Windows path semantics")
    def test_incomplete_windows_paths_rejected(self):
        for path in (r"\tmp\shots\test.png", "C:relative.png"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                capture.project_path(path, self.root)

    @unittest.skipUnless(os.name == "nt", "Windows Godot launcher")
    def test_console_launcher_resolves_owned_host(self):
        console = self.root / "Godot_mono_console.exe"
        direct = self.root / "Godot_mono.exe"
        console.touch()
        with self.assertRaisesRegex(ValueError, "host executable.*missing"):
            capture.host_executable(console)
        direct.touch()
        self.assertEqual(capture.host_executable(console), str(direct))

    def test_external_content_supported(self):
        path = self.root.parent / "content.dv"
        self.assertEqual(capture.project_path(path, self.root, allow_external=True), path)

    def test_user_storage_is_rejected(self):
        with self.assertRaises(ValueError):
            capture.project_path("user://screens/test.png", self.root)

    def test_png_sidecar_binds_hash_and_identity(self):
        image = self.root / "test.png"
        image.write_bytes(b"test PNG bytes")
        capture.save_image_sidecar(image, {"source_identity": self.source, "session_id": "test"})
        metadata = json.loads(image.with_suffix(".png.json").read_text(encoding="utf-8"))
        self.assertEqual(metadata["image_sha256"], hashlib.sha256(image.read_bytes()).hexdigest())
        self.assertEqual(metadata["source_identity"], self.source)

    def test_tampered_png_rejected(self):
        image = self.root / "test.png"
        image.write_bytes(b"original")
        capture.save_image_sidecar(image, {"source_identity": self.source})
        image.write_bytes(b"altered")
        with self.assertRaisesRegex(ValueError, "image hash mismatch"):
            capture.verify_image(image, self.root)

    def test_missing_sidecar_rejected(self):
        image = self.root / "test.png"
        image.write_bytes(b"original")
        with self.assertRaisesRegex(ValueError, "sidecar is missing"):
            capture.verify_image(image, self.root)

    def test_fixture_requires_explicit_selection(self):
        image = self.root / "test.png"
        image.write_bytes(b"original")
        capture.save_image_sidecar(image, {"source_identity": self.source})
        sidecar = image.with_suffix(".png.json")
        metadata = json.loads(sidecar.read_text(encoding="utf-8"))
        metadata["acceptance_eligible"] = False
        sidecar.write_text(json.dumps(metadata), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "fixture"):
            capture.verify_image(image, self.root)
        self.assertTrue(capture.verify_image(image, self.root, allow_fixture=True)["provenance_valid"])


if __name__ == "__main__":
    unittest.main()
