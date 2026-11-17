import json
import tempfile
import unittest
from pathlib import Path
from audio_cue_observation import read_cues

ROOT = Path(__file__).resolve().parents[2]


class CueObservationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=ROOT / ".runtime")
        self.directory = Path(self.tmp.name)
        self.path = self.directory / "audio-cues.jsonl"

    def tearDown(self):
        self.tmp.cleanup()

    def test_missing_and_incremental_records(self):
        result, cursor = read_cues(self.directory)
        self.assertFalse(result["available"])
        self.assertEqual(cursor, 0)
        records = [
            {"type": "configuration", "audibility": "not determined"},
            {"type": "scheduled", "elapsed_s": 1.25, "frame": 75, "sequence": 1, "category": "spatial_effect"},
        ]
        self.path.write_text("".join(json.dumps(item) + "\n" for item in records), encoding="utf-8")
        result, cursor = read_cues(self.directory, limit=1)
        self.assertTrue(result["more"])
        self.assertEqual(result["events"], records[:1])
        result, cursor = read_cues(self.directory, cursor)
        self.assertEqual(result["events"], records[1:])
        self.assertFalse(result["more"])
        self.assertEqual(read_cues(self.directory, cursor)[0]["events"], [])

    def test_partial_line_is_retried(self):
        self.path.write_bytes(b'{"type":"scheduled",')
        result, cursor = read_cues(self.directory)
        self.assertEqual(cursor, 0)
        self.assertTrue(result["more"])
        with self.path.open("ab") as output:
            output.write(b'"category":"global_effect","elapsed_s":1.0,"frame":2,"sequence":1}\n')
        result, cursor = read_cues(self.directory, cursor)
        self.assertEqual(result["events"][0]["category"], "global_effect")
        self.assertGreater(cursor, 0)

    def test_invalid_or_truncated_collection_is_explicit(self):
        self.path.write_text('{"type":"scheduled","category":"story_truth"}\n', encoding="utf-8")
        result, cursor = read_cues(self.directory)
        self.assertFalse(result["available"])
        self.assertEqual(cursor, 0)
        self.path.write_text("", encoding="utf-8")
        self.assertIn("truncated", read_cues(self.directory, 4)[0]["reason"])


if __name__ == "__main__": unittest.main()
