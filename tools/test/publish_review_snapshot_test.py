"""Regression checks for the portable review snapshot."""
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/testing'))
import publish_review_snapshot as snapshot


class PortableReviewTest(unittest.TestCase):
    def test_frame_selection(self):
        self.assertEqual(snapshot.select_frames([0, 1, 2, 3, 4]), [0, 2, 4])
        self.assertEqual(snapshot.select_frames([0, 1]), [0, 1])

    def test_link_validation_rejects_missing_and_escaped_paths(self):
        with tempfile.TemporaryDirectory(dir=ROOT / '.runtime') as temporary:
            output = Path(temporary)
            page = output / 'index.html'
            page.write_text('<a href="missing.html">missing</a>', encoding='utf-8')
            with self.assertRaises(ValueError):
                snapshot.validate(output)
            page.write_text('<a href="../outside.html">outside</a>', encoding='utf-8')
            with self.assertRaises(ValueError):
                snapshot.validate(output)
            page.write_text('<a href="#section">ok</a><p id="section">ok</p>', encoding='utf-8')
            self.assertEqual(snapshot.validate(output), 1)

    def test_snapshot_does_not_overwrite_full_review(self):
        with self.assertRaises(ValueError):
            snapshot.publish(snapshot.review.OUT / 'score_records.json', snapshot.review.OUT)


if __name__ == '__main__':
    unittest.main()
