"""Regression coverage for audited, segment-local development telemetry."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import export_review_site as site


class StructuredDevelopmentTelemetryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=site.ROOT)
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'segment-metrics.json'
        self.relative = self.path.relative_to(site.ROOT).as_posix()
        self.event = dict(event_id='e', kind='check', segment_id='wake',
                          summary='Runtime capture', result='Completed', revision='abc',
                          evidence=[self.relative])
        self.document = {'schema_version': 1, 'segments': {
            'wake': {'steady': {'frame_samples': 100, 'avg_fps': 60,
                                'frame_p95_ms': 18.25, 'frame_p99_ms': 20,
                                'spikes_over_33_3_ms': 0},
                     'audio': {'status': 'complete', 'signal_present': True,
                               'integrated_lufs': -38.26, 'true_peak_dbtp': -22.6}},
            'other': {'steady': {'frame_samples': 1, 'avg_fps': 999}}}}

    def audit(self):
        self.path.write_text(json.dumps(self.document), encoding='utf-8')
        digest = hashlib.sha256(self.path.read_bytes()).hexdigest()
        self.event['evidence_sha256'] = [{'path': self.relative, 'sha256': digest}]
        return site.audit_progress({'events': [self.event]})

    def test_numeric_metrics_in_correct_dimensions_and_formal_scores_unchanged(self):
        dimensions = site.development_dimensions([self.event], self.audit())
        self.assertEqual([i for i, items in enumerate(dimensions) if items], [0, 3])
        self.assertIn('P95 18.25 ms', dimensions[0][0]['text'])
        self.assertIn('spikes >33.3 ms 0', dimensions[0][0]['text'])
        self.assertIn('Integrated -38.26 LUFS', dimensions[3][0]['text'])
        self.assertNotIn('999', str(dimensions))
        html = site.dimension_scores({}, development=dimensions, page=site.OUT / 'index.html')
        self.assertEqual(html.count('<b class="primary-score">待评</b>'), 7)
        self.assertIn('True peak -22.6 dBTP', html)
        self.assertEqual(site.review_result({}), '待评')

    def test_repeated_events_with_same_measurements_are_deduplicated(self):
        audit = self.audit()
        second = dict(self.event, event_id='second', summary='Same run repeated')
        audit['events']['second'] = list(audit['events']['e'])
        dimensions = site.development_dimensions([self.event, second], audit)
        self.assertEqual(len([x for x in dimensions[0] if x.get('structured')]), 1)
        self.assertEqual(len([x for x in dimensions[3] if x.get('structured')]), 1)
        self.assertEqual(dimensions[0][0]['event_id'], 'second')

    def test_changed_missing_and_unverified_evidence_never_extracted(self):
        audit = self.audit()
        self.path.write_text('{}', encoding='utf-8')
        self.assertEqual(site.development_dimensions([self.event], audit), [[] for _ in site.DIMENSIONS])
        for status in ('changed', 'missing', 'unverified'):
            audit['events']['e'][0]['status'] = status
            self.assertEqual(site.development_dimensions([self.event], audit), [[] for _ in site.DIMENSIONS])

    def test_missing_segment_and_invalid_metrics(self):
        self.event['segment_id'] = 'missing'
        self.assertEqual(site.development_dimensions([self.event], self.audit()), [[] for _ in site.DIMENSIONS])
        self.event['segment_id'] = 'wake'
        self.document['segments']['wake']['steady'] = {'frame_samples': 0, 'avg_fps': 12}
        self.document['segments']['wake']['audio']['status'] = 'pending'
        self.assertEqual(site.development_dimensions([self.event], self.audit()), [[] for _ in site.DIMENSIONS])
        self.document['segments']['wake']['steady'] = {'frame_samples': 1, 'avg_fps': float('nan'), 'frame_p95_ms': True}
        self.document['segments']['wake']['audio'] = {'status': 'complete', 'signal_present': False, 'integrated_lufs': -70}
        dimensions = site.development_dimensions([self.event], self.audit())
        self.assertNotIn('nan', str(dimensions).lower())
        self.assertNotIn('P95', str(dimensions))
        self.assertEqual(dimensions[3], [])

    def test_bad_json_and_non_check_events(self):
        audit = self.audit()
        self.path.write_text('{', encoding='utf-8')
        digest = hashlib.sha256(self.path.read_bytes()).hexdigest()
        audit['events']['e'][0]['expected_sha256'] = digest
        self.assertEqual(site.development_dimensions([self.event], audit), [[] for _ in site.DIMENSIONS])
        self.event['kind'] = 'change'
        self.assertEqual(site.development_dimensions([self.event], audit), [[] for _ in site.DIMENSIONS])


if __name__ == '__main__':
    unittest.main()
