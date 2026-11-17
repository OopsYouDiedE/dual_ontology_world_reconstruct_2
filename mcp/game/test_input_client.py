"""Focused tests for the persistent input client's retained media."""
import base64
from pathlib import Path
import tempfile
import unittest
from types import SimpleNamespace

from input_client import ALLOWED, NOTE_TOOLS, ROOT, retain_audio


class InputClientTests(unittest.TestCase):
    def test_supported_note_tools(self):
        self.assertEqual(NOTE_TOOLS, {"event_script", "character_script", "charactor_script", "review_visible_text"})
        self.assertTrue(NOTE_TOOLS <= ALLOWED)

    def test_wav_is_retained_with_metadata(self):
        sample = b"RIFF-test-wave"
        block = SimpleNamespace(mimeType="audio/wav", data=base64.b64encode(sample).decode("ascii"))
        with tempfile.TemporaryDirectory(dir=ROOT / ".runtime") as directory:
            result = retain_audio(block, Path(directory), 12, 0)
            self.assertEqual(Path(result["path"]).read_bytes(), sample)
            self.assertEqual(result["mime_type"], "audio/wav")
            self.assertEqual(result["bytes"], len(sample))

    def test_rejects_wrong_type_and_corrupt_base64(self):
        with tempfile.TemporaryDirectory(dir=ROOT / ".runtime") as directory:
            for block in (SimpleNamespace(mimeType="audio/ogg", data="AA=="),
                          SimpleNamespace(mimeType="audio/wav", data="%%%")):
                with self.assertRaises(ValueError):
                    retain_audio(block, Path(directory), 1, 0)
            self.assertEqual(list(Path(directory).iterdir()), [])


if __name__ == "__main__":
    unittest.main()
