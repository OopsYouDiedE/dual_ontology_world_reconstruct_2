"""Development score ledger and live report projection tests."""
import asyncio
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'mcp' / 'review'))
sys.path.insert(0, str(ROOT / 'tools' / 'testing'))
from core import Store
from server import execute
import export_review_site as exporter


class DevelopmentScoresTests(unittest.TestCase):
    def setUp(self):
        parent = ROOT / '.runtime' / 'review-tests'
        parent.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=parent)
        self.store = Store(test_sandbox=Path(self.temp.name))

    def tearDown(self):
        self.temp.cleanup()

    def test_mcp_events_are_immediately_published_and_separate_from_acceptance(self):
        args = dict(trajectory_id='wake', category='fluidity', score=7, rationale='<observed>')
        first = execute(self.store, 'add_score', args)
        self.assertFalse(first['duplicate'])
        self.assertTrue(execute(self.store, 'add_score', args)['duplicate'])
        execute(self.store, 'add_score', dict(args, score=9, rationale='new observation'))
        result = execute(self.store, 'see_score', {'trajectory_id': 'wake'})
        event = result['scores']['fluidity']
        self.assertEqual(event['development_score']['score'], 9)
        self.assertFalse(result['acceptance_eligible'])
        self.assertEqual(event['server_identity']['server_pid'], os.getpid())
        live = self.store.live.read_text(encoding='utf-8').split('=', 1)[1].rstrip(';\n')
        self.assertEqual(len(json.loads(live)['events']), 2)
        rendered = exporter.dimension_scores({}, development_scores=exporter.development_score_events(self.store.load()['events']))
        self.assertIn('9/10 · new observation', rendered)
        self.assertIn('评分来源 · 非正式验收', rendered)
        self.assertIn('<b class="primary-score">9<small>/10</small></b><small class="primary-score-label">开发测试分数</small>', rendered)
        self.assertIn('正式验收：待评', rendered)
        self.assertEqual(rendered.count('<b class="primary-score">待评</b>'), 6)
        self.assertEqual(exporter.review_result({}), '待评')

    def test_real_stdio_mcp_score_call(self):
        from client import invoke
        response = asyncio.run(invoke('add_score',
            dict(trajectory_id='wake', category='audio_loudness', score=6, rationale='fixture'),
            test_sandbox=self.temp.name))
        self.assertIn('add_score', [tool['name'] for tool in response['tools']])
        self.assertFalse(response['result'].get('isError', False))
        self.assertEqual(self.store.load()['events'][0]['development_score']['score'], 6)

    def test_reject_invalid_updates(self):
        base = dict(trajectory_id='wake', category='fluidity', score=8)
        for change in (dict(score=-1), dict(score=11), dict(score=True), dict(score=float('nan')),
                       dict(category='invented'), dict(trajectory_id='missing-segment'), dict(trajectory_id='project')):
            with self.subTest(change=change), self.assertRaises(Exception):
                execute(self.store, 'add_score', dict(base, **change))
        self.assertEqual(self.store.load()['events'], [])

    def test_formal_score_remains_primary_when_development_score_exists(self):
        execute(self.store, 'add_score', dict(trajectory_id='wake', category='fluidity', score=6, rationale='development'))
        record = {'scores': [9] + [None] * 6, 'score_reasons': ['formal finding'] + [''] * 6}
        rendered = exporter.dimension_scores(record, development_scores=exporter.development_score_events(self.store.load()['events']))
        self.assertIn('<b class="primary-score">9<small>/10</small></b><small class="primary-score-label">正式验收分数</small>', rendered)
        self.assertIn('6/10 · development', rendered)
        self.assertIn('正式验收：formal finding', rendered)

    def test_coverage_counts_unique_segments_and_formal_precedence(self):
        execute(self.store, 'add_score', dict(trajectory_id='wake', category='fluidity', score=6))
        entries = [dict(id='wake', label='Opening', scores=[9, None, None, None, None, None, None], events=self.store.load()['events']),
                   dict(id='corridor', label='Hall', scores=[None] * 7, events=[])]
        rendered = exporter.scoring_coverage(entries)
        self.assertIn('正式 1 项 · 开发 0 项 · 仅历史 0 项 · 待评 13 项', rendered)
        self.assertIn('9 · 正式', rendered)
        entries[0]['scores'][0] = None
        self.assertIn('正式 0 项 · 开发 1 项 · 仅历史 0 项 · 待评 13 项', exporter.scoring_coverage(entries))
        entries[1]['history'] = [dict(id='prior', revision='abcdef0123', scores=[None, 8] + [None] * 5)]
        coverage = exporter.scoring_coverage(entries)
        self.assertIn('正式 0 项 · 开发 1 项 · 仅历史 1 项 · 待评 12 项', coverage)
        self.assertIn('8 · 历史', coverage)
        self.assertIn('历史版本 abcdef01；当前版本待评', coverage)

    def test_missing_scores_and_escaping(self):
        execute(self.store, 'add_score', dict(trajectory_id='wake', category='text_density', score=5, rationale='<script>'))
        html = exporter.dimension_scores({}, development_scores=exporter.development_score_events(self.store.load()['events']))
        self.assertEqual(html.count('No development score recorded'), 6)
        self.assertIn('&lt;script&gt;', html)
        self.assertNotIn('<script>', html)

    @unittest.skipUnless(shutil.which('node'), 'Node.js is required for the live UI test')
    def test_live_javascript_updates_without_changing_formal_score(self):
        script = ROOT / 'tools' / 'testing' / 'review.js'
        code = r"""
const fs = require('fs'), vm = require('vm');
const scoreValue = {textContent: ''}, formal = {textContent: '正式验收：待评'};
const primary = {textContent: '待评'}, label = {textContent:'等待评分'};
const dimension = {dataset:{formalScored:'false'}, classList:{remove(){},add(){}},
  querySelector: s => s === '.primary-score' ? primary : label};
const card = {dataset:{scoreCategory:'fluidity'}, querySelector: () => scoreValue, closest: () => dimension};
const segment = {dataset:{segment:'wake'}, querySelectorAll: () => [card]};
const list = {children:[], append: function(row){this.children.push(row)}};
const empty = {hidden:false};
const document = {querySelectorAll: s => s === '.segment[data-segment]' ? [segment] : [],
  getElementById: id => id === 'progress-events' ? list : id === 'progress-empty' ? empty : null,
  querySelector: () => null,
  createElement: tag => ({dataset:{}, append(){}, remove(){}, textContent:'', className:''}),
  body:{append(){}}};
const e = {event_id:'ev', segment_id:'wake', kind:'check', at:'now', summary:'score', result:'ok',
  work_id:'work', revision:'abcdef0', evidence:[], development_score:{category:'fluidity',score:7,rationale:'test',acceptance_eligible:false}};
const window = {MAINLINE_PROGRESS:{events:[e]}};
vm.runInNewContext(fs.readFileSync(process.argv[1], 'utf8'), {document, window, setInterval(){}, Date});
if (!scoreValue.textContent.includes('7/10') || primary.textContent !== '7/10' || label.textContent !== '开发测试分数' || formal.textContent !== '正式验收：待评') process.exit(1);
dimension.dataset.formalScored = 'true'; primary.textContent = '9/10'; window.MAINLINE_PROGRESS.events[0].development_score.score = 6;
window.MAINLINE_PROGRESS.events[0].event_id = 'ev2';
vm.runInNewContext(fs.readFileSync(process.argv[1], 'utf8'), {document, window, setInterval(){}, Date});
if (primary.textContent !== '9/10' || !scoreValue.textContent.includes('6/10')) process.exit(2);
"""
        subprocess.run(['node', '-e', code, str(script)], check=True, cwd=ROOT, capture_output=True, text=True)


    @unittest.skipUnless(shutil.which('node'), 'Node.js is required for the live UI test')
    def test_live_coverage_replaces_historical_and_keeps_formal(self):
        script = ROOT / 'tools' / 'testing' / 'review.js'
        code = r"""
const fs=require('fs'), vm=require('vm');
const summary={textContent:''};
const historical={dataset:{coverageCategory:'fluidity',formalScored:'false',scoreSource:'historical'}, textContent:'6 · 历史', removeAttribute(){this.removed=true}};
const formal={dataset:{coverageCategory:'audio_loudness',formalScored:'true',scoreSource:'formal'},textContent:'9 · 正式',removeAttribute(){}};
const pending={dataset:{coverageCategory:'narrative_flow',formalScored:'false',scoreSource:'pending'},textContent:'待评',removeAttribute(){}};
const row={dataset:{coverageSegment:'wake'},querySelectorAll:()=>[historical,formal,pending]};
const list={children:[],append(){}};
const document={querySelectorAll:s=>s==='[data-coverage-segment]'?[row]:[],
 getElementById:id=>id==='progress-events'?list:id==='progress-empty'?{hidden:false}:null,
 querySelector:s=>s==='[data-coverage-summary]'?summary:null,
 createElement:()=>({dataset:{},append(){},remove(){}}),body:{append(){}}};
const event=(category,score)=>({event_id:category,segment_id:'wake',kind:'check',at:'now',summary:'score',result:'ok',work_id:'work',revision:'abcdef0',evidence:[],development_score:{category,score,acceptance_eligible:false}});
const window={MAINLINE_PROGRESS:{events:[event('fluidity',8),event('audio_loudness',6)]}};
vm.runInNewContext(fs.readFileSync(process.argv[1],'utf8'),{document,window,setInterval(){},Date});
if(historical.textContent!=='8 · 开发'||!historical.removed||formal.textContent!=='9 · 正式'||summary.textContent!=='正式 1 项 · 开发 1 项 · 仅历史 0 项 · 待评 1 项')process.exit(1);
"""
        subprocess.run(['node', '-e', code, str(script)], check=True, cwd=ROOT, capture_output=True, text=True)


if __name__ == '__main__':
    unittest.main()
