"""Windows report readers must survive brief sharing violations."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import common as c


class ReportIoTests(unittest.TestCase):
    def test_read_retries_sharing_violation(self):
        with patch.object(c, "project_path", return_value=Path("status.json")), \
             patch.object(Path, "read_text", side_effect=[PermissionError("shared"), '{"state":"running"}']), \
             patch.object(c.time, "sleep"):
            self.assertEqual(c.read_json("status.json"), {"state": "running"})

    def test_read_persistent_error_remains_visible(self):
        with patch.object(c, "project_path", return_value=Path("status.json")), \
             patch.object(Path, "read_text", side_effect=PermissionError("denied")), \
             patch.object(c.time, "sleep"):
            with self.assertRaises(PermissionError): c.read_json("status.json")

    def test_atomic_replace_retries_and_removes_temporary_file(self):
        original = c.os.replace
        calls = []
        def replace(source, destination):
            calls.append(source)
            if len(calls) == 1: raise PermissionError("reader holds file")
            original(source, destination)
        with tempfile.TemporaryDirectory(dir=c.ROOT / ".runtime") as directory:
            output = Path(directory) / "status.json"
            with patch.object(c.os, "replace", side_effect=replace), patch.object(c.time, "sleep"):
                c.write_json(output, {"state": "completed"})
            self.assertEqual(json.loads(output.read_text()), {"state": "completed"})
            self.assertEqual(list(Path(directory).iterdir()), [output])


if __name__ == "__main__":
    unittest.main()
