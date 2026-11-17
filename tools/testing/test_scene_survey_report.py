"""Scene survey report projection and safe, partial-result handling."""
import json
from pathlib import Path
import tempfile
import unittest
from html import escape

import test_results


class SceneSurveyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.runs = self.root / 'artifacts/evaluation/runs'
        self.runs.mkdir(parents=True)

    def tearDown(self):
        self.temp.cleanup()

    def put(self, path, obj):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(obj), encoding='utf-8')

    def test_latest_batch_escapes_content_and_retains_timed_out_phase(self):
        directory = self.runs / 'eval-20261117t170000-test'
        self.put(directory / 'status.json', dict(profile='scene_survey', run_id='batch', revision='abcdef012345',
                 state='blocked', jobs={'scene-one': {'state':'failed', 'detail':{'error':'Timeout <blocked>'}},
                                        'scene-two': {'state':'passed', 'detail':{}}}))
        self.put(directory / 'scene-one/plan.json', [dict(id='one', fixture=dict(room='R<1>'))])
        self.put(directory / 'scene-one/one/progress.json', dict(phase='inspect <scratch>'))
        self.put(directory / 'scene-two/plan.json', [dict(id='two', fixture=dict(room='R2'))])
        self.put(directory / 'scene-two/survey.json', dict(cases=[dict(id='two', images=[], issues=[], final=dict(beat='d1'))]))
        # A newer unrelated run must not replace the latest actual scene survey.
        self.put(self.runs / 'eval-20261117t180000-other/status.json', dict(profile='chapter1_ui'))
        data = test_results.latest_scene_survey(self.root)
        self.assertEqual(data['id'], 'batch')
        self.assertEqual(len(data['rows']), 2)
        self.assertEqual(data['rows'][0]['phase'], 'inspect <scratch>')
        self.assertEqual(data['rows'][0]['room'], 'R<1>')
        self.assertEqual(data['rows'][1]['phase'], 'd1')
        html = test_results.scene_survey_table(data, None, lambda p, label, page: f'<a>{escape(label)}</a>')
        self.assertIn('Timeout &lt;blocked&gt;', html)
        self.assertIn('inspect &lt;scratch&gt;', html)
        self.assertNotIn('<scratch>', html)
        self.assertEqual(html.count('data-survey-case='), 2)

    def test_case_scores_stay_with_same_run_and_render_all_seven(self):
        directory = self.runs / 'eval-20261117t170000-test'
        status = dict(profile='scene_survey', run_id='batch', revision='abcdef012345',
                      jobs={'survey-one': {'state':'passed'}, 'survey-two': {'state':'failed'}})
        self.put(directory / 'status.json', status)
        values = dict.fromkeys(test_results.CATEGORIES)
        values['fluidity'] = 6
        reasons = dict.fromkeys(test_results.CATEGORIES, 'No measured <value>')
        reasons['fluidity'] = 'Observed a spike'
        score_file = dict(run_id='batch', source_revision='abcdef012345', cases=[
            dict(case_id='one', source_revision='abcdef012345', scores=values, reasons=reasons)])
        self.put(directory / 'scene-scores.json', score_file)
        data = test_results.latest_scene_survey(self.root)
        self.assertEqual(data['rows'][0]['scores']['fluidity'], 6)
        self.assertIsNone(data['rows'][0]['scores']['audio_loudness'])
        self.assertIsNone(data['rows'][1]['scores']['fluidity'])
        html = test_results.scene_survey_table(data, None, lambda *args: '<a>link</a>')
        self.assertEqual(html.count('data-survey-score='), 0)
        self.assertIn('<details>', html)
        self.assertIn('执行结束，评分见对应片段', html)
        payload = test_results.scene_survey_payload(self.root, data)
        self.assertEqual(payload['rows'][0]['reasons']['fluidity'], 'Observed a spike')
        reviewed = json.loads(json.dumps(score_file))
        reviewed['cases'][0]['scores']['text_density'] = 6
        self.put(directory / 'scene-scores-reviewed.json', reviewed)
        self.assertEqual(test_results.latest_scene_survey(self.root)['rows'][0]['scores']['text_density'], 6)
        self.assertIsNone(json.loads((directory / 'scene-scores.json').read_text())['cases'][0]['scores']['text_density'])
        (directory / 'scene-scores-reviewed.json').unlink()
        score_file['source_revision'] = 'other'
        self.put(directory / 'scene-scores.json', score_file)
        self.assertIsNone(test_results.latest_scene_survey(self.root)['rows'][0]['scores']['fluidity'])
        score_file['source_revision'] = status['revision']
        score_file['cases'].append(score_file['cases'][0])
        self.put(directory / 'scene-scores.json', score_file)
        self.assertIsNone(test_results.latest_scene_survey(self.root)['rows'][0]['scores']['fluidity'])

    def test_stall_keeps_step_and_reason_after_job_completion(self):
        directory = self.runs / 'eval-20261117t170000-test'
        self.put(directory / 'status.json', dict(profile='scene_survey', jobs={'survey-boot': {'state':'blocked', 'detail':{}}}))
        self.put(self.root / 'assets/data/test_scenarios/mainline_survey.json', [dict(id='boot', fixture=dict(room='B-P'))])
        self.put(directory / 'survey-boot/survey.json', dict(cases=[dict(id='boot', stalls=[dict(phase='inspect', action='boot-print', reason='walking path timed out')], issues=[])]))
        self.put(directory / 'survey-boot/progress.json', dict(phase='completed'))
        row = test_results.latest_scene_survey(self.root)['rows'][0]
        self.assertEqual(row['id'], 'boot')
        self.assertEqual(row['room'], 'B-P')
        self.assertIn('inspect / boot-print / walking path timed out', row['reason'])

    def test_scenes_are_grouped_under_their_segment(self):
        directory = self.runs / 'eval-20261117t170000-test'
        self.put(directory / 'status.json', dict(profile='scene_survey', jobs={
            'survey-a': {'segment_id': 'wake', 'state': 'passed'},
            'survey-b': {'segment_id': 'shaft', 'state': 'failed'}}))
        data = test_results.latest_scene_survey(self.root)
        wake = test_results.scene_survey_table(data, None, lambda *args: '<a>link</a>', 'wake')
        shaft = test_results.scene_survey_table(data, None, lambda *args: '<a>link</a>', 'shaft')
        self.assertIn('data-survey-case="a"', wake)
        self.assertNotIn('data-survey-case="b"', wake)
        self.assertIn('data-survey-case="b"', shaft)
        self.assertEqual(test_results.scene_survey_table(data, None, lambda *args: '', 'poem'), '')
        payload = test_results.scene_survey_payload(self.root, data)
        self.assertEqual([row['segment_id'] for row in payload['rows']], ['wake', 'shaft'])

    def test_live_bootstrap_never_reloads_for_older_pages(self):
        self.assertNotIn('location.reload', test_results.SCENE_LIVE_BOOTSTRAP)
        self.assertIn('window.__sceneSurveyLive', test_results.SCENE_LIVE_BOOTSTRAP)

    def test_missing_or_invalid_results_and_untrusted_links(self):
        directory = self.runs / 'eval-20261117t170000-test'
        self.put(directory / 'status.json', dict(profile='scene_survey', jobs={'a': {'state':'planned'}, 'b': {'state':'failed', 'detail':{'reason':'host exited'}}}))
        self.put(directory / 'b/plan.json', [dict(id='case-b', fixture=dict(room='B'))])
        self.put(directory / 'b/survey.json', dict(cases=[dict(id='case-b', images=[{'path':'../../outside.png'}], issues=['wait for input'])]))
        data = test_results.latest_scene_survey(self.root)
        self.assertEqual(data['rows'][0]['id'], 'a')
        self.assertEqual(data['rows'][0]['state'], 'planned')
        self.assertEqual(data['rows'][1]['reason'], 'wait for input；host exited')
        self.assertEqual(data['rows'][1]['images'], [])
        self.assertIsNone(test_results.latest_scene_survey(self.root / 'missing'))


if __name__ == '__main__':
    unittest.main()
