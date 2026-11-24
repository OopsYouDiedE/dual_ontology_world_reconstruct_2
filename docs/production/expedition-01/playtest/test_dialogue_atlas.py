"""Synthetic tiny replays exercise denominator, location and ordering rules."""
import json, tempfile, unittest
from pathlib import Path
from dialogue_atlas import catalog, load, zones

class Atlas(unittest.TestCase):
    def test_bilingual_catalog(self):
        rows = catalog()
        for key, count in [('start', 1), ('north_order', 2), ('archive_note', 1), ('reunion', 2)]:
            self.assertEqual(len([s for s, keys in rows.items() if key in keys]), count, key)

    def test_locations(self):
        self.assertNotIn('collapse',zones(31,0,4.4)); self.assertIn('collapse',zones(31,0,4.401))
        self.assertNotIn('ward_paired',zones(21.43,3,8.46))
    def test_matrix(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t); lines=catalog(); line=next(l for l,k in lines.items() if 'ward_paired' in k)
            for grp,i in [('matrix',1),('matrix',2),('human',1)]:
                path=root/grp/str(i); path.mkdir(parents=True); e=dict(event='dialogue',feet=[21.43,0,8.46],value=line,tick=12)
                d=dict(events=[e,e,dict(e,event='caption'),dict(e,event='confirmed',value='本次失败')] if i==1 else [],path_samples=[[12,21.43,0,8.46]],seed=i,outcome='interrupted',profile='test',policy_parameters={})
                (path/('route.json' if grp=='matrix' else 'report.json')).write_text(json.dumps(d))
            d=load(root/'matrix',root/'human'); rows=[r for r in d['rates'] if r['cohort']=='固定路线' and r['profile']=='全部']; r=next(r for r in rows if r['line']==line)
            self.assertEqual((r['heard'],r['runs'],r['events'],r['local'],r['reached']),(1,2,2,1,2)); self.assertTrue(any(r['heard']==0 for r in rows)); self.assertEqual(d['cases'][0]['outcome'],'gameplay_death'); self.assertTrue(d['order'][0]['paired_without_prior_window_caption'])

if __name__=='__main__': unittest.main()
