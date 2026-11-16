"""Development image blind-read comparisons, kept separate from live acceptance."""
from datetime import datetime
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'mcp'))
import capture_provenance as provenance

DIRECTORY = 'artifacts/acceptance/semantic_reviews'


def read(path, root):
    target = provenance.project_path(path, root)
    return json.loads(target.read_text(encoding='utf-8-sig'))


def validate(record, root=ROOT):
    if record.get('schema_version') != 1 or record.get('modality') != 'text_masked_stills':
        raise ValueError('Visual comparison requires schema 1 and text_masked_stills modality')
    if datetime.fromisoformat(record['evaluated_at']).tzinfo is None:
        raise ValueError('Comparison requires timezone')
    plan = read('assets/data/test_scenarios/gameplay_review_plan.json',root)
    if record['segment_id'] not in {s['id'] for s in plan['scenes']}:
        raise ValueError('Unknown mainline segment')
    raw = read(record['observations'],root)
    if raw.get('blind') is not True or raw.get('reviewer') != 'Terra':
        raise ValueError('Require independent Terra blind observations')
    groups = [g for g in raw['groups'] if g['group_id'] == record['group_id']]
    mapping = [g for g in read(record['source_map'],root) if g['group_id'] == record['group_id']]
    inputs = read(record['input_manifest'],root)
    public = [g for g in inputs['groups'] if g['group_id'] == record['group_id']]
    if len(groups) != 1 or len(mapping) != 1 or len(public) != 1 or mapping[0]['segment_id'] != record['segment_id']:
        raise ValueError('Blind group/source mapping mismatch')
    frames = {f['frame_id']:f for f in mapping[0]['frames']}
    if not frames or set(frames) != set(public[0]['frame_ids']):
        raise ValueError('Missing or inconsistent blind frames')
    for f in frames.values():
        checked = provenance.verify_image(f['original'],root,allow_fixture=True)
        if checked['image_sha256'] != f['original_sha256']:
            raise ValueError('Original frame changed after blind-pack creation')
        masked = provenance.project_path(f['masked'],root)
        if hashlib.sha256(masked.read_bytes()).hexdigest() != f['masked_sha256']:
            raise ValueError('Masked frame changed after blind read')
    observation = groups[0]
    if not all(observation.get(k) for k in ('action_observed','intent_guessed','uncertainty','claims')):
        raise ValueError('Missing raw action/intent/uncertainty/claims')
    for claim in observation['claims']:
        if not claim['frame_ids'] or not set(claim['frame_ids']) <= set(frames):
            raise ValueError('Observer references unknown frames')
    if not record.get('comparisons') or not record.get('conclusion') or not record.get('next_fix'):
        raise ValueError('Comparison needs explicit targets, conclusion and next fix')
    for item in record['comparisons']:
        if not item['frame_ids'] or not set(item['frame_ids']) <= set(frames):
            raise ValueError('Comparison references unknown frames')
        if not all(item.get(k) for k in ('expected_action','expected_intent','implementation','difference','truth_sources')):
            raise ValueError('Every target needs intended action/intent, implementation, difference and source')
        for key in ('action_score','intent_score'):
            if type(item[key]) not in (int,float) or item[key] not in (0,5,10):
                raise ValueError('Target scores use 0=missed/wrong, 5=partial, 10=matched')
        for source in item['truth_sources']:
            if not source.get('locator') or not provenance.project_path(source['path'],root).is_file():
                raise ValueError('Truth source must identify an existing file and location')
    return dict(observation=observation,mapping=mapping[0],frames=frames)


def load(root=ROOT):
    records=[]
    for path in sorted((root/DIRECTORY).glob('*.json')):
        envelope=read(path,root)
        record=envelope['record']
        validated=validate(record,root)
        for item in envelope['evidence_sha256']:
            if hashlib.sha256(provenance.project_path(item['path'],root).read_bytes()).hexdigest()!=item['sha256']:
                raise ValueError('Immutable semantic evidence changed: '+item['path'])
        records.append(dict(record,**validated,record_path=path.relative_to(root).as_posix(),
            action_score=round(sum(c['action_score'] for c in record['comparisons'])/len(record['comparisons']),1),
            intent_score=round(sum(c['intent_score'] for c in record['comparisons'])/len(record['comparisons']),1)))
    return sorted(records,key=lambda r:r['evaluated_at'])
