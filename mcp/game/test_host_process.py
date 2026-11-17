"""Regression checks for platform-specific .NET host selection."""
import os
from pathlib import Path
import unittest
from unittest.mock import patch

import environment
import host_process


class SpawnEnvironmentTests(unittest.TestCase):
    def test_selected_sdk_controls_dotnet_root(self):
        executable = Path(host_process.ROOT) / "sdk-native" / ("dotnet.exe" if os.name == "nt" else "dotnet")
        with patch.object(environment, "resolve_dotnet", return_value=str(executable)), \
             patch.object(host_process.provenance, "assert_runtime_root"), \
             patch.object(host_process.linux_display, "environment", side_effect=lambda env: env), \
             patch.object(host_process.subprocess, "Popen") as popen:
            host_process.spawn(["godot", "--path", host_process.ROOT])
        env = popen.call_args.kwargs["env"]
        self.assertEqual(env["DOTNET_ROOT"], str(executable.parent))
        self.assertEqual(env["PATH"].split(os.pathsep)[0], str(executable.parent))

    def test_invalid_inherited_root_is_removed_if_no_sdk(self):
        with patch.dict(os.environ, {"DOTNET_ROOT": "wrong-os-root"}), \
             patch.object(environment, "resolve_dotnet", return_value=None), \
             patch.object(host_process.provenance, "assert_runtime_root"), \
             patch.object(host_process.subprocess, "Popen") as popen:
            host_process.spawn(["other"])
        self.assertNotIn("DOTNET_ROOT", popen.call_args.kwargs["env"])


if __name__ == "__main__":
    unittest.main()
