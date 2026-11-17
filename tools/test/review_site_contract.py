"""Check the generated chapter report and its acceptance boundaries."""
from datetime import datetime
from html.parser import HTMLParser
import json
from pathlib import Path
import sys
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/testing'))
import export_review_site as site
import review_refresh


class Element:
    def __init__(self, tag, attrs=(), parent=None):
        self.tag, self.attrs, self.parent = tag, dict(attrs), parent
        self.children = []

    def find(self, predicate):
        return [e for child in self.children for e in ([child] if predicate(child) else []) + child.find(predicate)]


class Document(HTMLParser):
    def __init__(self, value):
        super().__init__()
        self.root = self.current = Element('root')
        self.feed(value)

    def handle_starttag(self, tag, attrs):
        child = Element(tag, attrs, self.current)
        self.current.children.append(child)
        if tag not in ('img', 'meta', 'link', 'br', 'hr', 'input', 'source'):
            self.current = child

    def handle_endtag(self, tag):
        element = self.current
        while element.parent:
            if element.tag == tag:
                self.current = element.parent
                return
            element = element.parent


def run():
    checks = []
    def check(label, condition):
        if not condition:
            raise AssertionError(label)
        checks.append({'check': label, 'passed': True})

    expected = [e['id'] for e in site.read_json(site.PLAN)['scenes']]
    data = site.read_json(site.OUT / 'score_records.json')
    for name in ('index.html', 'gameplay.html'):
        text = (site.OUT / name).read_text(encoding='utf-8')
        doc = Document(text).root
        cards = doc.find(lambda e: e.attrs.get('class') == 'segment')
        check(name + ': mainline order', [e.attrs['data-segment'] for e in cards] == expected)
        check(name + ': every first element is a trajectory', all(e.children[0].attrs.get('class', '').startswith('trajectory') for e in cards))
        check(name + ': all seven score cards', all(len(e.find(lambda n: n.attrs.get('class') == 'dimensions')[0].children) == 7 for e in cards))
        check(name + ': score cards visible without disclosure', all(e.find(lambda n: n.attrs.get('class') == 'acceptance-dimensions')[0].tag == 'div' for e in cards))
        check(name + ': image subscore summary present', all(e.find(lambda n: n.attrs.get('class') == 'semantic-score-summary') for e in cards))
        main = doc.find(lambda e: e.tag == 'main')[0]
        check(name + ': live progress is the final content section', main.children[-2].attrs.get('id') == 'live-progress' and main.children[-1].tag == 'script')
        check(name + ': auxiliary report tables removed', all(e.attrs.get('id') not in ('scores', 'references', 'reports') for e in doc.find(lambda n: True)))
        events = doc.find(lambda e: 'data-event-id' in e.attrs)
        check(name + ': existing progress rows are unique', len(events) == len({e.attrs['data-event-id'] for e in events}))

    check('all score rows follow the plan', [e['id'] for e in data['gameplay_scenes']] == expected)
    check('isolated records do not enter mainline cards', all(not r.get('source_isolated') for e in data['gameplay_scenes'] for r in e['history']))
    check('current reviews match exported commit', all(not e['current'] or data['revision'].startswith(e['current']['revision']) for e in data['gameplay_scenes']))
    check('missing review stays pending', site.review_result({}) == '待评')
    record = dict(status='complete', scores=[8] * 7)
    check('seven complete passing scores pass', site.review_result(record) == '合格')
    check('one missing dimension stays pending', site.review_result(dict(record, scores=[8] * 6 + [None])) == '待评')
    check('one failed dimension fails', site.review_result(dict(record, scores=[8] * 6 + [6])) == '不合格')
    check('actual blocked state fails', site.review_result(dict(record, status='blocked')) == '不合格')
    check('development evidence never passes', site.review_result(dict(record, acceptance_eligible=False)) == '待评')
    check('isolated evidence never passes', site.review_result(dict(record, source_isolated=True)) == '待评')
    pending = site.dimension_scores({})
    check('unscored rubric has seven pending cards', pending.count('待评') == 7)
    semantic = dict(modality='original_subtitled_stills', action_score=0, intent_score=7.5,
                    observation={'readability_score': 8}, mapping={'source_revision': '<untrusted>'})
    summary = site.semantic_score_summary(semantic)
    check('development subscore summary retains zero and escapes provenance', '>0<small>/10</small>' in summary and '&lt;untrusted&gt;' in summary)
    check('missing image review stays explicitly pending', '待评' in site.semantic_score_summary(None))
    editable = site.score_editor(dict(record, id='existing', score_reasons=['source'] * 7, summary='</script><script>alert(1)</script>'))
    check('recorded reviews expose escaped correction editor', 'class="score-editor"' in editable and '<script>alert(1)</script>' not in editable)
    check('missing reviews cannot be edited into acceptance scores', 'class="score-editor"' not in site.score_editor({}))

    progress = {'schema_version': 1, 'events': [dict(event_id='escaping-test', work_id='escaping-test', kind='change', at='2026-11-16T12:00:00+08:00', segment_id='project', revision='01234567', summary='</script><script>alert(1)</script>', result='test only', evidence=[])]}
    html = site.progress_section(progress, site.OUT / 'index.html')
    check('untrusted event summaries remain escaped', '<script>alert(1)</script>' not in html and '\\u003c/script>' in html)
    with patch.object(Path, 'rglob', side_effect=AssertionError('Capture scanning is forbidden in the idle loop')):
        review_refresh.source_snapshot()
    check('idle watcher never scans capture folders', True)

    records = [dict(id='earlier', segment_id='wake', revision='1111111', status='complete', scores=[9] * 7),
               dict(id='current', segment_id='wake', revision='2222222', status='complete', scores=[8] * 7),
               dict(id='audit', segment_id='wake', revision='2222222', status='blocked', scores=[6] * 7, supersedes='current')]
    entries = site.build_segments(records, [], {'events': []}, '2222222' + 'a' * 33)
    check('latest same-version audit replaces current verdict', entries[0]['current']['id'] == 'audit' and entries[0]['status'] == '不合格')
    check('prior reviews remain in history', len(entries[0]['history']) == 3)
    entries = site.build_segments(records, [], {'events': []}, '3333333' + 'a' * 33)
    check('new commits start pending without reusing old scores', entries[0]['current'] == {} and entries[0]['scores'] == [None] * 7)

    image = 'assets/data/test_scenarios/user_reference/formal_game_ui.png'
    image_hash = site.hashlib.sha256((ROOT / image).read_bytes()).hexdigest()
    event = dict(event_id='synthetic-capture', kind='check', segment_id='wake', evidence=[image, image],
                 evidence_sha256=[dict(path=image, sha256=image_hash)], summary='开发采集')
    with patch.object(site.provenance, 'verify_image') as verify, patch.object(site.visual_semantic_reviews, 'load', return_value=[]):
        entries = site.build_segments([], [], {'events': [event]}, 'a' * 40)
        check('MCP check images appear in their segment trajectory', len(entries[0]['development_images']) == 1)
        check('projected images require provenance validation', verify.call_count == 1)
        check('development trajectories preserve pending independent scores', entries[0]['status'] == '待评' and entries[0]['scores'] == [None] * 7)

    report = dict(passed=True, checks=len(checks), results=checks, generated_at=datetime.now().astimezone().isoformat(),
                  limitations=['Browser visual preview stopped at URL verification; this report checks generated structure and logic.'])
    output = ROOT / '.runtime/review-tests/site-contract-result.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(dict(passed=True, checks=len(checks), report=str(output))))


if __name__ == '__main__':
    run()
