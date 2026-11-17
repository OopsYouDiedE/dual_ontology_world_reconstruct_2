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


def _json_file(path, fallback=None):
    """Read a possibly incomplete result without interrupting the main report."""
    import json
    try:
        with path.open(encoding='utf-8-sig') as stream:
            return json.load(stream)
    except (OSError, ValueError, UnicodeError):
        return fallback


def _local_file(root, value):
    from pathlib import Path
    if not value:
        return None
    try:
        path = Path(value)
        if not path.is_absolute():
            path = root / path
        path = path.resolve()
        return path if path.is_relative_to(root.resolve()) and path.is_file() else None
    except (OSError, ValueError, TypeError):
        return None


def latest_scene_survey(root):
    """Return only the newest scene survey, including interrupted/queued jobs."""
    from pathlib import Path
    root = Path(root).resolve()
    runs = root / 'artifacts/evaluation/runs'
    if not runs.is_dir():
        return None
    # Run IDs contain sortable timestamps. Older unrelated runs are skipped.
    for directory in sorted((p for p in runs.iterdir() if p.is_dir()), key=lambda p: p.name, reverse=True):
        status_path = directory / 'status.json'
        status = _json_file(status_path, {})
        if not isinstance(status, dict) or status.get('profile') != 'scene_survey':
            continue
        rows = []
        scores_data = _json_file(directory / 'scene-scores.json', {})
        case_scores = {}
        if (isinstance(scores_data, dict) and status.get('run_id') and status.get('revision')
                and scores_data.get('run_id') == status.get('run_id')
                and scores_data.get('source_revision') == status.get('revision')
                and isinstance(scores_data.get('cases'), list)):
            for case in scores_data['cases']:
                if not isinstance(case, dict) or not isinstance(case.get('case_id'), str):
                    continue
                if case.get('source_revision', status.get('revision')) != status.get('revision'):
                    continue
                values, reasons = case.get('scores'), case.get('reasons')
                if not isinstance(values, dict) or not isinstance(reasons, dict):
                    continue
                if not all(key in values and key in reasons and isinstance(reasons[key], str) and reasons[key].strip()
                           and (values[key] is None or (isinstance(values[key], (int, float))
                                and not isinstance(values[key], bool) and math.isfinite(values[key]) and 0 <= values[key] <= 10))
                           for key in CATEGORIES):
                    continue
                # Duplicate case IDs make the source ambiguous: do not mix either.
                if case['case_id'] in case_scores:
                    case_scores[case['case_id']] = None
                else:
                    case_scores[case['case_id']] = {'scores': {key: values[key] for key in CATEGORIES},
                                                    'reasons': {key: reasons[key] for key in CATEGORIES}}
        planned = _json_file(root / 'assets/data/test_scenarios/mainline_survey.json', [])
        configs = {'survey-' + str(row.get('id')): row for row in planned
                   if isinstance(row, dict) and row.get('id')} if isinstance(planned, list) else {}
        for job, entry in status.get('jobs', {}).items():
            if not isinstance(entry, dict):
                continue
            job_dir = _local_file(root, directory / job / 'plan.json')
            plan = _json_file(job_dir, []) if job_dir else []
            config = plan[0] if isinstance(plan, list) and plan and isinstance(plan[0], dict) else configs.get(job, {})
            detail = entry.get('detail') if isinstance(entry.get('detail'), dict) else {}
            case_id = str(config.get('id') or detail.get('case_id') or entry.get('case_id') or job.removeprefix('survey-'))
            fixture = config.get('fixture') if isinstance(config.get('fixture'), dict) else {}
            result_path = _local_file(root, directory / job / 'survey.json')
            survey = _json_file(result_path, {}) if result_path else {}
            cases = survey.get('cases', []) if isinstance(survey, dict) else []
            result = next((case for case in cases if isinstance(case, dict) and str(case.get('id')) == case_id), {})
            if not result and len(cases) == 1 and isinstance(cases[0], dict):
                result = cases[0]
                case_id = str(result.get('id') or case_id)
            result_fixture = result.get('fixture') if isinstance(result.get('fixture'), dict) else {}
            progress_path = _local_file(root, directory / job / case_id / 'progress.json') or _local_file(root, directory / job / 'progress.json')
            progress = _json_file(progress_path, {}) if progress_path else {}
            if not isinstance(progress, dict):
                progress = {}
            final = result.get('final') if isinstance(result.get('final'), dict) else {}
            initial = result.get('initial') if isinstance(result.get('initial'), dict) else {}
            phase = progress.get('phase') or progress.get('stage') or detail.get('reached_phase') or detail.get('phase') or final.get('beat') or initial.get('beat') or '—'
            room = fixture.get('room') or result_fixture.get('room') or progress.get('room') or final.get('room') or initial.get('room') or detail.get('room') or '—'
            stalls = result.get('stalls') if isinstance(result.get('stalls'), list) else []
            issues = result.get('issues') if isinstance(result.get('issues'), list) else detail.get('issues', [])
            problems = [str(issue) for issue in issues if issue] if isinstance(issues, list) else []
            for stall in stalls:
                if isinstance(stall, dict):
                    description = ' / '.join(str(stall.get(k)) for k in ('phase', 'action', 'reason') if stall.get(k))
                    if description: problems.append(description)
            if progress.get('action') and entry.get('state') in ('failed', 'blocked', 'cancelled'):
                problems.append('最近操作: ' + str(progress['action']))
            if detail.get('error') or detail.get('reason'):
                problems.append(str(detail.get('error') or detail.get('reason')))
            if progress.get('reason'):
                problems.append(str(progress['reason']))
            images = []
            for image in result.get('images', []):
                value = image.get('path') if isinstance(image, dict) else image
                path = _local_file(root, value)
                if path:
                    images.append(path)
            for image in detail.get('images', []):
                path = _local_file(root, image)
                if path and path not in images:
                    images.append(path)
            evidence = _local_file(root, directory / job / case_id / 'report.json') or result_path
            scoring = case_scores.get(case_id) or {'scores': {key: None for key in CATEGORIES},
                                                     'reasons': {key: '该场景当前批次尚无评分。' for key in CATEGORIES}}
            rows.append(dict(id=case_id, room=str(room), phase=str(phase), state=str(entry.get('state', 'unknown')),
                             reason='；'.join(dict.fromkeys(problems)), images=images,
                             evidence=evidence, progress=progress_path, **scoring))
        return dict(id=str(status.get('run_id') or directory.name), revision=str(status.get('revision', '')),
                    state=str(status.get('state', 'unknown')), rows=rows, status_path=status_path)
    return None


def scene_survey_table(survey, page, link):
    if not survey:
        return ''
    labels = {'passed': '完成', 'failed': '失败', 'blocked': '受阻', 'cancelled': '已停止',
              'running': '进行中', 'starting': '启动中', 'planned': '等待中', 'unknown': '未知'}
    rows = []
    for row in survey['rows']:
        state = labels.get(row['state'], row['state'])
        reason = row['reason'] or ('检查执行结束' if row['state'] == 'passed' else '等待结果')
        evidence = []
        if row.get('evidence'):
            evidence.append(link(row['evidence'], '结果', page))
        if row.get('progress'):
            evidence.append(link(row['progress'], '最近步骤', page))
        if row.get('images'):
            evidence.append(link(row['images'][-1], '画面', page))
        dimensions = ''.join('<td class="survey-score" data-survey-score="' + escape(key, quote=True) + '"><strong>'
                             + escape(score_text(row['scores'][key])) + '</strong><small>' + escape(row['reasons'][key])
                             + '</small></td>' for key in CATEGORIES)
        rows.append('<tr data-survey-case="' + escape(row['id'], quote=True) + '"><th>' + escape(row['id']) + '</th><td>'
                    + escape(row['room']) + '</td><td>' + escape(row['phase']) + '</td><td>' + escape(state) + '</td><td>'
                    + escape(reason) + '</td>' + dimensions + '<td>' + (' '.join(evidence) if evidence else '—') + '</td></tr>')
    summary = '批次 ' + survey['id'] + ' · 版本 ' + survey['revision'][:12] + ' · ' + labels.get(survey['state'], survey['state'])
    return ('<section class="score-coverage scene-survey"><h2>场景逐项测试与卡点</h2><p>' + escape(summary) + ' · '
            + link(survey['status_path'], '批次状态', page) + '</p><div class="coverage-scroll"><table><thead><tr>'
            + '<th>场景</th><th>房间</th><th>最近阶段</th><th>状态</th><th>问题 / 卡点</th>' + ''.join('<th>' + escape(label) + '</th>' for label in LABELS) + '<th>证据</th></tr></thead><tbody>'
            + ''.join(rows) + '</tbody></table></div></section>')


def scene_survey_payload(root, survey):
    """Serialize only project-relative evidence for the file:// live view."""
    if not survey:
        return None
    root = root.resolve()
    relative = lambda path: path.resolve().relative_to(root).as_posix() if path else None
    return dict(id=survey['id'], revision=survey['revision'], state=survey['state'],
                status_path=relative(survey['status_path']),
                rows=[dict(row, evidence=relative(row.get('evidence')), progress=relative(row.get('progress')),
                           images=[relative(p) for p in row.get('images', [])]) for row in survey['rows']])


SCENE_LIVE_BOOTSTRAP = ("if(!window.__sceneSurveyLive){window.__sceneSurveyLive=true;"
                        "var s=document.createElement('script');s.src='scene-live.js?t='+Date.now();"
                        "s.onerror=function(){window.__sceneSurveyLive=false};document.body.append(s);}\n")
