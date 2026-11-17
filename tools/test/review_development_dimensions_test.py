"""Development evidence remains distinct from independent acceptance scores."""
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/testing'))
import export_review_site as site


class DevelopmentDimensionsTest(unittest.TestCase):
    def test_per_dimension_evidence_and_audit(self):
        texts = ['FPS 0, frame time 40ms', 'word count 12', 'animation clipping',
                 'LUFS -24 dBTP -21', 'blind read', 'SSIM 0.72', 'narrative flow']
        events = [dict(event_id=str(i), kind='check', summary=text, result='<recorded>', revision='abc')
                  for i, text in enumerate(texts)]
        path = 'assets/data/test_scenarios/gameplay_review_plan.json'
        audit = {'events': {str(i): [dict(path=path, status='valid')] for i in range(7)}}
        dimensions = site.development_dimensions(events, audit)
        self.assertTrue(all(dimensions))
        html = site.dimension_scores({}, development=dimensions, page=site.OUT / 'index.html')
        self.assertEqual(html.count('待评'), 7)
        self.assertEqual(html.count('非正式验收'), 7)
        self.assertIn('FPS 0', html)
        self.assertIn('&lt;recorded&gt;', html)
        self.assertNotIn('<recorded>', html)
        self.assertEqual(site.review_result({}), '待评')
        audit['events']['3'][0]['status'] = 'changed'
        dimensions = site.development_dimensions(events, audit)
        self.assertEqual(dimensions[3], [])
        self.assertIn(site.DIMENSION_MISSING[3], site.development_dimension_html([], 3, site.OUT / 'index.html'))

    def test_semantic_measurements_are_labeled_development(self):
        semantic = dict(action_score=0, intent_score=7.5, modality='text_masked_stills',
                        revision='old', id='blind', record_path='assets/data/test_scenarios/gameplay_review_plan.json')
        dimensions = site.development_dimensions([], {'events': {}}, semantic)
        self.assertIn('动作一致度 0/10', dimensions[4][0]['text'])
        self.assertIn('意图一致度 7.5/10', dimensions[4][0]['text'])
        html = site.development_dimension_html(dimensions[4], 4, site.OUT / 'index.html')
        self.assertIn('非正式验收', html)
        self.assertEqual(site.review_result(dict(status='complete', scores=[8]*7, acceptance_eligible=False)), '待评')

    def test_unverified_checks_and_changes_are_excluded(self):
        events = [dict(event_id='x', kind='check', summary='FPS 90', result='', revision='r'),
                  dict(event_id='y', kind='change', summary='LUFS -30', result='', revision='r')]
        audit = {'events': {'x': [dict(path='missing', status='missing')],
                            'y': [dict(path='source', status='valid')]}}
        self.assertEqual(site.development_dimensions(events, audit), [[] for _ in range(7)])

    def test_missing_reasons_and_partial_audit_are_visible(self):
        path = 'assets/data/test_scenarios/gameplay_review_plan.json'
        events = [dict(event_id='partial', kind='check', summary='FPS', result='', revision='r'),
                  dict(event_id='empty', kind='check', summary='LUFS', result='', revision='r')]
        audit = {'events': {'partial': [dict(path=path, status='valid'),
                                       dict(path='lost.json', status='missing'),
                                       dict(path='old.json', status='changed'),
                                       dict(path='unknown.json', status='unverified')], 'empty': []}}
        dimensions = site.development_dimensions(events, audit)
        reasons = site.development_missing_reasons(events, audit, dimensions)
        html = site.dimension_scores({}, development=dimensions, missing=reasons, page=site.OUT / 'index.html')
        for text in ('file missing', 'hash changed', 'hash missing', 'no evidence attached'):
            self.assertIn(text, html)
        self.assertIn('Development diagnostics', html)
        self.assertEqual(html.count('待评'), 7)
        self.assertEqual(dimensions[0][0]['paths'], [path])
        self.assertIn(site.DIMENSION_MISSING[1], reasons[1])

    def test_existing_survey_text_maps_to_relevant_dimensions(self):
        event = dict(event_id='survey', kind='check', summary='主线遍历：wake',
                     result='稳态超线 0 帧', revision='r')
        audit = {'events': {'survey': [dict(path='data.yaml', status='valid')]}}
        dimensions = site.development_dimensions([event], audit)
        self.assertEqual([i for i, items in enumerate(dimensions) if items], [0, 6])


if __name__ == '__main__':
    unittest.main()
