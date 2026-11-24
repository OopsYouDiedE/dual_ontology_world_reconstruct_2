import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import queue_review as q


class MediaTest(unittest.TestCase):
    def test_seek(self):
        from serve_queue import byte_range
        for header,want in [(None,(0,12)),('bytes=3-6',(3,7)),('bytes=-4',(8,12)),('bytes=11-',(11,12)),('bytes=0-80',(0,12))]:
            self.assertEqual(byte_range(header,12),want)
        for header in ['bytes=12-', 'bytes=-0', 'bytes=5-2', 'bytes=-','bytes=0-1,3-4']:
            with self.assertRaises(ValueError):byte_range(header,12)


class QueueTest(unittest.TestCase):
    def setUp(self):
        t=tempfile.TemporaryDirectory();self.addCleanup(t.cleanup);self.root=Path(t.name);self.db=q.connect(self.root);self.addCleanup(self.db.close)
        self.cards=[dict(id=str(i),scope='a',question='Q',family='x' if i<2 else 'y',contrast=str(i),dx=[1],media=f'{i}.png') for i in range(3)]
        for c in self.cards:(self.root/c['media']).write_bytes(c['id'].encode())
        p=patch.object(q,'catalog',return_value=self.cards);p.start();self.addCleanup(p.stop)

    def test_prediction_and_missing(self):
        q.import_prior(self.db,self.root,'0','A','test');self.assertEqual(q.report(self.db)['prospective'],0)
        card=q.select(self.db,self.root);tid=card['id'];self.assertEqual(q.select(self.db,self.root),card)
        row=self.db.execute('SELECT pred FROM trials WHERE id=?',(tid,)).fetchone();self.assertAlmostEqual(sum(json.loads(row[0])),1)
        q.vote(self.db,self.root,tid,'skip','');self.assertEqual(q.report(self.db)['labels'],1)
        with self.assertRaises(ValueError):q.vote(self.db,self.root,tid,'A','')
        last=q.select(self.db,self.root);q.vote(self.db,self.root,last['id'],'tie','');self.assertEqual(q.report(self.db)['prospective'],1);self.assertIsNone(q.select(self.db,self.root))

    def test_new_family_only(self):
        q.import_prior(self.db,self.root,'0','A','');q.import_prior(self.db,self.root,'1','B','');c=q.select(self.db,self.root);q.vote(self.db,self.root,c['id'],'A','');self.assertEqual(q.report(self.db)['transfer'],1);self.assertFalse(q.report(self.db)['readiness']['a']['eligible_for_shadow_review'])

    def test_quality_holds_matching_edition_without_training(self):
        for c in self.cards:c.update(family='same',contrast='same')
        for choice in q.REWORK:
            with self.subTest(choice=choice):
                self.db.execute('DELETE FROM trials');self.cards[2].pop('edition',None)
                first=q.select(self.db,self.root);q.vote(self.db,self.root,first['id'],choice,'')
                stats=q.report(self.db);self.assertEqual(stats['labels'],0);self.assertEqual(stats['quality'][choice],1)
                self.assertIsNone(q.select(self.db,self.root));self.cards[2]['edition']='new-film'
                self.assertIsNone(q.select(self.db,self.root));self.cards[2]['gate']='accept.json'
                gate=self.root/'accept.json';gate.write_text(json.dumps(dict(ok=True,sha256='old')))
                self.assertIsNone(q.select(self.db,self.root));gate.write_text(json.dumps(dict(ok=True,sha256=q.sha(self.root/'2.png'))))
                self.assertEqual(q.select(self.db,self.root)['id'],'2');self.cards[2].pop('gate')

    def test_changed_evidence(self):
        c=q.select(self.db,self.root);(self.root/c['media']).write_bytes(b'x');
        with self.assertRaises(ValueError):q.vote(self.db,self.root,c['id'],'B','')


if __name__=='__main__':unittest.main()
