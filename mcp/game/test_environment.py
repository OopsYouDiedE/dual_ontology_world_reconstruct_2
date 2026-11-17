"""Tests for project-local cross-platform engine discovery."""
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import environment


class EnvironmentDiscoveryTests(unittest.TestCase):
    def test_shared_checkout_ignores_other_operating_systems_binary(self):
        with tempfile.TemporaryDirectory() as temporary:
            local = Path(temporary)
            base = local / "godot" / environment.VERSION
            base.mkdir(parents=True)
            windows = base / "Godot_v4.7.2-stable_mono_win64_console.exe"
            linux = base / "linux" / "Godot_v4.7.2-stable_mono_linux.x86_64"
            linux.parent.mkdir()
            windows.touch()
            linux.touch()
            with patch.object(environment, "LOCAL", local), patch.object(environment.shutil, "which", return_value=None), patch.dict(os.environ, {"DV_GODOT": ""}):
                candidates = list(environment.godot_candidates())
            self.assertIn(windows if os.name == "nt" else linux, candidates)
            self.assertNotIn(linux if os.name == "nt" else windows, candidates)


if __name__ == "__main__":
    unittest.main()
