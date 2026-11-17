"""Live browser readers may briefly hold a Windows file handle."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import core


class LiveIoTests(unittest.TestCase):
    def test_projection_retries_sharing_violation(self):
        replace = core.os.replace
        attempts = []

        def busy_once(source, target):
            attempts.append(source)
            if len(attempts) == 1:
                raise PermissionError('browser reader')
            replace(source, target)

        with tempfile.TemporaryDirectory(dir=core.ROOT / '.runtime') as directory:
            target = Path(directory) / 'live.js'
            with patch.object(core.os, 'replace', side_effect=busy_once), patch.object(core.time, 'sleep'):
                core.atomic_write(target, 'complete')
            self.assertEqual(target.read_text(), 'complete')
            self.assertEqual(list(Path(directory).iterdir()), [target])


if __name__ == '__main__':
    unittest.main()
