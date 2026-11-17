"""Display-selection regressions for graphical MCP hosts."""
import subprocess
import unittest
from unittest.mock import patch

import linux_display


class DisplayProbeTests(unittest.TestCase):
    def test_missing_display_never_runs_probe(self):
        with patch.object(linux_display.subprocess, "run") as run:
            self.assertFalse(linux_display.display_available("x11", {}))
            run.assert_not_called()

    def test_stale_display_or_timeout_fails_closed(self):
        with patch.object(linux_display.subprocess, "run", side_effect=subprocess.TimeoutExpired("probe", 5)):
            self.assertFalse(linux_display.display_available("x11", {"DISPLAY": ":77"}))

    def test_successful_wayland_probe_is_available(self):
        with patch.object(linux_display.subprocess, "run") as run:
            run.return_value.returncode = 0
            self.assertTrue(linux_display.display_available("wayland", {"WAYLAND_DISPLAY": "wayland-0"}))


if __name__ == "__main__":
    unittest.main()
