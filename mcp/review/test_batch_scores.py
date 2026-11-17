"""Atomic seven-dimension score submissions."""
import copy
import asyncio
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'mcp' / 'review'))
from core import SCORE_CATEGORIES, Store
from server import execute


class BatchScoresTest(unittest.TestCase):
    def setUp(self):
        parent = ROOT / '.runtime' / 'review-tests'
        parent.mkdir(parents=True, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(dir=parent)
        self.addCleanup(self.tmp.cleanup)
        self.store = Store(test_sandbox=self.tmp.name)
        self.args = dict(trajectory_id='wake', test_id='test-01',
                         scores={category: 8 for category in SCORE_CATEGORIES},
                         reasons={category: 'Measured from the test' for category in SCORE_CATEGORIES},
                         evidence=[])

    def test_single_event_retry_and_retrieval(self):
        self.args['scores']['audio_loudness'] = None
        self.args['reasons']['audio_loudness'] = 'Audio capture unavailable'
        first = execute(self.store, 'add_scores', self.args)
        self.assertFalse(first['duplicate'])
        self.assertTrue(execute(self.store, 'add_scores', self.args)['duplicate'])
        self.assertEqual(len(self.store.load()['events']), 1)
        event = execute(self.store, 'see_score', {'trajectory_id': 'wake'})['latest_test']
        self.assertEqual(event['test_result']['scores']['audio_loudness'], 0)
        self.assertEqual(event['test_result']['provisional_categories'], ['audio_loudness'])
        self.assertEqual(event['test_result']['status'], 'incomplete')
        self.assertIn('Audio capture unavailable', event['test_result']['reasons']['audio_loudness'])
        self.assertIn('Provisional 0', event['test_result']['reasons']['audio_loudness'])
        self.assertEqual(event['test_result']['scores']['fluidity'], 8)
        self.assertEqual(len(event['revision']), 40)
        changed = copy.deepcopy(self.args)
        changed['scores']['fluidity'] = 9
        with self.assertRaises(ValueError):
            execute(self.store, 'add_scores', changed)
        self.assertEqual(len(self.store.load()['events']), 1)

    def test_explicit_incomplete_keeps_observed_numeric_failures(self):
        self.args['scores'] = {category: 6 for category in SCORE_CATEGORIES}
        self.args['status'] = 'incomplete'
        event = execute(self.store, 'add_scores', self.args)['event']
        result = event['test_result']
        self.assertEqual(result['status'], 'incomplete')
        self.assertEqual(result['provisional_categories'], [])
        self.assertTrue(all(score == 6 for score in result['scores'].values()))
        import test_results
        self.assertEqual(test_results.collect([], [event])[0]['status'], '已测 · 测试未完成')

    def test_invalid_batches_leave_no_event(self):
        variants = []
        missing = copy.deepcopy(self.args); missing['scores'].pop('fluidity'); variants.append(missing)
        empty = copy.deepcopy(self.args); empty['scores']['fluidity'] = None; empty['reasons']['fluidity'] = ' '; variants.append(empty)
        nan = copy.deepcopy(self.args); nan['scores']['fluidity'] = float('nan'); variants.append(nan)
        invalid = copy.deepcopy(self.args); invalid['evidence'] = ['does-not-exist']; variants.append(invalid)
        for value in variants:
            with self.subTest(value=value), self.assertRaises(Exception):
                execute(self.store, 'add_scores', value)
        self.assertEqual(self.store.load()['events'], [])

    def test_real_mcp_batch_roundtrip(self):
        from client import invoke
        result = asyncio.run(invoke('add_scores', self.args, test_sandbox=self.tmp.name))
        self.assertFalse(result['result'].get('isError', False))
        self.assertIn('add_scores', [tool['name'] for tool in result['tools']])
        event = self.store.load()['events'][0]
        self.assertEqual(event['test_result']['scores'], self.args['scores'])
        self.assertEqual(len(self.store.load()['events']), 1)


if __name__ == '__main__':
    unittest.main()
