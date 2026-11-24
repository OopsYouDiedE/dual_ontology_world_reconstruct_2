"""Mathematical fixtures only: never exported as human observations or scores."""
import math
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import Mock
import io

from evaluate import Vote, evaluate, fit, folds, load, log_probs

HERE = Path(__file__).resolve().parent


class PreferenceTest(unittest.TestCase):
    def test_swap_and_normalization(self):
        a, b, tie = log_probs([2, .5], [.8])
        self.assertEqual((b, a, tie), log_probs([2, .5], [-.8]))
        self.assertAlmostEqual(sum(map(math.exp, (a, b, tie))), 1)

    def test_learning_and_distinct_holdouts(self):
        votes = [Vote(rater, family, (dx,), choice)
                 for rater in ('fixture1', 'fixture2', 'fixture3')
                 for family, d in (('fixtureA', .8), ('fixtureB', 1.2), ('fixtureC', 1.8))
                 for dx, choice in ((d, 0), (-d, 1), (0., 2))]
        self.assertGreater(fit(votes, 1)[0], 0)
        self.assertGreater(fit([Vote('x', 'y', (0.,), 2)], 1)[-1], 0)
        result = evaluate(votes, 1)
        for axis in ('evaluator', 'family'):
            cv = result['cv'][axis]
            self.assertEqual(len(cv['folds']), 3)
            self.assertEqual(sum(r['test_n'] for r in cv['folds']), len(votes))
            self.assertLess(cv['macro_log_loss'], cv['macro_baseline_log_loss'])
            for train, test in folds(votes, axis):
                self.assertTrue({getattr(v, axis) for v in train}.isdisjoint(getattr(v, axis) for v in test))

    def test_refuse_single_group(self):
        for votes in ([Vote('x', 'a', (1.,), 0)],
                      [Vote('x', 'a', (1.,), 0), Vote('y', 'a', (1.,), 2)]):
            with self.assertRaisesRegex(ValueError, 'no scores'):
                evaluate(votes, 1)

    def test_refuse_machine_source(self):
        registry = Mock()
        registry.read_text.return_value = '{"features":["offset"],"layouts":{}}'
        labels = Mock()
        labels.open.return_value = io.StringIO('evaluator_id,trial_id,layout_a,layout_b,choice,source\n'
                                               'fixture,trial,a,b,A,policy\n')
        with self.assertRaisesRegex(ValueError, 'one human judgment'):
            load(registry, labels)

    def test_load_orientation_and_family_guard(self):
        registry = Mock()
        registry.read_text.return_value = ('{"features":["offset"],"layouts":'
                                           '{"a":{"family":"f","x":[0]},"b":{"family":"f","x":[1]},'
                                           '"c":{"family":"g","x":[-1]}}}')
        labels = Mock()
        header = 'evaluator_id,trial_id,layout_a,layout_b,choice,source\n'
        first = 'p_0123456789abcdef,t,b,a,B,human\n'
        labels.open.return_value = io.StringIO(header + first)
        self.assertEqual(load(registry, labels), (['offset'], [Vote('p_0123456789abcdef', 'f', (1,), 1)]))
        labels.open.return_value = io.StringIO(header + first + first)
        with self.assertRaisesRegex(ValueError, 'reused evaluator/trial'):
            load(registry, labels)
        labels.open.return_value = io.StringIO(header + first.replace(',b,a,', ',b,c,'))
        with self.assertRaisesRegex(ValueError, 'same structure family'):
            load(registry, labels)

    def test_empty_cli_has_no_score_output(self):
        result = subprocess.run([sys.executable, '-B', str(HERE/'evaluate.py'), '--layouts',
                                 str(HERE/'layouts.empty.json'), '--labels', str(HERE/'labels.empty.csv')],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, '')
        self.assertIn('no human labels', result.stderr)


if __name__ == '__main__':
    unittest.main()
