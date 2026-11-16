"""Validated, continuous development recordings attached by progress_append evidence."""
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'mcp'))
import capture_provenance as provenance


def read(relative, root=ROOT):
    return json.loads(provenance.project_path(relative,root).read_text(encoding='utf-8-sig'))


def validate(record, root=ROOT):
    if record.get('schema_version') != 1 or record.get('kind') != 'continuous-mainline-recording':
        raise ValueError('Unknown continuous recording format')
    if record.get('acceptance_eligible') is not False or record['segment_id'] not in ('wake','corridor'):
        raise ValueError('Opening recordings are development evidence')
    launch, sequence = read(record['launch'],root), read(record['sequence'],root)
    provenance.validate_source(sequence['source_identity'],launch['project'],pid=launch['host_pid'])
    if launch.get('exit_code') != 0 or sequence.get('failure') or sequence.get('skip_subtitles') is not False or sequence.get('engine_time_scale') != 1:
        raise ValueError('Recording must finish at normal speed with original subtitles')
    for item in record['evidence_sha256']:
        if hashlib.sha256(provenance.project_path(item['path'],root).read_bytes()).hexdigest() != item['sha256']:
            raise ValueError('Continuous recording evidence changed: '+item['path'])
    hashed={provenance.project_path(item['path'],root) for item in record['evidence_sha256']}
    if any(provenance.project_path(record[key],root) not in hashed for key in ('launch','sequence','coverage','video','full_video','end_snapshot')):
        raise ValueError('Every recording link must be bound to its evidence hash')
    if any(provenance.project_path(record[key],root).suffix!='.mp4' for key in ('video','full_video')):
        raise ValueError('Recording media must be MP4')
    coverage = read(record['coverage'],root)
    if not coverage['complete'] or not coverage['dialogue_complete']:
        raise ValueError('Incomplete recording cannot be published as complete')
    if coverage.get('host_pid')!=launch['host_pid']:
        raise ValueError('Coverage belongs to another process')
    segment = record['segment_id']
    images = []
    for frame in sequence['frames']:
        if frame['segment_id'] != segment: continue
        provenance.validate_source(frame['source_identity'],launch['project'],pid=launch['host_pid'])
        provenance.verify_image(frame['path'],root,allow_fixture=True)
        caption = f"{frame['time_s']:.1f}s · {frame['phase']}"
        if frame['interaction']: caption += ' · '+frame['interaction']
        if frame['subtitle']: caption += ' · '+frame['subtitle']
        images.append({'path':str(provenance.project_path(frame['path'],root).relative_to(root)).replace('\\','/'),'caption':caption})
    if not images: raise ValueError('No segment frames')
    return dict(record,images=images,coverage_data=coverage,
                subtitles=[s for s in sequence['subtitles'] if s['segment_id']==segment],
                phases=[e for e in sequence['events'] if e.get('event')=='phase_enter' and e['state'].startswith(segment+':')])


def load(events,root=ROOT):
    records = {}
    for event in events:
        if event['kind'] != 'check': continue
        for evidence in event.get('evidence',[]):
            if not evidence.endswith('.capture.json'): continue
            record = validate(read(evidence,root),root)
            if record['segment_id'] != event['segment_id']:
                raise ValueError('Capture attached to wrong mainline segment')
            records.setdefault(record['segment_id'],[]).append(record)
    return records
