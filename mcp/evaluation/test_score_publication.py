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


if __name__ == '__main__':
    unittest.main()
