"""Regression tests for whole-test score projection and the shipped report."""
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).parent))
import test_results as results


class ResultBatches(unittest.TestCase):
    def event(self, name, at, values):
        return dict(event_id=name, segment_id='wake', revision='abc1234', at=at,
                    test_result=dict(test_id=name, scores=dict(zip(results.CATEGORIES, values)),
                                     reasons={key: 'Measured in ' + name for key in results.CATEGORIES}))

    def test_latest_batch_never_borrows_missing_values(self):
        old = self.event('old', '2026-11-17T01:00:00+00:00', [9] * 7)
        new = self.event('new', '2026-11-17T02:00:00+00:00', [6, None, 8, 7, 5, 4, 9])
        latest = results.latest_by_segment(results.collect([], [new, old]))['wake']
        self.assertEqual(latest['scores'], [6, 0, 8, 7, 5, 4, 9])
        self.assertEqual(latest['provisional_categories'], ['text_density'])
        self.assertIn('Provisional 0', latest['reasons'][1])
        self.assertEqual(latest['id'], 'new')
        self.assertEqual(latest['status'], '已测 · 测试未完成')

    def test_legacy_single_score_does_not_merge_with_another_test(self):
        events = [dict(event_id=str(i), segment_id='wake', revision='abc1234',
                       at=f'2026-11-17T0{i}:00:00+00:00',
                       development_score=dict(category=key, score=8))
                  for i, key in enumerate(results.CATEGORIES)]
        latest = results.latest_by_segment(results.collect([], events))['wake']
        self.assertEqual(latest['scores'], [0] * 6 + [8])
        self.assertEqual(len(latest['provisional_categories']), 6)
        self.assertTrue(all(latest['reasons']))

    def test_observed_zero_is_distinct_from_missing_evidence(self):
        event = self.event('zero', '2026-11-17T01:00:00+00:00', [0, 8, 8, 8, 8, 8, 8])
        result = results.collect([], [event])[0]
        self.assertEqual(result['status'], '不合格')
        self.assertEqual(result['provisional_categories'], [])
        self.assertNotIn('Provisional 0', result['reasons'][0])

    def test_all_dimensions_visible_and_html_escaped(self):
        r = results.collect([], [self.event('one', '2026-11-17T01:00:00+00:00', [8] * 7)])[0]
        r['reasons'][0] = '<script>alert(1)</script>'
        scene = dict(id='wake', label='Opening')
        html = results.card(scene, r, None, None, None, None)
        self.assertEqual(html.count('data-result-category='), 7)
        self.assertIn('&lt;script&gt;', html)
        self.assertNotIn('<script>', html)
        for phrase in ('非正式', '开发测试', '正式验收', '历史'):
            self.assertNotIn(phrase, html)
        self.assertEqual(r['status'], '合格')

    def test_missing_and_blocked_results(self):
        r = results.collect([], [self.event('one', '2026-11-17T01:00:00+00:00', [8] * 6 + [None])])[0]
        self.assertEqual(r['status'], '已测 · 测试未完成')
        self.assertIn('暂定·缺证据', results.card(dict(id='wake', label='Opening'), r, None, None, None, None))
        review = dict(id='blocked', segment_id='wake', revision='abc1234',
                      observed_at=r['at'], scores=[8] * 7, score_reasons=['Observed'] * 7,
                      report='report.md', status='blocked')
        self.assertEqual(results.collect([review], [])[0]['status'], '不合格')

    def test_shipped_pages_have_no_archive_or_test_hierarchy(self):
        root = Path(__file__).resolve().parents[2] / 'artifacts/review'
        for name in ('index.html',):
            html = (root / name).read_text(encoding='utf-8')
            for phrase in ('archive.html', '非正式', '开发测试', '正式验收', 'live-progress"', '修改记录'):
                self.assertNotIn(phrase, html)
            self.assertEqual(html.count('data-test-segment='), 11)
        data = json.loads((root / 'score_records.json').read_text(encoding='utf-8'))
        for entry in data['gameplay_scenes']:
            self.assertEqual(len(entry['scores']), 7)
            if entry['test']:
                self.assertEqual(entry['scores'], entry['test']['scores'])


if __name__ == '__main__':
    unittest.main()
