"""Publish chapter-ordered player feedback, repairs and review history."""
from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
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
import visual_semantic_reviews
import mainline_recordings

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


def markdown_href(path, page):
    """Return a portable relative Markdown target for the generated report."""
    return href(path, page)


def link(path, label, page):
    return f'<a href="{href(path, page)}">{escape(str(label))}</a>'


def project_file(value):
    path = provenance.project_path(value, ROOT)
    if not path.is_file():
        raise ValueError('Missing project evidence: ' + str(value))
    return path


def audit_progress(progress):
    """Audit immutable progress evidence at milestone export, not on each update.

    Missing, changed and unhashed evidence remain visible as gaps. None may be
    linked, promoted to a trajectory or used to certify an overall pass. Formal
    player-review and capture validation remain strict and separate.
    """
    counts = {key: 0 for key in ('valid', 'missing', 'changed', 'unverified')}
    events, issues, cache = {}, [], {}
    for event in progress.get('events', []):
        event_id = event.get('event_id')
        if not isinstance(event_id, str) or not event_id or event_id in events:
            raise ValueError('Evidence audit requires unique progress event IDs')
        expected = {}
        for item in event.get('evidence_sha256', []):
            if not isinstance(item, dict) or not isinstance(item.get('path'), str):
                continue
            value, digest = item['path'], item.get('sha256')
            expected[value] = digest if value not in expected or expected[value] == digest else None
        rows = []
        for value in event.get('evidence', []):
            if not isinstance(value, str):
                raise ValueError('Evidence paths must be strings')
            path = provenance.project_path(value, ROOT)
            relative = path.relative_to(ROOT).as_posix()
            recorded = expected.get(relative, expected.get(value))
            actual = None
            if not path.is_file():
                status = 'missing'
            elif not isinstance(recorded, str) or not re.fullmatch(r'[0-9a-f]{64}', recorded):
                status = 'unverified'
            else:
                before = path.stat()
                key = (path, before.st_size, before.st_mtime_ns)
                if key not in cache:
                    digest = hashlib.sha256()
                    with path.open('rb') as stream:
                        for block in iter(lambda: stream.read(1024 * 1024), b''):
                            digest.update(block)
                    after = path.stat()
                    cache[key] = digest.hexdigest() if (before.st_size, before.st_mtime_ns) == (after.st_size, after.st_mtime_ns) else None
                actual = cache[key]
                status = 'unverified' if actual is None else 'valid' if actual == recorded else 'changed'
            row = {'path': relative, 'status': status, 'expected_sha256': recorded, 'actual_sha256': actual}
            counts[status] += 1
            rows.append(row)
            if status != 'valid':
                issues.append(dict(event_id=event_id, **row))
        events[event_id] = rows
    return {'complete': not issues, 'counts': counts, 'events': events, 'issues': issues}


def progress_evidence(event, page, audit=None):
    audit = audit if audit is not None else audit_progress({'events': [event]})
    labels = {'missing': '证据缺失', 'changed': '内容已变化', 'unverified': '缺少校验值或文件正在变化'}
    rendered = []
    for item in audit['events'].get(event['event_id'], []):
        if item['status'] == 'valid':
            rendered.append(link(project_file(item['path']), Path(item['path']).name, page))
            continue
        recorded = item.get('expected_sha256') or '未记录'
        detail = f"{labels[item['status']]}：{item['path']}（记录 SHA-256：{recorded}）"
        if item.get('actual_sha256'):
            detail += '（当前 SHA-256：' + item['actual_sha256'] + '）'
        rendered.append('<span class="evidence-issue">' + escape(detail) + '</span>')
    return ''.join(rendered)


def overall_passed(entries, audit):
    # A complete current review cannot hide an incomplete historical audit.
    return bool(entries) and bool(audit.get('complete')) and all(e['status'] == '合格' for e in entries)


def evidence_banner(audit, page):
    counts = audit['counts']
    status = '完整' if audit['complete'] else '不完整 · 不得视为验收通过'
    detail = f"已核验 {counts['valid']} 项；缺失 {counts['missing']} 项，内容变化 {counts['changed']} 项，未核验 {counts['unverified']} 项。"
    return '<aside class="evidence-banner"><b>历史证据：' + status + '</b><p>' + escape(detail) + ' 缺失或变化项仅以文字标记，不提供失效链接。</p>' + link(OUT / 'evidence-audit.json', '查看证据审计清单', page) + '</aside>'


def markdown_links(text):
    return [value.strip().strip('<>') for value in re.findall(r'!?\[[^\]]*\]\(([^)]+)\)', text)]


def atomic_write(path, text):
    temporary = path.with_name(path.name + f'.{os.getpid()}.tmp')
    temporary.write_text(text, encoding='utf-8')
    temporary.replace(path)


def development_image_origin(path):
    """Preserve clearly labelled, hash-checked historical fixtures after relocation.

    This is an archive display rule, not a substitute for verify_image: the old
    host/PID cannot be revalidated and the image can never qualify as acceptance.
    Never open the original host path recorded in the sidecar.
    """
    try:
        provenance.verify_image(path, ROOT, allow_fixture=True)
        return 'current-host-verified'
    except ValueError as original:
        sidecar = path.with_suffix(path.suffix + '.json')
        if not sidecar.is_file():
            raise original
        data = json.loads(sidecar.read_text(encoding='utf-8-sig'))
        source = data.get('source_identity') or {}
        former_root = str(source.get('project_root', '')).replace('\\', '/').rstrip('/')
        current = provenance.project_identity(ROOT)
        current_root = str(ROOT).replace('\\', '/').rstrip('/')
        if (former_root.casefold() == current_root.casefold()
                or not former_root.casefold().endswith('/dual_ontology_world_reconstruct_2')
                or data.get('acceptance_eligible') is not False
                or source.get('project_sha256') != current['project_sha256']
                or source.get('configured_main_scene') != current['configured_main_scene']
                or not isinstance(source.get('process_id'), int) or source['process_id'] <= 0
                or data.get('image_sha256') != hashlib.sha256(path.read_bytes()).hexdigest()):
            raise original
        return 'historical-other-host-unverified'


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
            origin = development_image_origin(project_file(image['path']))
            image['archive_origin'] = origin
            if origin == 'historical-other-host-unverified':
                image['caption'] = image.get('caption', '') + ' · 跨主机历史图：原 PID 不可复核，非验收证据'
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


def score_editor(record):
    if not record:
        return '<p class="muted">评分修订将在独立实机评审记录产生后开放。</p>'
    data = escape(json.dumps(record, ensure_ascii=False), quote=True)
    labels = escape(json.dumps(DIMENSIONS, ensure_ascii=False), quote=True)
    return ('<details class="score-editor" data-review="' + data + '" data-labels="' + labels + '">'
            '<summary>修订这条评分</summary>'
            '<p class="meta">生成修订请求草稿；提交至 review_append 后通过来源校验并保留原记录。</p>'
            '<div class="score-editor-fields"></div></details>')


def semantic_score_summary(review):
    if not review:
        return '<div class="semantic-score-summary"><h3>图片盲读分项 · 开发评审</h3><p class="muted">动作一致度、意图理解与可读性：待评。</p></div>'
    intent = '意图理解（含原字幕）' if review['modality'] == 'original_subtitled_stills' else '意图一致度'
    scores = [('动作一致度', review['action_score']), (intent, review['intent_score']),
              ('测试者自评可读性', review['observation']['readability_score'])]
    cards = ''.join('<div class="semantic-subscore"><span>' + escape(label) + '</span><b>' +
                    escape(str(score)) + '<small>/10</small></b></div>' for label, score in scores)
    revision = review['mapping'].get('source_revision') or '历史开发素材'
    return ('<div class="semantic-score-summary"><h3>图片盲读分项 · 开发评审</h3>'
            '<p class="meta">图片版本 ' + escape(revision) + ' · 动作与意图按目标平均；可读性为测试者自评。</p>'
            '<div class="semantic-subscore-grid">' + cards + '</div></div>')


def review_details(record, page):
    body = '<p class="meta">' + escape(f"版本 {record['revision'][:8]} · {record['reviewer']} · 采集 {capture_time(record).isoformat(timespec='seconds')}") + '</p>'
    body += '<p>' + escape(record.get('summary', '')) + '</p>'
    files = [(record['report'], '评审原文'), (record['source']['on_receipt'], '启动回执'), (record['source']['start_receipt'], '新游戏回执')]
    if record.get('metrics'):
        files.append((record['metrics'], '本段性能与音频'))
    return body + '<p class="evidence-links">' + ''.join(link(project_file(p), title, page) for p, title in files) + '</p>'


def repair_feedback(changes, events, page, audit):
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
        body += '<p class="evidence-links">' + progress_evidence(e, page, audit) + '</p>'
        body += '<small>' + escape(e['at'] + ' · ' + e['work_id']) + '</small></li>'
    return body + '</ol></div>'


def build_segments(reviews, changes, progress, revision, audit=None):
    entries = []
    audit = audit if audit is not None else audit_progress(progress)
    semantic_reviews = visual_semantic_reviews.load(ROOT)
    # Do not load a missing or changed capture receipt as a validated recording.
    recording_events = []
    for event in progress['events']:
        allowed = [item['path'] for item in audit['events'][event['event_id']] if item['status'] == 'valid']
        recording_events.append(dict(event, evidence=allowed))
    recordings = mainline_recordings.load(recording_events, ROOT)
    for scene in read_json(PLAN)['scenes']:
        history = [r for r in reviews if r['segment_id'] == scene['id'] and not r.get('source_isolated') and r.get('acceptance_eligible') is not False]
        superseded = {r['supersedes'] for r in history if r.get('supersedes')}
        effective = [r for r in history if r['id'] not in superseded]
        current = next((r for r in reversed(effective) if revision.startswith(r['revision'])), {})
        repairs = [r for r in changes if r['segment_id'] == scene['id']]
        events = [e for e in progress['events'] if e['segment_id'] == scene['id']]
        development_images = [image for row in repairs for image in row.get('images', [])]
        seen_images = {project_file(image['path']) for image in development_images}
        for event in events:
            if event['kind'] != 'check':
                continue
            for evidence in audit['events'][event['event_id']]:
                if evidence['status'] != 'valid':
                    continue
                path = project_file(evidence['path'])
                if path.suffix.lower() not in ('.png', '.jpg', '.jpeg') or path in seen_images:
                    continue
                provenance.verify_image(path, ROOT, allow_fixture=True)
                development_images.append({'path': evidence['path'], 'caption': event['summary'] + ' · ' + path.stem})
                seen_images.add(path)
        semantic_history = [r for r in semantic_reviews if r['segment_id'] == scene['id']]
        semantic = semantic_history[-1] if semantic_history else None
        entries.append(dict(scene, current=current, history=history, changes=repairs, events=events,
                            recordings=recordings.get(scene['id'],[]),
                            semantic=semantic, semantic_history=semantic_history,
                            modification_count=len(repairs) + sum(e['kind'] == 'change' for e in events),
                            development_images=development_images,
                            scores=current.get('scores', [None] * 7), status=review_result(current)))
    return entries


def semantic_images(entry):
    if entry.get('recordings'):
        return entry['recordings'][-1]['images']
    review = entry.get('semantic')
    if not review:
        return entry['development_images']
    return [dict(path=f['original'],caption=f['frame_id']) for f in review['mapping']['frames']]


def recording_details(record, page):
    coverage = record['coverage_data']
    body = '<section class="continuous-recording"><h3>完整过程 · 原速与原字幕</h3>'
    target_phase = 'look' if record['segment_id']=='wake' else 'join'
    poster = next((f for f in record['images'] if ' · '+target_phase in f['caption']),record['images'][0])
    body += '<video controls preload="metadata" playsinline poster="'+href(project_file(poster['path']),page)+'" src="'+href(project_file(record['video']),page)+'" style="width:100%;max-height:560px;background:#101417"></video>'
    body += '<p>覆盖检查：<b>完整</b> · 连续视频 '+str(round(record['end_s']-record['start_s'],1))+' 秒 · 本段对白 '+str(len(record['subtitles']))+' 个显示片段。</p>'
    body += '<p class="meta">生产流程开发录制；画面采集为12帧/秒，性能数据包含采集开销。完整实机验收另行评审。</p>'
    if coverage.get('audio_signal_present') is False:
        body += '<p class="meta">本轮录制音轨无信号，音频表现与响度保持待评。</p>'
    body += '<details><summary>阶段与对白时间轴 · 点击时间回看片段</summary><ol class="dialogue-timeline">'
    rows = [(e['time_s'],e['state'].split(':',1)[1]) for e in record['phases']]
    rows += [(s['start_s'],s['speaker']+'：'+s['text']) for s in record['subtitles']]
    for time, text in sorted(rows):
        offset = max(0,time-record['start_s'])
        body += '<li><a href="'+href(project_file(record['video']),page)+'#t='+str(round(offset,2))+'">'+f'{offset:.1f}s'+'</a> · '+escape(text)+'</li>'
    body += '</ol></details><p class="evidence-links">'+link(project_file(record['coverage']),'完整覆盖清单',page)+link(project_file(record['sequence']),'原始逐帧与对白记录',page)+link(project_file(record['full_video']),'第一二段连续视频',page)+link(project_file(record['end_snapshot']),'结束快照',page)+'</p></section>'
    return body


def semantic_details(review, page):
    observation = review['observation']
    verdict = '合格' if min(review['action_score'],review['intent_score']) >= 8 else '不合格'
    body = '<div class="semantic-review"><div class="semantic-heading"><h3>图片盲读 · 动作与意图对照</h3>' + badge(verdict) + '</div>'
    intent_label = '意图理解（含原字幕）' if review['modality']=='original_subtitled_stills' else '意图一致度'
    body += '<p class="semantic-scores">动作一致度 <b>' + str(review['action_score']) + '/10</b>　'+intent_label+' <b>' + str(review['intent_score']) + '/10</b></p>'
    modality = '原字幕静态图 · 未提供剧本' if review['modality']=='original_subtitled_stills' else '遮字静态图'
    body += '<p class="meta">独立 Terra · '+modality+' · 无音频 · 图片版本 ' + escape(review['mapping'].get('source_revision') or '历史开发素材') + ' · 开发评审</p>'
    body += '<p class="meta">' + escape(review['mapping'].get('source_note','')) + ' · 测试者自评可读性 ' + str(observation['readability_score']) + '/10</p>'
    body += '<p><b>评审结论：</b>' + escape(review['conclusion']) + '</p>'
    body += '<div class="blind-original"><h4>测试者原始判断</h4><p><b>看到的动作：</b>' + escape(observation['action_observed']) + '</p><p><b>猜测的意图：</b>' + escape(observation['intent_guessed']) + '</p><p><b>无法确认：</b>' + escape(observation['uncertainty']) + '</p></div>'
    if observation.get('visual_only'):
        body += '<p><b>只看画面读到：</b>'+escape(observation['visual_only'])+'</p><p><b>字幕补充理解：</b>'+escape(observation['dialogue_understanding'])+'</p>'
    body += '<div class="semantic-table-scroll"><table class="semantic-table"><thead><tr><th>对应图片／测试者原话</th><th>剧情实际动作与意图</th><th>差异与评分</th></tr></thead><tbody>'
    for item in review['comparisons']:
        ids = set(item['frame_ids'])
        claims = [c for c in observation['claims'] if ids.intersection(c['frame_ids'])]
        body += '<tr><td><p class="evidence-links">'
        for fid in item['frame_ids']:
            f = review['frames'][fid]
            body += link(project_file(f['original']),fid+' 原图',page) + link(project_file(f['masked']),'评审图',page)
        body += '</p>'
        if not claims:
            body += '<p>测试者未单独描述这些帧；使用本组原始判断对照。</p>'
        for claim in claims:
            body += '<p><b>动作：</b>' + escape(claim['action_observed']) + '<br><b>意图：</b>' + escape(claim['intent_guessed']) + '</p>'
            if claim.get('evidence_basis'):
                body += '<p class="meta">判断依据：'+{'visual':'直接画面','dialogue':'字幕信息','both':'画面与字幕'}[claim['evidence_basis']]+'</p>'
        body += '</td><td><p><b>动作目标：</b>' + escape(item['expected_action']) + '</p><p><b>意图目标：</b>' + escape(item['expected_intent']) + '</p><p><b>当前实现：</b>' + escape(item['implementation']) + '</p>'
        body += '<details><summary>设定来源</summary>'
        for source in item['truth_sources']:
            body += '<p>' + link(project_file(source['path']),source['locator'],page) + '</p>'
        body += '</details></td><td><p>' + escape(item['difference']) + '</p><p>动作 <b>' + str(item['action_score']) + '/10</b> · 意图 <b>' + str(item['intent_score']) + '/10</b></p></td></tr>'
    body += '</tbody></table></div><p class="meta">计分：每项目标相符10、部分相符5、漏读或误读0；动作与意图分别取各项目标均值，均达8分合格。对应关系由主智能体依据盲读原文及设定评分。</p>'
    body += '<p><b>下一次修正：</b>' + escape(review['next_fix']) + '</p>'
    body += '<p class="evidence-links">' + link(project_file(review['observations']),'Terra 完整原始记录',page) + link(project_file(review['record_path']),'对照评分记录',page) + link(project_file(review['input_manifest']),'匿名输入清单',page) + '</p></div>'
    return body


def segment_card(entry, number, page, audit):
    current = entry['current']
    body = f'<article class="segment" id="trajectory-{entry["id"]}" data-segment="{entry["id"]}">'
    # The actual image sequence is the first element of every mainline segment.
    body += trajectory(current.get('images', []) or semantic_images(entry), page, development=not bool(current))
    conclusion = entry['status']
    conclusion_label = '实机验收'
    if entry.get('semantic'):
        conclusion = '合格' if min(entry['semantic']['action_score'],entry['semantic']['intent_score']) >= 8 else '不合格'
        conclusion_label = '图片盲读'
    body += f'<div class="segment-heading"><div><small>第一章 · {number:02d} / 11</small><h2>{escape(entry["label"])}</h2></div><div class="conclusion"><span>{conclusion_label}</span>{badge(conclusion)}<span>修改 <b>{entry["modification_count"]}</b> 次</span></div></div>'
    body += '<p class="meta">' + escape(' / '.join(entry['rooms'])) + ' · 当前版本 ' + ('独立评审已记录' if current else '待独立实机评审') + '</p>'
    body += '<div class="acceptance-dimensions"><h3>完整实机七项验收 · ' + entry['status'] + '</h3>'
    body += '<p class="meta">当前版本独立实机评分；缺少评审的分项显示待评。</p>' + dimension_scores(current) + '</div>'
    body += score_editor(current)
    body += semantic_score_summary(entry.get('semantic'))
    if entry.get('recordings'):
        body += recording_details(entry['recordings'][-1],page)
    if entry.get('semantic'):
        if entry.get('recordings') and entry['semantic']['modality']!='original_subtitled_stills':
            body += '<p class="meta">下方保留上一轮抽帧评审，评分对应其原始素材；本轮完整录制评审随后追加。</p>'
        body += semantic_details(entry['semantic'],page)
    else:
        body += '<p class="muted">图片动作／意图盲读：等待独立测试者记录。</p>'
    if current:
        body += review_details(current, page)
    body += repair_feedback(entry['changes'], entry['events'], page, audit)
    if entry['history']:
        body += f'<details class="history"><summary>历次实机评分与对照 · {len(entry["history"])} 条</summary>'
        previous = None
        for r in entry['history']:
            body += '<div class="review-history">' + trajectory(r['images'], page) + badge(review_result(r)) + dimension_scores(r, previous) + review_details(r, page) + '</div>'
            previous = r
        body += '</details>'
    if len(entry.get('semantic_history',[])) > 1:
        body += '<details><summary>历次图片盲读对照</summary>' + ''.join(semantic_details(r,page) for r in entry['semantic_history'][:-1]) + '</details>'
    if len(entry.get('recordings',[])) > 1:
        body += '<details><summary>历次完整录制</summary>'+''.join(trajectory(r['images'],page,development=True)+recording_details(r,page) for r in entry['recordings'][:-1])+'</details>'
    return body + '</article>'


def progress_section(progress, page, audit=None):
    audit = audit if audit is not None else audit_progress(progress)
    labels = {'change': '修改', 'check': '检测', 'complete': '完成确认'}
    rows = []
    for e in progress['events']:
        row = f'<li class="{e["kind"]}" data-event-id="{escape(e["event_id"], quote=True)}"><b>{escape(e["at"] + " · " + labels[e["kind"]] + " · " + e["summary"])}</b><p>{escape(str(e["result"]))}</p>'
        row += '<p class="evidence-links">' + progress_evidence(e, page, audit) + '</p>'
        row += '<small>' + escape(e['work_id'] + ' · ' + e['segment_id'] + ' · ' + e['revision'][:8]) + '</small>'
        if e['kind'] == 'complete':
            row += '<small>确认事件：' + escape('、'.join(e['related_event_ids'])) + '</small>'
        rows.append(row + '</li>')
    data = json.dumps(progress, ensure_ascii=False).replace('<', '\\u003c').replace('\u2028', '\\u2028').replace('\u2029', '\\u2029')
    return '<section id="live-progress" class="live-progress"><h2>实时进展</h2><p class="muted">每次修改、检测追加一行；工作完成后另行确认。每 5 秒更新。</p><ol id="progress-events">' + ''.join(rows) + '</ol><p id="progress-empty"' + (' hidden' if rows else '') + '>等待首条记录。</p></section><script>window.MAINLINE_PROGRESS=' + data + ';</script>'


def wrap(title, body, page, revision, navigation=''):
    return '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>' + escape(title) + '</title><link rel="stylesheet" href="' + href(OUT / 'review.css', page) + '"></head><body data-project-base="' + href(ROOT, page) + '/"><header><div class="brand">DUAL ONTOLOGY · CHAPTER 01</div><h1>' + escape(title) + '</h1><p>沿主线查看实机轨迹、逐项评分与反馈修正。</p><div class="header-links">' + link(OUT / 'index.html', '主线评分', page) + link(OUT / 'archive.html', '历史与辅助资料', page) + link(OUT / '评分总览.md', '带图 Markdown', page) + '<span>版本 ' + escape(revision[:8]) + '</span></div></header>' + navigation + '<main>' + body + '</main><dialog id="image-view"><button aria-label="关闭原图">关闭 · Esc</button><img alt="实机原图"></dialog><script src="' + href(OUT / 'review.js', page) + '"></script></body></html>'


def markdown(entries, revision, progress, audit):
    page = OUT / '评分总览.md'
    integrity = '完整' if audit['complete'] else '不完整；不得视为验收通过'
    lines = ['# 第一章主线评分', '', '版本：' + revision, '', '**历史证据：' + integrity + '**', '', f'[证据审计](<{markdown_href(OUT / "evidence-audit.json", page)}>) · [HTML 主线](<{markdown_href(OUT / "index.html", page)}>) · [历史与辅助资料](<{markdown_href(OUT / "archive.html", page)}>)', '']
    for i, entry in enumerate(entries, 1):
        lines += [f'## {i:02d} · {entry["label"]}', '']
        images = entry['current'].get('images', []) or semantic_images(entry)
        lines += [' '.join(f'![{image.get("caption", "实机轨迹")}](<{markdown_href(project_file(image["path"]), page)}>)' for image in images) if images else '起始 → 过程 → 结束：实机轨迹待采集。', '']
        if images and not entry['current']:
            lines += ['开发快反画面；本段验收待独立评审。', '']
        lines += [f'**完整实机验收：{entry["status"]} · 修改 {entry["modification_count"]} 次**', '']
        if entry.get('recordings'):
            recording=entry['recordings'][-1]
            lines += ['完整过程已录制，保留原速与原字幕；本段对白显示片段 '+str(len(recording['subtitles']))+' 个。', '',
                      '[本段连续视频](<'+markdown_href(project_file(recording['video']), page)+'>) · [覆盖清单](<'+markdown_href(project_file(recording['coverage']), page)+'>) · [第一二段完整视频](<'+markdown_href(project_file(recording['full_video']), page)+'>)', '']
        if entry.get('recordings'):
            capture = entry['recordings'][-1]
            lines += ['完整原速录制、原字幕对白覆盖：完整。', '', '[本段视频](<'+markdown_href(project_file(capture['video']), page)+'>) · [覆盖清单](<'+markdown_href(project_file(capture['coverage']), page)+'>)', '']
        semantic = entry.get('semantic')
        if semantic:
            observation = semantic['observation']
            lines += ['### 图片盲读动作／意图对照','', f'动作一致度：{semantic["action_score"]}/10；意图一致度：{semantic["intent_score"]}/10。', '', '评审结论：'+semantic['conclusion'], '', '测试者看到的动作：'+observation['action_observed'], '', '测试者猜测的意图：'+observation['intent_guessed'], '', '测试者无法确认：'+observation['uncertainty'], '', '| 图片 | 实际动作／意图 | 差异 | 动作分／意图分 |','| --- | --- | --- | --- |']
            if observation.get('visual_only'):
                lines[-2:-2] = ['只看画面读到：'+observation['visual_only'],'','字幕补充理解：'+observation['dialogue_understanding'],'']
            for c in semantic['comparisons']:
                cell=lambda s:str(s).replace('|','／').replace('\n',' ')
                lines.append('| '+'、'.join(c['frame_ids'])+' | '+cell(c['expected_action']+'；'+c['expected_intent'])+' | '+cell(c['difference'])+f' | {c["action_score"]}／{c["intent_score"]} |')
            lines += ['', '下一次修正：'+semantic['next_fix'],'', '[Terra 原始记录](<'+markdown_href(project_file(semantic['observations']), page)+'>)', '']
        lines += ['| 实机验收分项 | 分数 | 原因 |', '| --- | --- | --- |']
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
            lines += ['', '### 历史 ' + r['revision'][:8] + ' · ' + review_result(r), '', ' '.join(f'![{im.get("caption", "实机轨迹")}](<{markdown_href(project_file(im["path"]), page)}>)' for im in r['images']), '', '[原始评审](<' + markdown_href(project_file(r['report']), page) + '>)', '']
    lines += ['', '## 实时进展', '']
    for e in progress['events']:
        lines += ['- ' + e['at'] + ' · ' + e['kind'] + ' · ' + e['work_id'] + '：' + e['summary'] + '；' + str(e['result'])]
        for item in audit['events'][e['event_id']]:
            if item['status'] != 'valid':
                label = {'missing': '证据缺失', 'changed': '内容已变化', 'unverified': '未核验'}[item['status']]
                lines += ['  - **' + label + '**：`' + item['path'].replace('`', '') + '`；记录 SHA-256：`' + str(item.get('expected_sha256') or '未记录') + '`']
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
        for url in markdown_links(page.read_text(encoding='utf-8-sig')):
            if os.name == 'nt' and re.match(r'^[A-Za-z]:[\\/]', url):
                checked += 1
                path = Path(url).resolve()
                if not path.is_relative_to(ROOT) or not path.exists():
                    broken.append({'page': str(page), 'url': url})
                continue
            target = urlsplit(url)
            if target.scheme in ('http', 'https', 'mailto', 'data'):
                continue
            checked += 1
            if target.scheme:
                broken.append({'page': str(page), 'url': url})
                continue
            path = Path(unquote(target.path)) if target.path else page
            if not path.is_absolute():
                path = page.parent / path
            path = path.resolve()
            if not path.is_relative_to(ROOT) or not path.exists() or (target.fragment and path in documents and target.fragment not in documents[path].ids):
                broken.append({'page': str(page), 'url': url})
    data = read_json(OUT / 'score_records.json')
    expected = [s['id'] for s in read_json(PLAN)['scenes']]
    if [e['id'] for e in data['gameplay_scenes']] != expected or any(len(e['scores']) != 7 for e in data['gameplay_scenes']):
        raise ValueError('Invalid mainline order or scores')
    integrity = data.get('history_evidence', {})
    passed = overall_passed(data['gameplay_scenes'], integrity)
    if data['overall_passed'] != passed:
        raise ValueError('Mainline acceptance inconsistent')
    report = dict(generated_at=datetime.now().astimezone().isoformat(timespec='seconds'), html_files=len(documents), markdown_files=len(list(OUT.rglob('*.md'))), local_links_checked=checked, broken_links=broken, mainline_segments=len(expected), history_evidence_complete=integrity.get('complete', False), history_evidence_counts=integrity.get('counts', {}), overall_passed=passed)
    atomic_write(OUT / 'export-verification.json', json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    if broken:
        raise ValueError(f'{len(broken)} broken local links; see export-verification.json')
    return report


def render():
    provenance.assert_runtime_root(ROOT)
    OUT.mkdir(parents=True, exist_ok=True)
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, stdin=subprocess.DEVNULL, text=True).strip()
    progress, reviews = load_progress(), load_reviews(ROOT)
    audit = audit_progress(progress)
    audit_document = dict(generated_at=datetime.now().astimezone().isoformat(timespec='seconds'),
                          complete=audit['complete'], counts=audit['counts'], issues=audit['issues'])
    atomic_write(OUT / 'evidence-audit.json', json.dumps(audit_document, ensure_ascii=False, indent=2) + '\n')
    entries = build_segments(reviews, load_changes(), progress, revision, audit)
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
        body = evidence_banner(audit, page) + ''.join(segment_card(e, i, page, audit) for i, e in enumerate(entries, 1)) + progress_section(progress, page, audit)
        atomic_write(page, wrap('第一章 · 主线评分与修正', body, page, revision, nav))
    archive_page(reviews, revision)
    for name in ('评分总览.md', '游戏场景评分.md'):
        atomic_write(OUT / name, markdown(entries, revision, progress, audit))
    integrity = dict(complete=audit['complete'], counts=audit['counts'], audit='evidence-audit.json')
    data = dict(schema_version=2, generated_at=datetime.now().astimezone().isoformat(timespec='seconds'), revision=revision, dimensions=DIMENSIONS, history_evidence=integrity, overall_passed=overall_passed(entries, integrity), gameplay_scenes=entries)
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
