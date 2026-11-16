"""Publish chapter-ordered player feedback, repairs and review history."""
from __future__ import annotations

import argparse
from datetime import datetime
from html import escape
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import quote, unquote, urlsplit
import yaml
from mainline_reviews import load_reviews, capture_time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'mcp'))
import capture_provenance as provenance
OUT = ROOT / 'artifacts/review'
DIMENSIONS = ['游玩流畅度', '界面字数', '动作与音效', '音频响度', '视听剧情替代', '参考图相似度', '剧情流畅性']
PLAN = ROOT / 'assets/data/test_scenarios/gameplay_review_plan.json'


def read_json(path, default=None):
    return json.loads(path.read_text(encoding='utf-8-sig')) if path.is_file() else default


def href(path, page):
    return quote(os.path.relpath(path.resolve(), page.parent.resolve()).replace(os.sep, '/'), safe='/#:')


def link(path, label, page):
    return f'<a href="{href(path, page)}">{escape(str(label))}</a>'


def project_file(value):
    path = provenance.project_path(value, ROOT)
    if not path.is_file():
        raise ValueError('Missing project evidence: ' + str(value))
    return path


def atomic_write(path, text):
    temporary = path.with_name(path.name + f'.{os.getpid()}.tmp')
    temporary.write_text(text, encoding='utf-8')
    temporary.replace(path)


def review_result(record):
    if not record or record.get('source_isolated') or record.get('acceptance_eligible') is False:
        return '待评'
    scores = record['scores']
    if record['status'] == 'blocked' or any(s is not None and s < 8 for s in scores):
        return '不合格'
    return '合格' if record['status'] == 'complete' and all(s is not None and s >= 8 for s in scores) else '待评'


def load_progress():
    path = ROOT / 'artifacts/acceptance/mainline_progress.yaml'
    data = yaml.safe_load(path.read_text(encoding='utf-8-sig')) if path.is_file() else {'schema_version': 1, 'events': []}
    if data.get('schema_version') != 1 or not isinstance(data.get('events'), list):
        raise ValueError('Invalid progress ledger')
    ids = set()
    for e in data['events']:
        if e['event_id'] in ids or e['kind'] not in ('change', 'check', 'complete'):
            raise ValueError('Invalid immutable progress event')
        if datetime.fromisoformat(e['at']).tzinfo is None:
            raise ValueError('Progress time requires timezone')
        ids.add(e['event_id'])
    return data


def load_changes():
    path = ROOT / 'artifacts/acceptance/mainline_changes.yaml'
    data = yaml.safe_load(path.read_text(encoding='utf-8-sig')) if path.is_file() else {'schema_version': 1, 'changes': []}
    if data.get('schema_version') != 1:
        raise ValueError('Invalid repair schema')
    valid = {s['id'] for s in read_json(PLAN)['scenes']}
    seen = set()
    for row in data['changes']:
        key = (row.get('segment_id'), row.get('revision'))
        if key in seen or key[0] not in valid or not re.fullmatch('[0-9a-f]{40}', key[1] or ''):
            raise ValueError('Invalid or duplicate mainline repair')
        if datetime.fromisoformat(row['time']).tzinfo is None or any(not row.get(k) for k in ('reason', 'before', 'after')):
            raise ValueError('Repair requires dated feedback and before/after facts')
        subprocess.run(['git', 'cat-file', '-e', row['revision'] + '^{commit}'], cwd=ROOT, stdin=subprocess.DEVNULL, capture_output=True, check=True)
        if row.get('fast_report'):
            project_file(row['fast_report'])
        for image in row.get('images', []):
            provenance.verify_image(project_file(image['path']), ROOT, allow_fixture=True)
        seen.add(key)
    return data['changes']


def trajectory(images, page, *, development=False):
    if not images:
        return '<div class="trajectory empty" aria-label="实机轨迹待采集"><span>起始 → 过程 → 结束</span><small>本段实机轨迹待采集</small></div>'
    frames = []
    for i, image in enumerate(images):
        path = project_file(image['path'])
        stage = '开发记录' if development else '单帧 · 过程待补' if len(images) == 1 else '起始' if i == 0 else '结束' if i == len(images) - 1 else '过程'
        caption = f'{i + 1:02d} · {stage} · ' + image.get('caption', '')
        if development:
            caption += ' · 开发快反，验收待评'
        frames.append(f'<figure><a class="zoom" href="{href(path, page)}"><img loading="lazy" src="{href(path, page)}" alt="{escape(caption, quote=True)}"></a><figcaption>{escape(caption)}</figcaption></figure>')
    return '<div class="trajectory" aria-label="实机轨迹序列">' + ''.join(frames) + '</div>'


def badge(result):
    cls = {'合格': 'pass', '不合格': 'fail', '待评': 'pending'}[result]
    return f'<strong class="verdict {cls}">{result}</strong>'


def dimension_scores(record, previous=None):
    cards = []
    for i, (name, score, reason) in enumerate(zip(DIMENSIONS, record.get('scores', [None] * 7), record.get('score_reasons', [None] * 7))):
        value = '待评' if score is None else f'{score:g}<small>/10</small>'
        delta = ''
        if previous and score is not None and previous['scores'][i] is not None:
            delta = f'<small>较上轮 {score - previous["scores"][i]:+g}</small>'
        cls = 'pending' if score is None else 'pass' if score >= 8 else 'fail'
        cards.append(f'<div class="dimension {cls}"><span>{name}</span><b>{value}</b>{delta}<p>{escape(str(reason or "等待独立实机评审"))}</p></div>')
    return '<div class="dimensions">' + ''.join(cards) + '</div>'


def review_details(record, page):
    body = '<p class="meta">' + escape(f"版本 {record['revision'][:8]} · {record['reviewer']} · 采集 {capture_time(record).isoformat(timespec='seconds')}") + '</p>'
    body += '<p>' + escape(record.get('summary', '')) + '</p>'
    files = [(record['report'], '评审原文'), (record['source']['on_receipt'], '启动回执'), (record['source']['start_receipt'], '新游戏回执')]
    if record.get('metrics'):
        files.append((record['metrics'], '本段性能与音频'))
    return body + '<p class="evidence-links">' + ''.join(link(project_file(p), title, page) for p, title in files) + '</p>'


def repair_feedback(changes, events, page):
    body = '<div class="feedback"><h3>本段反馈与修正</h3>'
    if not changes and not events:
        return body + '<p class="muted">等待本段主线游玩反馈。</p></div>'
    body += '<ol class="repairs">'
    for row in changes:
        body += '<li><b>' + escape(row['reason']) + '</b><p>反馈：' + escape(row['before']) + '</p><p>修正：' + escape(row['after']) + '</p>'
        if row.get('check_result'):
            body += '<p class="check-result">复测：' + escape(row['check_result']) + '</p>'
        if row.get('fast_report'):
            body += link(project_file(row['fast_report']), '快速检查原始结果', page)
        body += '<small>' + escape(row['time'] + ' · ' + row['revision'][:8]) + '</small></li>'
    for e in events:
        body += '<li><b>' + escape({'change': '修正', 'check': '检查', 'complete': '完成确认'}[e['kind']] + ' · ' + e['summary']) + '</b><p>' + escape(str(e['result'])) + '</p>'
        body += '<p class="evidence-links">' + ''.join(link(project_file(p), Path(p).name, page) for p in e.get('evidence', [])) + '</p>'
        body += '<small>' + escape(e['at'] + ' · ' + e['work_id']) + '</small></li>'
    return body + '</ol></div>'


def build_segments(reviews, changes, progress, revision):
    entries = []
    for scene in read_json(PLAN)['scenes']:
        history = [r for r in reviews if r['segment_id'] == scene['id'] and not r.get('source_isolated') and r.get('acceptance_eligible') is not False]
        superseded = {r['supersedes'] for r in history if r.get('supersedes')}
        effective = [r for r in history if r['id'] not in superseded]
        current = next((r for r in reversed(effective) if revision.startswith(r['revision'])), {})
        repairs = [r for r in changes if r['segment_id'] == scene['id']]
        events = [e for e in progress['events'] if e['segment_id'] == scene['id']]
        entries.append(dict(scene, current=current, history=history, changes=repairs, events=events,
                            modification_count=len(repairs) + sum(e['kind'] == 'change' for e in events),
                            development_images=[image for row in repairs for image in row.get('images', [])],
                            scores=current.get('scores', [None] * 7), status=review_result(current)))
    return entries


def segment_card(entry, number, page):
    current = entry['current']
    body = f'<article class="segment" id="trajectory-{entry["id"]}" data-segment="{entry["id"]}">'
    # The actual image sequence is the first element of every mainline segment.
    body += trajectory(current.get('images', []) or entry['development_images'], page, development=not bool(current))
    body += f'<div class="segment-heading"><div><small>第一章 · {number:02d} / 11</small><h2>{escape(entry["label"])}</h2></div><div class="conclusion">{badge(entry["status"])}<span>修改 <b>{entry["modification_count"]}</b> 次</span></div></div>'
    body += '<p class="meta">' + escape(' / '.join(entry['rooms'])) + ' · 当前版本 ' + ('独立评审已记录' if current else '待独立实机评审') + '</p>'
    body += dimension_scores(current)
    if current:
        body += review_details(current, page)
    body += repair_feedback(entry['changes'], entry['events'], page)
    if entry['history']:
        body += f'<details class="history"><summary>历次实机评分与对照 · {len(entry["history"])} 条</summary>'
        previous = None
        for r in entry['history']:
            body += '<div class="review-history">' + trajectory(r['images'], page) + badge(review_result(r)) + dimension_scores(r, previous) + review_details(r, page) + '</div>'
            previous = r
        body += '</details>'
    return body + '</article>'


def progress_section(progress, page):
    labels = {'change': '修改', 'check': '检测', 'complete': '完成确认'}
    rows = []
    for e in progress['events']:
        row = f'<li class="{e["kind"]}" data-event-id="{escape(e["event_id"], quote=True)}"><b>{escape(e["at"] + " · " + labels[e["kind"]] + " · " + e["summary"])}</b><p>{escape(str(e["result"]))}</p>'
        row += '<p class="evidence-links">' + ''.join(link(project_file(p), Path(p).name, page) for p in e.get('evidence', [])) + '</p>'
        row += '<small>' + escape(e['work_id'] + ' · ' + e['segment_id'] + ' · ' + e['revision'][:8]) + '</small>'
        if e['kind'] == 'complete':
            row += '<small>确认事件：' + escape('、'.join(e['related_event_ids'])) + '</small>'
        rows.append(row + '</li>')
    data = json.dumps(progress, ensure_ascii=False).replace('<', '\\u003c').replace('\u2028', '\\u2028').replace('\u2029', '\\u2029')
    return '<section id="live-progress" class="live-progress"><h2>实时进展</h2><p class="muted">每次修改、检测追加一行；工作完成后另行确认。每 5 秒更新。</p><ol id="progress-events">' + ''.join(rows) + '</ol><p id="progress-empty"' + (' hidden' if rows else '') + '>等待首条记录。</p></section><script>window.MAINLINE_PROGRESS=' + data + ';</script>'


def wrap(title, body, page, revision, navigation=''):
    return '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>' + escape(title) + '</title><link rel="stylesheet" href="' + href(OUT / 'review.css', page) + '"></head><body data-project-base="' + href(ROOT, page) + '/"><header><div class="brand">DUAL ONTOLOGY · CHAPTER 01</div><h1>' + escape(title) + '</h1><p>沿主线查看实机轨迹、逐项评分与反馈修正。</p><div class="header-links">' + link(OUT / 'index.html', '主线评分', page) + link(OUT / 'archive.html', '历史与辅助资料', page) + link(OUT / '评分总览.md', '带图 Markdown', page) + '<span>版本 ' + escape(revision[:8]) + '</span></div></header>' + navigation + '<main>' + body + '</main><dialog id="image-view"><button aria-label="关闭原图">关闭 · Esc</button><img alt="实机原图"></dialog><script src="' + href(OUT / 'review.js', page) + '"></script></body></html>'


def markdown(entries, revision, progress):
    lines = ['# 第一章主线评分', '', '版本：' + revision, '', f'[HTML 主线](<{(OUT / "index.html").as_posix()}>) · [历史与辅助资料](<{(OUT / "archive.html").as_posix()}>)', '']
    for i, entry in enumerate(entries, 1):
        lines += [f'## {i:02d} · {entry["label"]}', '']
        images = entry['current'].get('images', []) or entry['development_images']
        lines += [' '.join(f'![{image.get("caption", "实机轨迹")}](<{project_file(image["path"]).as_posix()}>)' for image in images) if images else '起始 → 过程 → 结束：实机轨迹待采集。', '']
        if images and not entry['current']:
            lines += ['开发快反画面；本段验收待独立评审。', '']
        lines += [f'**{entry["status"]} · 修改 {entry["modification_count"]} 次**', '', '| 分项 | 分数 | 原因 |', '| --- | --- | --- |']
        for name, score, reason in zip(DIMENSIONS, entry['scores'], entry['current'].get('score_reasons', [None] * 7)):
            lines.append('| ' + name + ' | ' + ('待评' if score is None else str(score)) + ' | ' + str(reason or '等待独立实机评审').replace('|', '／').replace('\n', ' ') + ' |')
        lines += ['', '### 本段反馈与修正', '']
        for row in entry['changes']:
            lines += ['- ' + row['reason'] + '（' + row['revision'][:8] + '）：' + row['before'] + ' → ' + row['after']]
            if row.get('check_result'):
                lines += ['  复测：' + row['check_result']]
        for e in entry['events']:
            lines += ['- ' + e['summary'] + '：' + str(e['result'])]
        if not entry['changes'] and not entry['events']:
            lines += ['等待本段主线游玩反馈。']
        for r in entry['history']:
            lines += ['', '### 历史 ' + r['revision'][:8] + ' · ' + review_result(r), '', ' '.join(f'![{im.get("caption", "实机轨迹")}](<{project_file(im["path"]).as_posix()}>)' for im in r['images']), '', '[原始评审](<' + project_file(r['report']).as_posix() + '>)', '']
    lines += ['', '## 实时进展', '']
    for e in progress['events']:
        lines += ['- ' + e['at'] + ' · ' + e['kind'] + ' · ' + e['work_id'] + '：' + e['summary'] + '；' + str(e['result'])]
        if e['kind'] == 'complete':
            lines += ['  完成确认：' + '、'.join(e['related_event_ids'])]
    return '\n'.join(lines) + '\n'


def archive_page(reviews, revision):
    page = OUT / 'archive.html'
    old = read_json(OUT / 'archive-score-records.json', {})
    body = '<section><h2>历史与辅助资料</h2><p>原始评分、采集和报告保留在此。</p>'
    isolated = [r for r in reviews if r.get('source_isolated') or r.get('acceptance_eligible') is False]
    body += f'<details><summary>来源隔离的历史主线记录 · {len(isolated)} 条</summary><ul>'
    for r in isolated:
        body += '<li>' + escape(r['segment_id'] + ' · ' + r['revision'][:8] + ' · ' + r['id']) + ' · ' + link(project_file(r['report']), '原始记录', page) + '</li>'
    body += '</ul></details><details><summary>辅助采集与旧指标</summary><p>' + link(OUT / 'archive-score-records.json', '原辅助指标快照', page) + '</p><ul>'
    for run in old.get('runs', []):
        body += '<li>' + escape(run.get('label', run['run_path']) + ' · ' + run.get('bundle', '')) + ' · ' + link(provenance.project_path(run['run_path'], ROOT), '原始采集目录', page) + '</li>'
    body += '</ul></details><details><summary>原图文报告</summary><ul>'
    for path in sorted((OUT / 'reports').glob('*.html')):
        body += '<li>' + link(path, path.stem, page) + '</li>'
    body += '</ul></details><details><summary>Astra 参考资料</summary><ul>'
    for ref in read_json(ROOT / 'assets/data/test_scenarios/reference_manifest.json', {}).get('entries', []):
        if ref.get('reference_image') and (ROOT / ref['reference_image']).is_file():
            body += '<li>' + link(project_file(ref['reference_image']), ref.get('label', ref['reference_image']), page) + '</li>'
    atomic_write(page, wrap('历史与辅助资料', body + '</ul></details></section>', page, revision))


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links, self.ids = [], set()

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs:
            self.ids.add(attrs['id'])
        self.links += [(tag, attrs[k]) for k in ('href', 'src') if k in attrs]


def validate_export():
    documents = {}
    for path in OUT.rglob('*.html'):
        doc = Links()
        doc.feed(path.read_text(encoding='utf-8-sig'))
        documents[path.resolve()] = doc
    broken, checked = [], 0
    for page, doc in documents.items():
        for tag, url in doc.links:
            target = urlsplit(url)
            if target.scheme or url == '#':
                continue
            checked += 1
            path = (page.parent / unquote(target.path)).resolve() if target.path else page
            if not path.is_relative_to(ROOT) or not path.exists() or (target.fragment and path in documents and target.fragment not in documents[path].ids):
                broken.append({'page': str(page), 'url': url})
    for page in OUT.rglob('*.md'):
        for url in re.findall(r'!\[[^\]]*\]\(([^)]+)\)', page.read_text(encoding='utf-8-sig')):
            value = url.strip().strip('<>')
            if urlsplit(value).scheme in ('http', 'https'):
                continue
            path = Path(unquote(value))
            if not path.is_absolute():
                path = page.parent / path
            if not path.resolve().is_relative_to(ROOT) or not path.is_file():
                broken.append({'page': str(page), 'image': url})
    data = read_json(OUT / 'score_records.json')
    expected = [s['id'] for s in read_json(PLAN)['scenes']]
    if [e['id'] for e in data['gameplay_scenes']] != expected or any(len(e['scores']) != 7 for e in data['gameplay_scenes']):
        raise ValueError('Invalid mainline order or scores')
    passed = all(e['status'] == '合格' for e in data['gameplay_scenes'])
    if data['overall_passed'] != passed:
        raise ValueError('Mainline acceptance inconsistent')
    report = dict(generated_at=datetime.now().astimezone().isoformat(timespec='seconds'), html_files=len(documents), markdown_files=len(list(OUT.rglob('*.md'))), local_links_checked=checked, broken_links=broken, mainline_segments=len(expected), overall_passed=passed)
    atomic_write(OUT / 'export-verification.json', json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    if broken:
        raise ValueError(f'{len(broken)} broken local links; see export-verification.json')
    return report


def render():
    provenance.assert_runtime_root(ROOT)
    OUT.mkdir(parents=True, exist_ok=True)
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, stdin=subprocess.DEVNULL, text=True).strip()
    progress, reviews = load_progress(), load_reviews(ROOT)
    entries = build_segments(reviews, load_changes(), progress, revision)
    previous = read_json(OUT / 'score_records.json', {})
    if previous.get('runs') and not (OUT / 'archive-score-records.json').exists():
        atomic_write(OUT / 'archive-score-records.json', json.dumps(previous, ensure_ascii=False, indent=2) + '\n')
    if not (OUT / 'archive-score-records.json').exists():
        atomic_write(OUT / 'archive-score-records.json', '{}\n')
    for name in ('review.css', 'review.js'):
        atomic_write(OUT / name, (Path(__file__).parent / name).read_text(encoding='utf-8'))
    for filename in ('index.html', 'gameplay.html'):
        page = OUT / filename
        nav = '<nav class="chapter-nav" aria-label="主线剧情顺序">' + ''.join(f'<a href="#trajectory-{e["id"]}"><span>{i:02d}</span>{escape(e["label"])}</a>' for i, e in enumerate(entries, 1)) + '</nav>'
        body = ''.join(segment_card(e, i, page) for i, e in enumerate(entries, 1)) + progress_section(progress, page)
        atomic_write(page, wrap('第一章 · 主线评分与修正', body, page, revision, nav))
    archive_page(reviews, revision)
    for name in ('评分总览.md', '游戏场景评分.md'):
        atomic_write(OUT / name, markdown(entries, revision, progress))
    data = dict(schema_version=2, generated_at=datetime.now().astimezone().isoformat(timespec='seconds'), revision=revision, dimensions=DIMENSIONS, overall_passed=all(e['status'] == '合格' for e in entries), gameplay_scenes=entries)
    atomic_write(OUT / 'score_records.json', json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    if not (OUT / 'live-progress.js').exists():
        atomic_write(OUT / 'live-progress.js', 'window.MAINLINE_PROGRESS=' + json.dumps(progress, ensure_ascii=False).replace('<', '\\u003c') + ';\n')
    return validate_export()


def main():
    global OUT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=OUT)
    OUT = provenance.project_path(parser.parse_args().output, ROOT)
    from review_refresh import watcher_lock
    with watcher_lock('render.lock') as acquired:
        if not acquired:
            raise RuntimeError('Another milestone export is active; retry after it completes')
        report = render()
    print(json.dumps(report, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
