"""Publish chapter-ordered player feedback, repairs and review history."""
from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
from html import escape
from html.parser import HTMLParser
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from urllib.parse import quote, unquote, urlsplit
import yaml
from mainline_reviews import load_reviews, capture_time
import visual_semantic_reviews
import mainline_recordings
import test_results

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'mcp'))
import capture_provenance as provenance
OUT = ROOT / 'artifacts/review'
SCORE_CATEGORIES = ['fluidity', 'text_density', 'action_sfx_integrity', 'audio_loudness', 'blind_narrative_match', 'aesthetic_similarity', 'narrative_flow']
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
    return bool(entries) and bool(audit.get('complete')) and all(
        e['status'] == '合格' and ('test' not in e or bool((e.get('test') or {}).get('independent_review')))
        for e in entries)


def evidence_banner(audit, page):
    counts = audit['counts']
    status = '完整' if audit['complete'] else '不完整 · 不得视为验收通过'
    detail = f"已核验 {counts['valid']} 项；缺失 {counts['missing']} 项，内容变化 {counts['changed']} 项，未核验 {counts['unverified']} 项。"
    return '<aside class="evidence-banner"><b>历史证据：' + status + '</b><p>' + escape(detail) + ' 缺失或变化项仅以文字标记，不提供失效链接。</p>' + link(OUT / 'evidence-audit.json', '查看证据审计清单', page) + '</aside>'


def markdown_links(text):
    return [value.strip().strip('<>') for value in re.findall(r'!?\[[^\]]*\]\(([^)]+)\)', text)]


def atomic_write(path, text):
    temporary = path.with_name(path.name + f'.{os.getpid()}.tmp')
    try:
        temporary.write_text(text, encoding='utf-8')
        for attempt in range(20):
            try:
                temporary.replace(path)
                break
            except PermissionError:
                if attempt == 19:
                    raise
                time.sleep(0.025)
    finally:
        if temporary.exists():
            temporary.unlink()


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


# Matching is limited to explicit check descriptions; each displayed excerpt keeps
# its original provenance and is never interpreted as a seven-point score.
DIMENSION_CHECK_TERMS = [
    ('fps', 'frame time', 'frame pacing', '帧率', '帧时间', '卡顿', '性能', '稳态超线'),
    ('text density', 'word count', 'character count', 'localization', '字幕', '字数', '英文', '本地化'),
    ('animation', 'skeletal', 'ik ', 'decal', 'occlusion', 'clipping', 'sfx', '动作', '动画', '遮挡', '穿模', '音效', '贴花'),
    ('lufs', 'dbtp', 'loudness', '响度', '真峰值'),
    ('blind narrative', 'blind read', 'semantic', '盲读', '叙事理解', '剧情替代'),
    ('ssim', 'lpips', 'aesthetic', 'reference image', '参考图', '相似度', '视觉对照'),
    ('narrative flow', 'pacing', 'walkthrough', '剧情流畅', '剧情节奏', '主线流程', '主线遍历'),
]
DIMENSION_MISSING = [
    'No audited frame-rate or frame-time check found for this segment.',
    'No audited visible-text density or English-language check found for this segment.',
    'No audited action, decal, occlusion, or sound check found for this segment.',
    'No audited LUFS or dBTP measurement found for this segment.',
    'No audited blind-reading or narrative comprehension check found for this segment.',
    'No audited reference-image similarity comparison found for this segment.',
    'No audited narrative pacing or walkthrough check found for this segment.',
]


def structured_development_metrics(event, evidence):
    """Read segment-specific measurements only from an unchanged audited file."""
    if Path(evidence['path']).name != 'segment-metrics.json' or evidence.get('status') != 'valid':
        return {}
    digest = evidence.get('expected_sha256')
    if not isinstance(digest, str) or not re.fullmatch(r'[0-9a-f]{64}', digest):
        return {}
    try:
        data = project_file(evidence['path']).read_bytes()
        if hashlib.sha256(data).hexdigest() != digest:
            return {}
        document = json.loads(data.decode('utf-8-sig'))
        if not isinstance(document, dict) or document.get('schema_version') != 1:
            return {}
        segments = document.get('segments')
        segment = segments.get(event.get('segment_id')) if isinstance(segments, dict) else None
        if not isinstance(segment, dict):
            return {}
    except (OSError, ValueError, UnicodeError):
        return {}

    def fields(source, specifications):
        if not isinstance(source, dict):
            return []
        return [label + ' ' + format(value, '.6g') + unit
                for key, label, unit in specifications
                if isinstance((value := source.get(key)), (int, float))
                and not isinstance(value, bool) and math.isfinite(value)]

    steady = segment.get('steady')
    samples = steady.get('frame_samples') if isinstance(steady, dict) else None
    frame = fields(steady, [
        ('frame_samples', 'samples', ''), ('avg_fps', 'Avg FPS', ''),
        ('low_5_fps', '5% Low FPS', ''), ('low_1_fps', '1% Low FPS', ''),
        ('frame_p95_ms', 'P95', ' ms'), ('frame_p99_ms', 'P99', ' ms'),
        ('max_frame_ms', 'max', ' ms'), ('spikes_over_33_3_ms', 'spikes >33.3 ms', ''),
    ]) if isinstance(samples, (int, float)) and not isinstance(samples, bool) and math.isfinite(samples) and samples > 0 else []
    audio = segment.get('audio')
    loudness = fields(audio, [
        ('integrated_lufs', 'Integrated', ' LUFS'),
        ('short_term_lufs', 'Short-term', ' LUFS'),
        ('true_peak_dbtp', 'True peak', ' dBTP'),
    ]) if isinstance(audio, dict) and audio.get('status') == 'complete' and audio.get('signal_present') is True else []
    result = {}
    if frame:
        result[0] = 'Steady-state frame pacing: ' + '; '.join(frame)
    if loudness:
        result[3] = 'Measured loudness: ' + '; '.join(loudness)
    return result


def development_dimensions(events, audit, semantic=None):
    """Collect segment-local, audited check excerpts without inferring scores."""
    dimensions = [[] for _ in DIMENSIONS]
    for event in events:
        if event.get('kind') != 'check':
            continue
        valid = [item['path'] for item in audit['events'].get(event['event_id'], [])
                 if item['status'] == 'valid']
        if not valid:
            continue
        text = str(event.get('summary', '')) + ' · ' + str(event.get('result', ''))
        for evidence in audit['events'].get(event['event_id'], []):
            for index, measurement in structured_development_metrics(event, evidence).items():
                dimensions[index].append(dict(text=measurement, revision=str(event.get('revision', '')),
                                              event_id=event['event_id'], paths=[evidence['path']], structured=True,
                                              evidence_sha256=evidence.get('expected_sha256')))
        for i, terms in enumerate(DIMENSION_CHECK_TERMS):
            if any(term in text.casefold() for term in terms):
                dimensions[i].append(dict(text=text, revision=str(event.get('revision', '')),
                                          event_id=event['event_id'], paths=valid))
    # Several ledger events may cite the same measured file. Merge only exact
    # duplicates; separate captures and distinct findings remain independently visible.
    unique_dimensions = []
    for items in dimensions:
        distinct = {}
        for item in items:
            key = (('measurement', item.get('evidence_sha256'), item['text']) if item.get('structured')
                   else ('finding', tuple(item['paths']), item['text']))
            distinct[key] = item
        unique_dimensions.append(sorted(distinct.values(), key=lambda item: item.get('structured', False))[-2:])
    dimensions = unique_dimensions
    if semantic:
        dimensions[4].append(dict(
            text='图片盲读：动作一致度 ' + str(semantic['action_score']) + '/10；意图一致度 '
                 + str(semantic['intent_score']) + '/10；模式 ' + str(semantic['modality']),
            revision=str(semantic.get('revision', '')), event_id=str(semantic.get('id', '')),
            paths=[semantic['record_path']]))
    return dimensions


def development_missing_reasons(events, audit, dimensions):
    """Explain absent or unauditable matching checks without treating them as scores."""
    reasons = [[] for _ in DIMENSIONS]
    labels = {'missing': 'file missing', 'changed': 'hash changed',
              'unverified': 'hash missing or file changed during audit'}
    for event in events:
        if event.get('kind') != 'check':
            continue
        text = (str(event.get('summary', '')) + ' · ' + str(event.get('result', ''))).casefold()
        evidence = audit['events'].get(event['event_id'], [])
        for i, terms in enumerate(DIMENSION_CHECK_TERMS):
            if not any(term in text for term in terms):
                continue
            if not evidence:
                reasons[i].append('Check ' + event['event_id'] + ': no evidence attached')
            for item in evidence:
                if item['status'] in labels:
                    reasons[i].append('Check ' + event['event_id'] + ': ' + item['path']
                                      + ' (' + labels[item['status']] + ')')
    for i, items in enumerate(dimensions):
        if not items and not reasons[i]:
            reasons[i].append(DIMENSION_MISSING[i])
    return reasons


def development_dimension_html(items, index, page, missing=None):
    missing = missing if missing is not None else ([] if items else [DIMENSION_MISSING[index]])
    rows = []
    for item in items:
        sources = ' '.join(link(project_file(path), Path(path).name, page) for path in item['paths'])
        rows.append('<li>' + escape(item['text']) + ' <small>' + escape(item['revision']) + ' · '
                    + escape(item['event_id']) + '</small> ' + sources + '</li>')
    gaps = ''.join('<li>' + escape(reason) + '</li>' for reason in missing)
    if not rows and not gaps:
        return ''
    return ('<details class="development-dimension"><summary>查看测试依据</summary>'
            + ('<ul>' + ''.join(rows) + '</ul>' if rows else '')
            + ('<p>待补证据：</p><ul>' + gaps + '</ul>' if gaps else '') + '</details>')


def development_score_events(events):
    latest = {}
    for event in events:
        value = event.get('development_score')
        if (isinstance(value, dict) and value.get('category') in SCORE_CATEGORIES
                and value.get('acceptance_eligible') is False
                and isinstance(value.get('score'), (int, float)) and not isinstance(value['score'], bool)
                and math.isfinite(value['score']) and 0 <= value['score'] <= 10):
            latest[value['category']] = event
    return latest


def dimension_scores(record, previous=None, development=None, page=None, missing=None, development_scores=None):
    cards = []
    for i, (name, score, reason) in enumerate(zip(DIMENSIONS, record.get('scores', [None] * 7), record.get('score_reasons', [None] * 7))):
        development_score = (development_scores or {}).get(SCORE_CATEGORIES[i])
        primary_score = score if score is not None else (development_score['development_score']['score'] if development_score else None)
        value = '待评' if primary_score is None else f'{primary_score:g}<small>/10</small>'
        primary_label = '正式验收分数' if score is not None else ('开发测试分数' if development_score else '等待评分')
        delta = ''
        if previous and score is not None and previous['scores'][i] is not None:
            delta = f'<small>较上轮 {score - previous["scores"][i]:+g}</small>'
        cls = 'pending' if primary_score is None else 'pass' if primary_score >= 8 else 'fail'
        detail = development_dimension_html(development[i], i, page, missing[i] if missing is not None else None) if development is not None else ''
        development_text = 'No development score recorded'
        if development_score:
            data = development_score['development_score']
            development_text = (f"{data['score']:g}/10 · {data.get('rationale') or 'No rationale supplied'} · "
                                f"{development_score['at']} · HEAD {development_score['revision']} · event {development_score['event_id']} · "
                                f"server PID {development_score.get('server_identity', {}).get('server_pid', 'unknown')} · "
                                f"evidence {', '.join(development_score.get('evidence', [])) or 'none supplied'}")
        development_html = (f'<details class="development-score" data-score-category="{SCORE_CATEGORIES[i]}">'
                            '<summary>评分来源 · 非正式验收</summary><p class="development-score-value">'
                            + escape(development_text) + '</p></details>') if development_scores is not None else ''
        formal_status = ('正式验收：待评' if score is None else '正式验收：' + str(reason or '已记录'))
        formal_flag = 'true' if score is not None else 'false'
        cards.append(f'<div class="dimension {cls}" data-formal-scored="{formal_flag}"><span>{name}</span><b class="primary-score">{value}</b><small class="primary-score-label">{primary_label}</small>{delta}<p class="formal-score-status">{escape(formal_status)}</p>{development_html}{detail}</div>')
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
    body = '<details class="feedback"><summary>本段反馈与修正</summary>'
    if not changes and not events:
        return body + '<p class="muted">等待本段主线游玩反馈。</p></details>'
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
    return body + '</ol></details>'


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
                origin = development_image_origin(path)
                caption = event['summary'] + ' · ' + path.stem
                if origin == 'historical-other-host-unverified':
                    caption += ' · Cross-host historical image: original PID cannot be verified; development evidence only'
                development_images.append({'path': evidence['path'], 'caption': caption, 'archive_origin': origin})
                seen_images.add(path)
        semantic_history = [r for r in semantic_reviews if r['segment_id'] == scene['id']]
        semantic = semantic_history[-1] if semantic_history else None
        diagnostics = development_dimensions(events, audit, semantic)
        missing = development_missing_reasons(events, audit, diagnostics)
        entries.append(dict(scene, current=current, history=history, changes=repairs, events=events,
                            recordings=recordings.get(scene['id'],[]),
                            semantic=semantic, semantic_history=semantic_history,
                            modification_count=len(repairs) + sum(e['kind'] == 'change' for e in events),
                            development_images=development_images,
                            development_dimensions=diagnostics, development_missing=missing,
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
    body += '<div class="acceptance-dimensions"><h3>七项评分与正式验收 · ' + entry['status'] + '</h3>'
    body += '<p class="meta">卡片优先显示正式验收分数；正式验收待评时，醒目显示已有开发测试分数并单独标注。</p>' + dimension_scores(current, development=entry['development_dimensions'], page=page, missing=entry.get('development_missing'), development_scores=development_score_events(entry['events'])) + '</div>'
    body += score_editor(current)
    body += semantic_score_summary(entry.get('semantic'))
    if entry.get('recordings'):
        body += recording_details(entry['recordings'][-1],page)
    if entry.get('semantic'):
        if entry.get('recordings') and entry['semantic']['modality']!='original_subtitled_stills':
            body += '<p class="meta">下方保留上一轮抽帧评审，评分对应其原始素材；本轮完整录制评审随后追加。</p>'
        body += '<details><summary>图片盲读详情</summary>' + semantic_details(entry['semantic'],page) + '</details>'
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
    return '<section id="live-progress" class="live-progress"><details><summary>实时进展与完整记录</summary><ol id="progress-events">' + ''.join(rows) + '</ol><p id="progress-empty"' + (' hidden' if rows else '') + '>等待首条记录。</p></details></section><script>window.MAINLINE_PROGRESS=' + data + ';</script>'


def scoring_coverage(entries):
    """Compact chapter matrix; historical scores stay attached to their revision."""
    rows = []
    counts = {'formal': 0, 'development': 0, 'historical': 0, 'pending': 0}
    for entry in entries:
        events = development_score_events(entry.get('events', []))
        history = entry.get('history', [])
        superseded = {r['supersedes'] for r in history if r.get('supersedes')}
        cells = []
        for i, category in enumerate(SCORE_CATEGORIES):
            score = entry.get('scores', [None] * 7)[i]
            old = next((r for r in reversed(history) if r.get('id') not in superseded
                        and len(r.get('scores', [])) > i and r['scores'][i] is not None), None)
            source = 'formal' if score is not None else ('development' if category in events else ('historical' if old else 'pending'))
            counts[source] += 1
            title = ''
            if source == 'development':
                score = events[category]['development_score']['score']
            elif source == 'historical':
                score = old['scores'][i]
                title = f' title="历史版本 {escape(str(old.get("revision", ""))[:8], quote=True)}；当前版本待评"'
            text = '待评' if score is None else f'{score:g} · ' + {'formal': '正式', 'development': '开发', 'historical': '历史'}[source]
            cells.append(f'<td data-coverage-category="{category}" data-formal-scored="{str(source == "formal").lower()}" data-score-source="{source}"{title}>{escape(text)}</td>')
        rows.append(f'<tr data-coverage-segment="{escape(entry["id"], quote=True)}"><th><a href="#trajectory-{escape(entry["id"], quote=True)}">{escape(entry["label"])}</a></th>' + ''.join(cells) + '</tr>')
    header = ''.join('<th>' + escape(name) + '</th>' for name in DIMENSIONS)
    summary = f"正式 {counts['formal']} 项 · 开发 {counts['development']} 项 · 仅历史 {counts['historical']} 项 · 待评 {counts['pending']} 项"
    return (f'<section class="score-coverage"><h2>第一章评分统计</h2><p data-coverage-summary>{summary}</p>'
            '<div class="coverage-scroll"><table><thead><tr><th>剧情片段</th>' + header + '</tr></thead><tbody>' + ''.join(rows) + '</tbody></table></div>'
            '<p class="meta">历史分数来自旧版本，当前版本仍待评；图片盲读分项单独保留。</p></section>')


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
        lines += ['', '开发期证据（与正式验收分开）：', '']
        for dimension_index, items in enumerate(entry['development_dimensions']):
            lines.append('- **' + DIMENSIONS[dimension_index] + '**：' + (
                '；'.join(str(item['text']).replace('\n', ' ') + '（版本 ' + item['revision']
                         + '，事件 ' + item['event_id'] + '；' + '、'.join(
                             '[' + Path(path).name.replace(']', '') + '](<' + markdown_href(project_file(path), page) + '>)'
                             for path in item['paths']) + '）' for item in items)
                if items else DIMENSION_MISSING[dimension_index]))
            for reason in entry.get('development_missing', [[] for _ in DIMENSIONS])[dimension_index]:
                lines.append('  - Missing evidence: ' + reason.replace('|', '／').replace('\n', ' '))

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
    results = test_results.collect(reviews, progress['events'])
    latest = test_results.latest_by_segment(results)
    current_events = {r['event_id'] for r in latest.values() if r.get('event_id')}
    audit = audit_progress({'events': [e for e in progress['events'] if e['event_id'] in current_events]})
    for result in latest.values():
        if not result.get('event_id'):
            continue
        evidence = audit['events'][result['event_id']]
        result['evidence'] = [e['path'] for e in evidence if e['status'] == 'valid']
        result['evidence_issues'] = [e['status'] + ': ' + e['path'] for e in evidence if e['status'] != 'valid']
        if not evidence:
            result['evidence_issues'] = ['This test did not attach measurement evidence.']
            audit['complete'] = False
        if result['evidence_issues'] and result['status'] == '合格':
            result['status'] = '待补测'
        for value in result['evidence']:
            path = project_file(value)
            if path.suffix.lower() in ('.png', '.jpg', '.jpeg'):
                try:
                    provenance.verify_image(path, ROOT, allow_fixture=True)
                except ValueError:
                    continue
                result['images'].append({'path': value, 'caption': path.stem})
    scenes = read_json(PLAN)['scenes']
    survey = test_results.latest_scene_survey(ROOT)
    survey_payload = test_results.scene_survey_payload(ROOT, survey)
    survey_json = json.dumps(survey_payload, ensure_ascii=False, allow_nan=False).replace('<', '\\u003c').replace('\u2028', '\\u2028').replace('\u2029', '\\u2029')
    atomic_write(OUT / 'scene-survey.js', 'window.SCENE_SURVEY=' + survey_json + ';\n')
    for name in ('review.css', 'run-report.js', 'scene-live.js'):
        atomic_write(OUT / name, (Path(__file__).parent / name).read_text(encoding='utf-8'))
    obsolete = OUT / 'gameplay.html'
    if obsolete.is_file(): obsolete.unlink()
    for filename in ('index.html',):
        page = OUT / filename
        body = test_results.scene_survey_table(survey, page, link)
        body += test_results.matrix(scenes, latest)
        body += ''.join(test_results.card(scene, latest.get(scene['id']), page, link, project_file, trajectory) for scene in scenes)
        document = wrap('第一章 · 测试评分', body, page, revision)
        document = document.replace('<body ', '<body data-report-client-version="2" ', 1)
        document = document.replace(link(OUT / 'archive.html', '历史与辅助资料', page), '')
        document = document.replace('review.js', 'run-report.js')
        atomic_write(page, document)
    for name in ('评分总览.md', 'scoring_overview.md'):
        atomic_write(OUT / name, test_results.markdown(scenes, latest, revision))
    entries = [dict(scene, scores=latest.get(scene['id'], {}).get('scores', [None] * 7),
                    status=latest.get(scene['id'], {}).get('status', '待补测'),
                    test=latest.get(scene['id'])) for scene in scenes]
    # Each result is evaluated against its own evidence and revision.
    integrity = dict(complete=audit['complete'], counts=audit['counts'])
    data = dict(schema_version=3, generated_at=datetime.now().astimezone().isoformat(timespec='seconds'),
                revision=revision, dimensions=DIMENSIONS, history_evidence=integrity,
                overall_passed=overall_passed(entries, integrity), gameplay_scenes=entries)
    atomic_write(OUT / 'score_records.json', json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    live = {'events': [e for e in progress['events'] if e.get('test_result')]}
    atomic_write(OUT / 'live-progress.js', 'window.MAINLINE_PROGRESS=' + json.dumps(live, ensure_ascii=False).replace('<', '\\u003c') + ';\n' + test_results.SCENE_LIVE_BOOTSTRAP)
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
