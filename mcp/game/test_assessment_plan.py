"""Reject incomplete evaluation preparation before creating a runtime host."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from assessment_plan import CATEGORIES, validate


class AssessmentPlanTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'reference.png').write_bytes(b'unit-test-fixture')
        (self.root / 'provenance.json').write_text('{}')
        (self.root / 'ready.json').write_text(json.dumps(dict(test_id='test', observer='reviewer', ready=True, canonical_unseen=True)))
        self.plan = dict(schema_version=1, test_id='test', revision='revision', collection_mode='simultaneous',
                         max_fps=60, max_hosts=3,
                         channels={key: dict(collector='live', assessor='assigned', method='documented') for key in CATEGORIES},
                         blind_observer=dict(identity='reviewer', canonical_unseen=True, ready_receipt='ready.json'),
                         cases=[dict(id='scene', segment_id='segment', reference=dict(path='reference.png',
                         sha256=hashlib.sha256(b'unit-test-fixture').hexdigest(), provenance='provenance.json'))])

    def check(self):
        path = self.root / 'plan.json'
        path.write_text(json.dumps(self.plan))
        return validate(path, self.root, revision='revision')

    def test_all_channels_and_observer_references_are_required(self):
        self.assertEqual(self.check()['test_id'], 'test')
        del self.plan['channels']['audio_loudness']
        with self.assertRaisesRegex(ValueError, 'seven'):
            self.check()

    def test_missing_or_changed_reference_prevents_launch(self):
        (self.root / 'reference.png').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            self.check()
        (self.root / 'reference.png').unlink()
        with self.assertRaisesRegex(ValueError, 'existing project file'):
            self.check()

    def test_stale_readiness_or_source_prevents_launch(self):
        self.plan['blind_observer']['identity'] = 'other'
        with self.assertRaisesRegex(ValueError, 'readiness'):
            self.check()
        self.plan['revision'] = 'old'
        with self.assertRaisesRegex(ValueError, 'revision'):
            self.check()

    def test_offline_or_unassigned_assessment_prevents_launch(self):
        self.plan['collection_mode'] = 'later'
        with self.assertRaisesRegex(ValueError, 'simultaneous'):
            self.check()
        self.plan['collection_mode'] = 'simultaneous'
        self.plan['channels']['narrative_flow']['assessor'] = ''
        with self.assertRaisesRegex(ValueError, 'assessor'):
            self.check()


if __name__ == '__main__':
    unittest.main()
