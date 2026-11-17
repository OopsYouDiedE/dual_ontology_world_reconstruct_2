"""Project test results: seven dimensions from one immutable test, never blended."""
from datetime import datetime
from html import escape
import math
from mainline_reviews import capture_time

CATEGORIES = ('fluidity', 'text_density', 'action_sfx_integrity', 'audio_loudness',
              'blind_narrative_match', 'aesthetic_similarity', 'narrative_flow')
LABELS = ('游玩流畅度', '界面字数', '动作与音效', '音频响度', '视听剧情替代', '参考图相似度', '剧情流畅性')


def normalize(test_id, segment, revision, at, scores, reasons, **extra):
    values = [scores.get(k) for k in CATEGORIES] if isinstance(scores, dict) else list(scores)
    notes = [reasons.get(k, '') for k in CATEGORIES] if isinstance(reasons, dict) else list(reasons)
    if len(values) != 7 or len(notes) != 7:
        raise ValueError('A test result must contain exactly seven dimensions')
    for value in values:
        if value is not None and (isinstance(value, bool) or not isinstance(value, (int, float))
                                  or not math.isfinite(value) or not 0 <= value <= 10):
            raise ValueError('Invalid test score')
    notes = [str(note).strip() or ('This test did not collect this dimension.' if value is None
                                  else 'Imported from the original test record.')
             for value, note in zip(values, notes)]
    status = ('不合格' if any(v is not None and v < 8 for v in values)
              else '待补测' if any(v is None for v in values) else '合格')
    return dict(id=test_id, segment_id=segment, revision=revision, at=at,
                scores=values, reasons=notes, status=status, **extra)


def collect(reviews, events):
    results = []
    superseded = {r['supersedes'] for r in reviews if r.get('supersedes')}
    for r in reviews:
        result = normalize(r['id'], r['segment_id'], r['revision'], capture_time(r).isoformat(),
                           r['scores'], r['score_reasons'], images=r.get('images', []),
                           evidence=[r['report']], superseded=r['id'] in superseded,
                           independent_review=not r.get('source_isolated') and r.get('acceptance_eligible') is not False)
        # Keep an actual observed blockage even when seven numeric scores pass.
        if r.get('status') == 'blocked':
            result['status'] = '不合格'
        elif r.get('status') == 'incomplete' and result['status'] == '合格':
            result['status'] = '待补测'
        results.append(result)
    for event in events:
        batch = event.get('test_result')
        if batch:
            results.append(normalize(batch['test_id'], event['segment_id'], event['revision'],
                                     event['at'], batch['scores'], batch['reasons'],
                                     images=[], evidence=event.get('evidence', []), event_id=event['event_id'], independent_review=False))
        elif event.get('development_score'):
            old = event['development_score']
            results.append(normalize(event['event_id'], event['segment_id'], event['revision'],
                                     event['at'], {old['category']: old['score']},
                                     {old['category']: old.get('rationale', '')},
                                     images=[], evidence=event.get('evidence', []), event_id=event['event_id'], independent_review=False))
    return sorted(results, key=lambda r: (datetime.fromisoformat(r['at']).timestamp(), r['id']))


def latest_by_segment(results):
    latest = {}
    for result in results:
        if not result.get('superseded'):
            latest[result['segment_id']] = result
    return latest


def score_text(value):
    return '未测' if value is None else f'{value:g}/10'


def matrix(scenes, latest):
    rows = []
    for scene in scenes:
        result = latest.get(scene['id'])
        values = result['scores'] if result else [None] * 7
        cells = ''.join(f'<td data-batch-score="{category}">{score_text(v)}</td>'
                        for category, v in zip(CATEGORIES, values))
        label = f'<a href="#trajectory-{escape(scene["id"], quote=True)}">{escape(scene["label"])}</a>'
        rows.append(f'<tr data-test-segment="{escape(scene["id"], quote=True)}"><th>{label}</th>'
                    f'<td data-test-id>{escape(result["id"]) if result else "尚未测试"}</td>' + cells + '</tr>')
    return ('<section class="score-coverage"><h2>最新测试 · 全部七项评分</h2>'
            '<p>每行对应同一次测试。点击片段查看评分依据、版本和实测画面。</p>'
            '<div class="coverage-scroll"><table><thead><tr><th>片段</th><th>测试 ID</th>'
            + ''.join('<th>' + name + '</th>' for name in LABELS)
            + '</tr></thead><tbody>' + ''.join(rows) + '</tbody></table></div></section>')


def card(scene, result, page, link, project_file, trajectory):
    sid = escape(scene['id'], quote=True)
    body = f'<article class="segment test-result" id="trajectory-{sid}" data-test-card="{sid}"'
    body += f' data-test-at="{escape(result["at"], quote=True) if result else ""}" data-test-id="{escape(result["id"], quote=True) if result else ""}"><h2>{escape(scene["label"])}</h2>'
    if not result:
        return body + '<p>尚未测试。</p><div data-result-body></div></article>'
    body += '<div data-result-body><p class="meta">测试 <span data-result-id>' + escape(result['id']) + '</span> · <span data-result-at>' + escape(result['at'])
    body += '</span> · 版本 <span data-result-revision>' + escape(result['revision'][:12]) + '</span></p>'
    body += '<p data-result-status>' + result['status'] + '</p><div class="dimensions">'
    for category, name, value, reason in zip(CATEGORIES, LABELS, result['scores'], result['reasons']):
        cls = 'pending' if value is None else 'pass' if value >= 8 else 'fail'
        body += (f'<div class="dimension {cls}" data-result-category="{category}"><span>{name}</span>'
                 f'<b>{score_text(value)}</b><p>{escape(reason)}</p></div>')
    body += '</div>'
    if result.get('images'):
        body += trajectory(result['images'], page)
    links = []
    for value in result.get('evidence', []):
        try:
            path = project_file(value)
        except ValueError:
            continue
        links.append(link(path, path.name, page))
    if links:
        body += '<details><summary>测试证据</summary><p class="evidence-links">' + ' '.join(links) + '</p></details>'
    if result.get('evidence_issues'):
        body += '<p class="meta">' + escape('；'.join(result['evidence_issues'])) + '</p>'
    return body + '</div></article>'


def markdown(scenes, latest, revision):
    lines = ['# 测试评分总览', '', '报告版本：' + revision, '',
             '| 片段 | 测试 ID | ' + ' | '.join(LABELS) + ' |',
             '|---|---|' + '---|' * 7]
    for scene in scenes:
        r = latest.get(scene['id'])
        values = r['scores'] if r else [None] * 7
        lines.append('| ' + scene['label'] + ' | ' + (r['id'] if r else '尚未测试') + ' | '
                     + ' | '.join(score_text(v) for v in values) + ' |')
    for scene in scenes:
        r = latest.get(scene['id'])
        if not r:
            continue
        lines += ['', '## ' + scene['label'], '', f"{r['id']} · {r['at']} · {r['revision']} · {r['status']}", '']
        lines += [f'- {name}：{score_text(v)} — {reason}' for name, v, reason in zip(LABELS, r['scores'], r['reasons'])]
    return '\n'.join(lines) + '\n'
