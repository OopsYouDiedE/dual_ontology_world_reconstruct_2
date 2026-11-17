"""Evaluation score publication and report lifecycle."""
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'mcp' / 'evaluation'))
import worker


class EvaluationReportTest(unittest.TestCase):
    def setUp(self):
        parent = ROOT / '.runtime' / 'review-tests'
        parent.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=parent)
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.state = dict(run_id='eval-20261117t120000-abcdef12', revision='a' * 40,
                          source_fingerprint_after='same', source_changed_during_run=False,
                          jobs={'bedroom-fast': {'state': 'passed', 'host_pid': 1},
                                'story-visual': {'state': 'failed', 'host_pid': 2},
                                'corridor-fast': {'state': 'blocked'},
                                'room-fast': {'state': 'failed', 'host_pid': 3, 'detail': {'room': 'B-P'}}})
        (self.directory / 'bedroom-fast').mkdir()
        (self.directory / 'bedroom-fast' / 'result.json').write_text('{}')
        self.e = worker.Evaluation.__new__(worker.Evaluation)
        self.e.root, self.e.directory, self.e.state = ROOT, self.directory, self.state
        self.e.lock, self.e.store, self.e._publish = threading.Lock(), Mock(), Mock()

    def test_segment_grouping_keeps_seven_honest_pending_scores(self):
        result = worker.build_test_results(self.state, self.directory, ROOT)
        self.assertEqual(set(result), {'wake', 'kitchen_evidence'})
        self.assertEqual(result['wake']['jobs'], ['bedroom-fast', 'story-visual'])
        self.assertEqual(len(result['wake']['scores']), 7)
        self.assertTrue(all(v is None for v in result['wake']['scores'].values()))
        self.assertTrue(all(result['wake']['reasons'].values()))
        self.assertEqual(len(result['wake']['evidence']), 1)

    @patch.object(worker.c, 'source_fingerprint', return_value='same')
    @patch.object(worker.c, 'revision_state', return_value={'revision': 'a' * 40})
    def test_publish_all_segments_and_capture_render_error(self, revision, fingerprint):
        self.e.store.flush.side_effect = RuntimeError('render failed')
        self.e.publish_test_results()
        self.assertEqual(self.e.store.add_scores.call_count, 2)
        self.assertIn('render failed', self.state['report_error'])
        self.assertEqual(len(self.state['test_results']), 2)

    @patch.object(worker.c, 'source_fingerprint', return_value='changed')
    @patch.object(worker.c, 'revision_state', return_value={'revision': 'a' * 40})
    def test_changed_source_blocks_publication_and_still_renders(self, revision, fingerprint):
        self.e.publish_test_results()
        self.e.store.add_scores.assert_not_called()
        self.e.store.flush.assert_called_once_with(full_render=True)
        self.assertIn('Source changed', self.state['test_results_publication_error'])

    @patch.object(worker.c, 'source_fingerprint', return_value='same')
    @patch.object(worker.c, 'revision_state', return_value={'revision': 'a' * 40})
    def test_scene_survey_publishes_all_segments_once_with_immutable_evidence(self, revision, fingerprint):
        import json
        segments = ['wake', 'corridor', 'kitchen_evidence', 'kitchen_reconstruction',
                    'service_route', 'cross_zone', 'shaft', 'poem', 'institutes', 'dinner', 'chapter_end']
        self.state.update(profile='scene_survey', state='blocked',
            jobs={'survey-' + segment: {'state': 'blocked', 'segment_id': segment} for segment in segments})
        (self.directory / 'status.json').write_text(json.dumps(self.state), encoding='utf-8')
        self.e.publish_test_results()
        self.assertEqual(self.e.store.add_scores.call_count, 11)
        self.assertEqual(set(self.state['test_results']), set(segments))
        score_file = self.directory / 'scene-scores.json'
        self.assertTrue(score_file.is_file())
        for call in self.e.store.add_scores.call_args_list:
            args = call.kwargs
            self.assertEqual(len(args['scores']), 7)
            self.assertTrue(all(value is None for value in args['scores'].values()))
            self.assertTrue(all(args['reasons'].values()))
            self.assertTrue(any(value.endswith('/scene-scores.json') for value in args['evidence']))
            self.assertFalse(any(value.endswith('/status.json') for value in args['evidence']))
        self.e.store.flush.assert_called_once_with(full_render=True)

    @patch.object(worker.c, 'source_fingerprint', return_value='same')
    @patch.object(worker.c, 'revision_state', return_value={'revision': 'a' * 40})
    def test_scene_survey_forwards_measured_and_missing_values_together(self, revision, fingerprint):
        import importlib
        sys.path.insert(0, str(ROOT / 'tools' / 'testing'))
        self.addCleanup(sys.path.remove, str(ROOT / 'tools' / 'testing'))
        scoring = importlib.import_module('scene_survey_scores')
        self.state.update(profile='scene_survey', state='completed')
        values = dict.fromkeys(worker.SCORE_REASONS)
        values['fluidity'] = 6
        values['audio_loudness'] = 8
        collected = {'source_revision': self.state['revision'], 'run_id': self.state['run_id'],
                     'segments': {'wake': {'case_ids': ['bedroom'], 'scores': values,
                                          'reasons': dict(worker.SCORE_REASONS), 'evidence': []}}}
        with patch.object(scoring, 'collect', return_value=collected):
            self.e.publish_test_results()
        args = self.e.store.add_scores.call_args.kwargs
        self.assertEqual(args['scores'], values)
        self.assertEqual(args['scores']['fluidity'], 6)
        self.assertEqual(args['scores']['audio_loudness'], 8)
        self.assertIsNone(args['scores']['aesthetic_similarity'])

    @patch.object(worker.c, 'source_fingerprint', return_value='changed')
    @patch.object(worker.c, 'revision_state', return_value={'revision': 'a' * 40})
    def test_changed_scene_survey_never_publishes(self, revision, fingerprint):
        self.state['profile'] = 'scene_survey'
        self.e.publish_test_results()
        self.e.store.add_scores.assert_not_called()
        self.assertFalse((self.directory / 'scene-scores.json').exists())
        self.assertIn('Source changed', self.state['test_results_publication_error'])


if __name__ == '__main__':
    unittest.main()
