"""Regression checks for the explicit portable review export."""
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/testing'))
import publish_review_snapshot as snapshot
import test_results


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

    def test_snapshot_does_not_overwrite_full_or_published_review(self):
        for output in (snapshot.review.OUT, snapshot.review.OUT / 'published'):
            with self.subTest(output=output), self.assertRaises(ValueError):
                snapshot.publish(snapshot.review.OUT / 'score_records.json', output)

    def test_schema3_whole_test_with_image_and_missing_score(self):
        with tempfile.TemporaryDirectory(dir=ROOT / '.runtime') as temporary:
            base = Path(temporary)
            image = base / 'capture.png'
            image.write_bytes(b'test image evidence')
            digest = hashlib.sha256(image.read_bytes()).hexdigest()
            scores = [9, 8, None, 7, 6, 8, 10]
            result = dict(id='run-1', segment_id='wake', revision='abc1234',
                          at='2026-11-17T10:00:00+08:00', status='不合格', scores=scores,
                          reasons=['reason <one>'] * 7,
                          images=[dict(path=str(image), sha256=digest, caption='Screen <1>')],
                          evidence=[str(image)])
            data = dict(schema_version=3, dimensions=list(test_results.LABELS), revision='abc1234',
                        gameplay_scenes=[dict(id='wake', label='Opening', scores=scores, test=result),
                                         dict(id='other', label='Other', scores=[None] * 7, test=None)])
            source, output = base / 'records.json', base / 'portable'
            source.write_text(json.dumps(data), encoding='utf-8')
            self.assertGreater(snapshot.publish(source, output), 0)
            html = (output / 'index.html').read_text(encoding='utf-8')
            md = (output / 'scoring_overview.md').read_text(encoding='utf-8')
            self.assertFalse((output / 'gameplay.html').exists())
            self.assertIn('run-1', html)
            self.assertIn('9/10', html)
            self.assertIn('未测', html)
            self.assertIn('reason &lt;one&gt;', html)
            self.assertIn('Screen &lt;1&gt;', html)
            self.assertIn('run-1', md)
            self.assertEqual(html.count('data-result-category='), 7)
            self.assertTrue((output / 'images' / (digest + '.png')).is_file())
            for word in ('正式', '开发', '历史'):
                self.assertNotIn(word, html)
                self.assertNotIn(word, md)
            result['scores'] = [10] * 7
            source.write_text(json.dumps(data), encoding='utf-8')
            with self.assertRaises(ValueError):
                snapshot.publish(source, output)
            result['scores'] = scores
            result['images'][0]['sha256'] = '0' * 64
            source.write_text(json.dumps(data), encoding='utf-8')
            with self.assertRaises(ValueError):
                snapshot.publish(source, output)


if __name__ == '__main__':
    unittest.main()
