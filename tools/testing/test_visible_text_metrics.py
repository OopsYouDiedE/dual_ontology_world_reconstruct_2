"""Unit checks for evidence-backed visible text scoring."""
import json
from pathlib import Path
import tempfile
import unittest

from visible_text_metrics import analyze_visible_text


class VisibleTextMetricsTests(unittest.TestCase):
    def setUp(self):
        runtime = Path(__file__).resolve().parents[2] / '.runtime'
        runtime.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=runtime)
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'visible-text-changes.jsonl'

    def entry(self, text, category='prompt', **extra):
        return {'path': '/root/Prompt', 'text': text, 'category': category,
                'english_verified': True, **extra}

    def write(self, *entries, segment='wake'):
        records = [{'frame': i + 1, 'elapsed_s': (i + 1) / 10,
                    'scene_node': segment + '/R05', 'entries': item}
                   for i, item in enumerate(entries)]
        self.path.write_text(''.join(json.dumps(row, ensure_ascii=False) + '\n' for row in records), encoding='utf-8')

    def analyze(self, complete=True, **kwargs):
        return analyze_visible_text(self.path, segment_id='wake', collection_complete=complete, **kwargs)

    def test_zero_text_scores_ten(self):
        self.write([])
        result = self.analyze()
        self.assertEqual(result['score'], 10)
        self.assertEqual(result['records'], 1)

    def test_english_typographic_punctuation_is_not_foreign(self):
        self.write([self.entry('Don’t touch the door — wait.')])
        result = self.analyze()
        self.assertEqual(result['score'], 8)
        self.assertEqual(result['max_words'], 5)
        self.assertEqual(result['non_english'], [])

    def test_more_than_twelve_words_fails(self):
        self.write([self.entry('one two three four five six seven eight nine ten eleven twelve thirteen')])
        self.assertEqual(self.analyze()['score'], 6)

    def test_character_limit_fails_even_when_word_count_is_small(self):
        self.write([self.entry('A' * 61)])
        self.assertEqual(self.analyze()['score'], 6)

    def test_simultaneous_entries_are_added_per_frame(self):
        self.write([self.entry('one two three four five six seven'),
                    self.entry('eight nine ten eleven twelve thirteen', path='/root/Other')],
                   [self.entry('short')])
        result = self.analyze()
        self.assertEqual(result['score'], 6)
        self.assertEqual(result['max_words'], 13)
        self.assertEqual(result['worst_words_at_s'], 0.1)

    def test_disabled_button_is_still_visible_and_counted(self):
        self.write([self.entry('word ' * 13, disabled=True)])
        self.assertEqual(self.analyze()['score'], 6)

    def test_nameplate_and_certified_key_icon_do_not_count(self):
        self.write([self.entry('Detective', 'nameplate'), self.entry('E', 'single_key_icon')])
        self.assertEqual(self.analyze()['score'], 10)

    def test_ambiguous_single_character_is_not_automatically_an_icon(self):
        self.write([self.entry('E', 'single_key_or_text')])
        result = self.analyze()
        self.assertEqual(result['score'], 8)
        self.assertIn('counted conservatively', result['reason'])
        review = {('/root/Prompt', 'E'): {'category': 'single_key_icon', 'english_verified': True}}
        self.assertEqual(self.analyze(reviews=review)['score'], 10)

    def test_one_character_non_english_is_detected(self):
        self.write([self.entry('查', 'single_key_or_text', english_verified=False)])
        self.assertEqual(self.analyze()['score'], 6)

    def test_english_cannot_be_inferred_solely_from_latin_letters(self):
        self.write([self.entry('Wait', english_verified=False)])
        self.assertEqual(self.analyze()['score'], 8)
        self.assertTrue(self.analyze()['complete'])
        self.assertIn('script only', self.analyze()['reason'])
        review = {('/root/Prompt', 'Wait'): {'category': 'prompt', 'english_verified': True}}
        self.assertEqual(self.analyze(reviews=review)['score'], 8)

    def test_incomplete_collection_never_passes(self):
        self.write([self.entry('Wait.')])
        result = self.analyze(complete=False)
        self.assertIsNone(result['score'])
        self.assertIn('interrupted', result['reason'])
        self.write([self.entry('word ' * 13)])
        failed = self.analyze(complete=False)
        self.assertEqual(failed['score'], 6)
        self.assertIn('incomplete', failed['reason'])

    def test_missing_and_invalid_timeline_are_missing(self):
        self.assertIsNone(self.analyze()['score'])
        self.path.write_text('{broken\n', encoding='utf-8')
        self.assertIn('invalid', self.analyze()['reason'])
        self.write([], segment='shaft')
        self.assertIn('No visible-text', self.analyze()['reason'])

    def test_malformed_category_does_not_crash_or_score(self):
        self.write([self.entry('Wait', category=['prompt'])])
        result = self.analyze()
        self.assertIsNone(result['score'])
        self.assertIn('invalid classification', result['reason'])

    def test_backward_frame_is_invalid(self):
        self.path.write_text(json.dumps({'frame': 2, 'elapsed_s': 2, 'scene_node': 'wake/R05', 'entries': []}) + '\n'
                             + json.dumps({'frame': 1, 'elapsed_s': 3, 'scene_node': 'wake/R05', 'entries': []}) + '\n', encoding='utf-8')
        self.assertIn('out-of-order', self.analyze()['reason'])


if __name__ == '__main__':
    unittest.main()
