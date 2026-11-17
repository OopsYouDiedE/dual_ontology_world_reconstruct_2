"""Live listening previews preserve the captured PCM and report skipped audio."""
import array
import base64
import io
import json
from pathlib import Path
import tempfile
import unittest
import wave

from audio_observation import read_excerpt


class AudioObservationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / 'audio.json').write_text(json.dumps({'sample_rate': 8000}))

    def test_reads_incremental_stereo_samples_as_playable_wav(self):
        (self.root / 'mix.f32le').write_bytes(array.array('f', [0.0, 0.5, -1.0, 1.0]).tobytes())
        info, cursor, encoded = read_excerpt(self.root, 0)
        self.assertEqual((info['start_frame'], info['end_frame'], info['skipped_frames']), (0, 2, 0))
        with wave.open(io.BytesIO(base64.b64decode(encoded)), 'rb') as wav:
            self.assertEqual((wav.getnchannels(), wav.getframerate(), wav.getnframes()), (2, 8000, 2))
        again, following, audio = read_excerpt(self.root, cursor)
        self.assertFalse(again['available']); self.assertEqual(following, cursor); self.assertIsNone(audio)

    def test_backlog_is_bounded_and_explicit(self):
        (self.root / 'mix.f32le').write_bytes(array.array('f', [0.0, 0.0] * 8000).tobytes())
        info, cursor, encoded = read_excerpt(self.root, 0, max_seconds=0.25)
        self.assertEqual(info['skipped_frames'], 6000)
        self.assertEqual((info['start_frame'], info['end_frame']), (6000, 8000))
        self.assertEqual(cursor, 8000 * 8); self.assertTrue(encoded)

    def test_missing_capture_is_explicit(self):
        info, cursor, encoded = read_excerpt(self.root, 0)
        self.assertFalse(info['available']); self.assertIn('reason', info)
        self.assertEqual(cursor, 0); self.assertIsNone(encoded)


if __name__ == '__main__': unittest.main()
