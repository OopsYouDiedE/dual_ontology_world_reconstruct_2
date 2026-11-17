"""Prepare a seven-dimension result from one closed, continuous segment session.

The output is an argument object for the review MCP's ``add_scores`` tool; this
module does not publish it. Independent reviewers must supply their same-session
observations and judgments. A score is never borrowed from another run.

The assessment JSON belongs in the closed monitor directory. It has
schema_version, test_id, revision, session_id, host_pid, segment_id, and
assessment_plan_sha256 fields matching that session. Its ``case_outcomes`` maps
each planned case ID to {status, reason, start_s, end_s}; statuses are
completed, failed, stalled, or not_started; started-case times use the monitor elapsed clock.
``reviews`` maps subjective category IDs to {assessor, score, reason,
case_evidence}. Each case_evidence maps a case ID to project-local evidence
paths. Use live blind-observations.jsonl for narrative and pacing; for aesthetic
comparison supply that case's configured reference and a timed image listed in
the session's dynamic/frames.jsonl. Scores may be null with a specific reason.
Objective values are read from the same session's finalized metrics summary.
For a graceful close whose FFmpeg analysis timed out, --recovered-metrics
explicitly selects a provenance-checked postprocessed summary; the original
close receipt is retained, and the test remains incomplete.

Command example::

    python tools/testing/segment_settlement.py --plan PLAN --on-receipt ON \
        --close-receipt CLOSE --assessment SESSION/assessment.json
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys

import yaml

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'mcp'))
sys.path.insert(0, str(ROOT / 'mcp/game'))
import capture_provenance as provenance
from assessment_plan import CATEGORIES, validate as validate_plan
from mainline_metrics import audio_score, summarize

SUBJECTIVE = ('action_sfx_integrity', 'blind_narrative_match', 'aesthetic_similarity', 'narrative_flow')


def _read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def _hash(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def _local(root, value):
    path = provenance.project_path(value, root)
    if not path.is_file():
        raise ValueError('Evidence file does not exist: ' + str(value))
    return path


def _number(value):
    return not isinstance(value, bool) and isinstance(value, (int, float)) and math.isfinite(value)


def _receipt(path, kind):
    data = _read(path)
    if not isinstance(data, dict) or data.get('is_error') is not False or data.get('tool') != kind or not isinstance(data.get('data'), dict):
        raise ValueError('A successful ' + kind + ' client receipt is required')
    return data['data']


def _case_windows(value, plan, intervals):
    if not isinstance(value, dict) or set(value) != {case['id'] for case in plan['cases']}:
        raise ValueError('Case outcomes must cover exactly the planned scenes')
    previous, incomplete = 0.0, []
    for case in plan['cases']:
        name = case['id']
        item = value[name]
        if not isinstance(item, dict) or item.get('status') not in ('completed', 'failed', 'stalled', 'not_started'):
            raise ValueError('Each case needs a completed, failed, stalled, or not_started outcome')
        if not isinstance(item.get('reason'), str) or not item['reason'].strip():
            raise ValueError('Each case outcome needs a concrete reason')
        if item['status'] == 'not_started':
            if item.get('start_s') is not None or item.get('end_s') is not None:
                raise ValueError('An unstarted case cannot have a measured interval')
            incomplete.append(name + ' (not_started: ' + item['reason'].strip() + ')')
            continue
        start, end = item.get('start_s'), item.get('end_s')
        if (not _number(start) or not _number(end) or start < previous or end <= start
                or not any(a - 1 <= start and end <= b + 1 for a, b in intervals)):
            raise ValueError('Case intervals must be ordered and lie within the recorded session')
        if item['status'] != 'completed':
            incomplete.append(name + ' (' + item['status'] + ': ' + item['reason'].strip() + ')')
        previous = end
    return incomplete


def _blind_rows(path, plan, session_id, pid, windows, session_intervals):
    if not path.is_file():
        return []
    rows = []
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        if not line.strip():
            continue
        row = json.loads(line)
        case = row.get('case_id') if isinstance(row, dict) else None
        t = row.get('monitor_elapsed_s') if isinstance(row, dict) else None
        if (not isinstance(row, dict) or row.get('schema_version') != 1
                or row.get('test_id') != plan['test_id'] or row.get('revision') != plan['revision']
                or row.get('session_id') != session_id or row.get('host_pid') != pid
                or row.get('observer') != plan['blind_observer']['identity']
                or row.get('assessment_plan_sha256') != plan['plan_sha256']
                or row.get('segment_id') != plan['segment_id'] or case not in windows
                or row.get('case_index') != next((i for i, c in enumerate(plan['cases']) if c['id'] == case), None)
                or not _number(t) or not _number(windows[case].get('start_s'))
                or not _number(windows[case].get('end_s'))
                or not any(start <= t <= end for start, end in session_intervals)
                or row.get('kind') not in ('event', 'character')
                or not isinstance(row.get('text'), str) or not row['text'].strip()):
            raise ValueError('Blind observation does not belong to this session, case, or timeline')
        # Observers may file a retrospective note after the case transition.
        # Keep the original log, but only count notes inside the case window
        # as time-specific evidence for a case score.
        if windows[case]['start_s'] <= t <= windows[case]['end_s']:
            rows.append(row)
    return rows


def _dynamic_frames(root, directory, windows):
    manifest = directory / 'dynamic/frames.jsonl'
    if not manifest.is_file():
        return {}, None
    frames, summary = {}, None
    for line in manifest.read_text(encoding='utf-8-sig').splitlines():
        if not line.strip():
            continue
        row = json.loads(line)
        if not isinstance(row, dict):
            raise ValueError('Invalid dynamic capture manifest row')
        if row.get('type') == 'summary':
            summary = row
        if row.get('type') != 'frame' or row.get('error') != 0:
            continue
        frame = provenance.project_path(row.get('path', ''), root)
        t = row.get('elapsed_s')
        if (not frame.is_relative_to(directory / 'dynamic') or row.get('error') != 0
                or not isinstance(row.get('sha256'), str) or not _number(t)):
            raise ValueError('Dynamic capture path, image hash, or timestamp is invalid')
        cases = [case for case, interval in windows.items()
                 if _number(interval.get('start_s')) and _number(interval.get('end_s'))
                 and interval['start_s'] <= t <= interval['end_s']]
        if len(cases) == 1:
            frames[frame] = (cases[0], row['sha256'])
    if not isinstance(summary, dict):
        summary = {'frames':len(frames), 'skipped_samples':0, 'write_failures':1}
    return frames, summary


def prepare(plan_file, on_receipt, close_receipt, assessment_file, *, root=ROOT, revision=None, recovered_metrics=None):
    root = Path(root).resolve()
    plan_file, on_receipt, close_receipt = (_local(root, p) for p in (plan_file, on_receipt, close_receipt))
    revision = revision or subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    plan = validate_plan(plan_file, root, revision=revision)
    if plan.get('entry_mode') != 'segment' or not isinstance(plan.get('segment_id'), str):
        raise ValueError('A single-segment assessment plan is required')
    on, close = _receipt(on_receipt, 'on'), _receipt(close_receipt, 'close')
    session_id = on.get('session_id')
    pid = on.get('source_identity', {}).get('process_id')
    expected = provenance.project_identity(root)
    if not isinstance(session_id, str) or not session_id or isinstance(pid, bool) or not isinstance(pid, int) or pid <= 0:
        raise ValueError('Original session and host PID are required')
    provenance.validate_source(on.get('source_identity'), expected, pid=pid)
    provenance.validate_source(close.get('source_identity'), expected, pid=pid)
    if (on.get('assessment_test_id') != plan['test_id'] or on.get('scenario_ready') is not True
            or on.get('scene') != 'res://mcp/game/SegmentEntry.tscn'
            or on.get('assessment_case_index') != 0 or on.get('assessment_case_count') != len(plan['cases'])
            or close.get('session_id') != session_id
            or close.get('closed') is not True or close.get('graceful_exit') is not True):
        raise ValueError('On/close receipts do not identify one gracefully closed test')
    provenance.validate_source(on.get('server_identity'), expected)
    provenance.validate_source(close.get('server_identity'), expected)
    if (provenance.project_path(on.get('server_identity', {}).get('server_path', ''), root) != root / 'mcp/game/server.py'
            or on.get('server_identity', {}).get('server_path') != close.get('server_identity', {}).get('server_path')):
        raise ValueError('Session did not use the project input MCP server')
    server_pid = on.get('server_identity', {}).get('server_pid')
    if (isinstance(server_pid, bool) or not isinstance(server_pid, int) or server_pid <= 0
            or server_pid != close.get('server_identity', {}).get('server_pid')):
        raise ValueError('Session server PID is missing or changed between receipts')
    directory = provenance.project_path(on.get('metrics_directory', ''), root)
    if not directory.is_dir() or not directory.name.endswith('-' + str(pid)):
        raise ValueError('Session metrics directory and host PID do not match')
    recovery_issue = None
    recovery_evidence = []
    if recovered_metrics is None:
        if close.get('metrics_status') != 'complete':
            raise ValueError('On/close receipts do not identify one gracefully closed test with complete metrics')
        metrics_path = _local(root, close.get('metrics_summary_path', ''))
        if metrics_path != directory / 'segment-metrics.json':
            raise ValueError('Metrics summary belongs to a different session')
        metrics = _read(metrics_path)
    else:
        error = close.get('metrics_error')
        if (close.get('metrics_status') != 'error' or not isinstance(error, str)
                or 'ffmpeg' not in error.lower() or 'timed out' not in error.lower()):
            raise ValueError('Recovery requires the original graceful FFmpeg timeout receipt')
        metrics_path = _local(root, recovered_metrics)
        if metrics_path != directory / 'segment-metrics-recovered.json':
            raise ValueError('Recovered metrics belong to a different session')
        metrics = _read(metrics_path)
        recovery = metrics.get('recovery') if isinstance(metrics, dict) else None
        if (not isinstance(recovery, dict)
                or _local(root, recovery.get('original_close_receipt', '')) != close_receipt
                or recovery.get('original_close_receipt_sha256') != _hash(close_receipt)):
            raise ValueError('Recovery does not match the original close receipt')
        script = _local(root, 'tools/testing/mainline_metrics.py')
        if recovery.get('analysis_script_sha256') != _hash(script):
            raise ValueError('Recovery analysis script hash does not match')
        try:
            resolved = subprocess.check_output(['git', 'rev-parse', '--verify', revision + '^{commit}'],
                                               cwd=root, text=True, stderr=subprocess.DEVNULL).strip()
            ancestor = subprocess.run(['git', 'merge-base', '--is-ancestor', revision, 'HEAD'],
                                      cwd=root, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
        except (OSError, subprocess.CalledProcessError) as exc:
            raise ValueError('Recovery source revision is not a committed ancestor') from exc
        if resolved != revision or ancestor != 0:
            raise ValueError('Recovery source revision is not a committed ancestor')
        expected_names = {'mix.f32le', 'background-music.f32le', 'audio.json',
                          'background-music.json', 'concurrency-observation.json'}
        captured = recovery.get('source_sha256')
        if not isinstance(captured, dict) or set(captured) != expected_names:
            raise ValueError('Recovery must hash the same-session audio and concurrency sources')
        for name, recorded in captured.items():
            source = _local(root, directory / name)
            if _hash(source) != recorded:
                raise ValueError('Recovery source hash does not match: ' + name)
            recovery_evidence.append(source)
        recovery_evidence.append(script)
        recovery_issue = 'Original close reported audio postprocessing failure: ' + error
    timeline = _local(root, directory / 'timeline.yaml')
    timeline_data = yaml.safe_load(timeline.read_text(encoding='utf-8-sig'))
    if not isinstance(timeline_data, dict) or not isinstance(timeline_data.get('summary'), dict):
        raise ValueError('Finalized session timeline is required')
    meta = timeline_data.get('metadata', {})
    provenance.validate_source(meta.get('source_identity'), expected, pid=pid)
    provenance.validate_source(metrics.get('source_identity'), expected, pid=pid)
    if (metrics.get('finalized') is not True or metrics.get('measurement_context') != 'rendered_runtime'
            or metrics.get('test_id') != plan['test_id'] or metrics.get('assessment_revision') != plan['revision']
            or provenance.project_path(metrics.get('source_directory', ''), root) != directory
            or meta.get('test_id') != plan['test_id'] or meta.get('revision') != plan['revision']
            or meta.get('collection_mode') != 'simultaneous'
            or meta.get('entry') != 'scenario' or metrics.get('entry') != 'scenario'
            or provenance.project_path(meta.get('scenario_path', ''), root) != provenance.project_path(plan['cases'][0]['scenario_path'], root)
            or provenance.project_path(metrics.get('scenario_path', ''), root) != provenance.project_path(plan['cases'][0]['scenario_path'], root)
            or provenance.project_path(meta.get('assessment_plan', ''), root) != plan_file
            or meta.get('assessment_plan_sha256') != plan['plan_sha256']):
        raise ValueError('Metrics, timeline, assessment plan, or source revision do not match')
    hashes = metrics.get('source_sha256')
    if not isinstance(hashes, dict) or not {'timeline.yaml', 'frames.csv'} <= set(hashes):
        raise ValueError('Original timeline and frames need recorded hashes')
    for name, digest in hashes.items():
        if name not in ('timeline.yaml', 'frames.csv', 'visible-text-changes.jsonl', 'visible-text-reviews.jsonl'):
            raise ValueError('Unexpected metrics source hash')
        if _hash(_local(root, directory / name)) != digest:
            raise ValueError('Metrics source changed after settlement: ' + name)
    if recovery_issue:
        # Hashes establish which inputs were used. Recompute with the verified
        # analysis script so a hand-edited recovery result cannot become a score.
        try:
            verified = summarize(directory, scenario_path=provenance.project_path(plan['cases'][0]['scenario_path'], root))
        except (OSError, ValueError, TypeError, subprocess.SubprocessError) as exc:
            raise ValueError('Recovery reanalysis failed: ' + str(exc)) from exc
        for field in ('finalized', 'source_directory', 'source_identity', 'entry', 'measurement_context',
                      'scenario_path', 'test_id', 'assessment_revision', 'source_sha256', 'segments'):
            if json.dumps(verified.get(field), sort_keys=True, allow_nan=False) != json.dumps(metrics.get(field), sort_keys=True, allow_nan=False):
                raise ValueError('Recovery metrics do not match reanalysis: ' + field)
    assessment_path = _local(root, assessment_file)
    if assessment_path.parent != directory:
        raise ValueError('Assessment must be retained inside its own session directory')
    assessment = _read(assessment_path)
    if (not isinstance(assessment, dict) or assessment.get('schema_version') != 1
            or assessment.get('test_id') != plan['test_id'] or assessment.get('revision') != plan['revision']
            or assessment.get('session_id') != session_id or assessment.get('host_pid') != pid
            or assessment.get('segment_id') != plan['segment_id']
            or assessment.get('assessment_plan_sha256') != plan['plan_sha256']):
        raise ValueError('Assessment identity does not match this session')
    segment = metrics.get('segments', {}).get(plan['segment_id'])
    if not isinstance(segment, dict) or not isinstance(segment.get('measured_scores'), list) or len(segment['measured_scores']) != 7:
        raise ValueError('The requested segment has no complete measured-score record')
    intervals = segment.get('intervals_s')
    if not isinstance(intervals, list) or not intervals or any(not isinstance(v, list) or len(v) != 2 or not all(_number(n) for n in v) or v[0] < 0 or v[1] < v[0] for v in intervals):
        raise ValueError('Segment timeline intervals are unavailable or invalid')
    windows = assessment.get('case_outcomes')
    incomplete = _case_windows(windows, plan, intervals)
    notes_path = directory / 'blind-observations.jsonl'
    notes = _blind_rows(notes_path, plan, session_id, pid, windows, intervals)
    frames, frame_summary = _dynamic_frames(root, directory, windows)
    if frame_summary is None:
        incomplete.append('Dynamic scene capture did not finalize')
    elif frame_summary.get('frames', 0) <= 0 or frame_summary.get('skipped_samples', 0) or frame_summary.get('write_failures', 0):
        incomplete.append('Dynamic scene capture reported skipped samples or write failures')
    evidence = [plan_file, on_receipt, close_receipt, metrics_path, timeline, directory / 'frames.csv', assessment_path, *recovery_evidence]
    scores, reasons = {}, {}
    partial = '; '.join(incomplete)
    concurrency = metrics.get('concurrency_observation', {})
    concurrency_path = directory / 'concurrency-observation.json'
    concurrency_ok = (isinstance(concurrency, dict) and concurrency_path.is_file()
                      and _read(concurrency_path) == concurrency and concurrency.get('host_pid') == pid
                      and concurrency.get('sampler_stopped') is True and concurrency.get('sample_count', 0) > 0)
    peak = concurrency.get('peak_observed_godot_processes') if concurrency_ok else None
    concurrency_note = (f'Peak observed Godot processes: {peak}; sampling is periodic.' if not isinstance(peak, bool) and isinstance(peak, int) and peak >= 1
                        else 'Concurrent load observation unavailable.')
    for index, category in ((0, 'fluidity'), (1, 'text_density'), (3, 'audio_loudness')):
        score = segment['measured_scores'][index]
        if score is not None and (not _number(score) or not 0 <= score <= 10):
            raise ValueError('Invalid same-session measured score for ' + category)
        if category == 'fluidity':
            steady = segment.get('steady', {})
            samples, spikes = steady.get('frame_samples'), steady.get('spikes_over_33_3_ms')
            if (isinstance(samples, bool) or not isinstance(samples, int) or samples < 0
                    or isinstance(spikes, bool) or not isinstance(spikes, int) or not 0 <= spikes <= samples):
                raise ValueError('Invalid steady-frame statistics')
            expected_score = 6 if spikes else 8 if samples else None
            if score != expected_score:
                raise ValueError('Fluidity score conflicts with same-session frame statistics')
            reason = f"{samples} steady frames, {spikes} frames above 33.3 ms. {concurrency_note}"
            if score is None:
                reason += ' Fluidity score unavailable.'
            if score is not None and score >= 8 and not (not isinstance(peak, bool) and isinstance(peak, int) and peak >= 1):
                score = None
        elif category == 'text_density':
            reason = segment.get('text_score_reason') or 'Visible text measurement is unavailable.'
            text_result = segment.get('visible_text', {})
            if score is not None and (not isinstance(text_result, dict) or text_result.get('score') != score
                                      or 'visible-text-changes.jsonl' not in hashes
                                      or not (directory / 'visible-text-changes.jsonl').is_file()):
                raise ValueError('Text score lacks its same-session visible-text analysis')
            if (directory / 'visible-text-changes.jsonl').is_file(): evidence.append(directory / 'visible-text-changes.jsonl')
            if (directory / 'visible-text-reviews.jsonl').is_file(): evidence.append(directory / 'visible-text-reviews.jsonl')
        else:
            reason = segment.get('audio_score_reason') or segment.get('audio', {}).get('reason') or 'Audio measurement is unavailable.'
            audio_path, pcm_path = directory / 'audio.json', directory / 'mix.f32le'
            audio_log = directory / ('segment-' + plan['segment_id'] + '-mix-audio.log')
            if score is not None:
                if not all(path.is_file() for path in (audio_path, pcm_path, audio_log)):
                    raise ValueError('Audio score lacks its same-session PCM, analyzer output or log')
                audio_summary = _read(audio_path)
                recorded = timeline_data['summary']
                writer = recorded.get('audio_writer', {})
                samples = timeline_data.get('timeline', [])
                if (not isinstance(audio_summary, dict) or audio_summary.get('status') != 'complete'
                        or not isinstance(writer, dict) or writer.get('error') != 0
                        or writer.get('bytes_queued') != 0 or writer.get('bytes_written') != pcm_path.stat().st_size
                        or recorded.get('audio_discarded_frames') != 0 or not isinstance(samples, list)
                        or any(not isinstance(sample, dict) or sample.get('audio_discarded_frames', 0)
                               or sample.get('audio_writer', {}).get('error', 0) for sample in samples)):
                    raise ValueError('Audio capture was incomplete, changed, or lost frames')
                expected_audio, _ = audio_score(segment.get('audio', {}), segment.get('background_audio'))
                if score != expected_audio:
                    raise ValueError('Audio score conflicts with same-session loudness analysis')
                evidence.extend((pcm_path, audio_log))
            if audio_path.is_file(): evidence.append(audio_path)
        if incomplete and score is not None and score >= 8:
            score = None
            reason += ' Complete segment coverage is missing: ' + partial
        scores[category], reasons[category] = score, reason
    reviews = assessment.get('reviews', {})
    if not isinstance(reviews, dict) or set(reviews) - set(SUBJECTIVE):
        raise ValueError('Subjective reviews must use the four supported categories')
    references = {_local(root, case['reference']['path']) for case in plan['cases']}
    for category in SUBJECTIVE:
        review = reviews.get(category)
        if review is None:
            scores[category] = None
            reasons[category] = 'Same-session assessment was not supplied for ' + category + '.'
            continue
        if not isinstance(review, dict) or review.get('assessor') != plan['channels'][category]['assessor']:
            raise ValueError('Assessment is not attributed to the configured assessor for ' + category)
        score, reason = review.get('score'), review.get('reason')
        if score is not None and (not _number(score) or not 0 <= score <= 10):
            raise ValueError('Invalid score for ' + category)
        if not isinstance(reason, str) or not reason.strip():
            raise ValueError('A specific assessment reason is required for ' + category)
        by_case = review.get('case_evidence', {})
        if not isinstance(by_case, dict) or set(by_case) - set(windows):
            raise ValueError('Evidence references an unplanned case')
        supported = set()
        for case, paths in by_case.items():
            if not isinstance(paths, list):
                raise ValueError('Case evidence must be a list')
            for item in paths:
                path = _local(root, item)
                if not path.is_relative_to(directory) and not (category == 'aesthetic_similarity' and path in references):
                    raise ValueError('Evidence belongs to another session: ' + str(item))
                if category == 'aesthetic_similarity' and path in references:
                    reference = next(c['reference']['path'] for c in plan['cases'] if c['id'] == case)
                    if path != _local(root, reference):
                        raise ValueError('Aesthetic reference belongs to a different case')
                    receipt = next(c['reference']['provenance'] for c in plan['cases'] if c['id'] == case)
                    evidence.append(_local(root, receipt))
                if path == notes_path and any(row['case_id'] == case for row in notes):
                    supported.add(case)
                frame = frames.get(path)
                if frame and frame[0] == case:
                    if _hash(path) != frame[1]:
                        raise ValueError('Dynamic capture hash mismatch')
                    supported.add(case)
                evidence.append(path)
        if score is not None and not supported:
            raise ValueError('A scored assessment requires a timed blind note or capture from its session')
        if score is not None and score >= 8 and (set(windows) != supported or incomplete):
            score = None
            reason = reason.strip() + ' Complete case evidence is missing.' + (' ' + partial if partial else '')
        if category in ('blind_narrative_match', 'narrative_flow') and score is not None:
            if any(not any(row['case_id'] == case for row in notes) for case in supported):
                raise ValueError('Blind narrative and pacing scores require live blind notes for each supporting case')
        if category == 'action_sfx_integrity' and score is not None and score >= 8:
            pcm = directory / 'mix.f32le'
            if not pcm.is_file() or any(pcm not in [_local(root, p) for p in by_case[case]] for case in supported):
                raise ValueError('A passing action/SFX assessment requires the same-session audio for every supporting case')
        if category == 'aesthetic_similarity' and score is not None:
            for case in supported:
                paths = [_local(root, p) for p in by_case[case]]
                reference = next(_local(root, row['reference']['path']) for row in plan['cases'] if row['id'] == case)
                if reference not in paths or not any(frames.get(path, (None,))[0] == case for path in paths):
                    raise ValueError('Aesthetic scoring requires the case reference and a timed capture for each supporting case')
        scores[category], reasons[category] = score, reason.strip()
    if recovery_issue:
        reasons['audio_loudness'] += ' ' + recovery_issue
    if notes: evidence.append(notes_path)
    if frame_summary is not None: evidence.append(directory / 'dynamic/frames.jsonl')
    if concurrency_ok: evidence.append(concurrency_path)
    return {'trajectory_id': plan['segment_id'], 'test_id': plan['test_id'],
            'status': 'incomplete' if recovery_issue or incomplete or any(value is None for value in scores.values()) else 'complete',
            'scores': {key: scores[key] for key in CATEGORIES}, 'reasons': {key: reasons[key] for key in CATEGORIES},
            'evidence': list(dict.fromkeys(path.relative_to(root).as_posix() for path in evidence))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', required=True)
    parser.add_argument('--on-receipt', required=True)
    parser.add_argument('--close-receipt', required=True)
    parser.add_argument('--assessment', required=True)
    parser.add_argument('--revision', help='Committed source revision of the test; defaults to HEAD')
    parser.add_argument('--recovered-metrics', help='Explicit same-session recovery summary after an FFmpeg timeout')
    args = parser.parse_args()
    print(json.dumps(prepare(args.plan, args.on_receipt, args.close_receipt, args.assessment, revision=args.revision, recovered_metrics=args.recovered_metrics), ensure_ascii=False, indent=2, allow_nan=False))


if __name__ == '__main__':
    main()
