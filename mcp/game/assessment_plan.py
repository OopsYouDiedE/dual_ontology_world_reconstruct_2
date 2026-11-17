"""Validate synchronous assessment inputs before reserving a game process."""
import hashlib
import json
from pathlib import Path
import subprocess

CATEGORIES = ('fluidity', 'text_density', 'action_sfx_integrity', 'audio_loudness',
              'blind_narrative_match', 'aesthetic_similarity', 'narrative_flow')


def validate(path, root, revision=None):
    root = Path(root).resolve()
    def local(value):
        result = (root / value).resolve()
        if not result.is_relative_to(root) or not result.is_file():
            raise ValueError('Assessment input must be an existing project file: ' + str(value))
        return result
    plan_path = local(path)
    plan = json.loads(plan_path.read_text(encoding='utf-8-sig'))
    if plan.get('schema_version') != 1 or plan.get('collection_mode') != 'simultaneous':
        raise ValueError('A simultaneous seven-category assessment plan is required')
    revision = revision or subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    if plan.get('revision') != revision or not plan.get('test_id'):
        raise ValueError('Assessment test ID and current committed revision are required')
    if plan.get('max_fps') != 60 or not 1 <= plan.get('max_hosts', 0) <= 3:
        raise ValueError('Assessment requires a 60 FPS cap and at most three hosts')
    channels = plan.get('channels', {})
    if set(channels) != set(CATEGORIES):
        raise ValueError('All seven assessment channels must be configured before launch')
    for category in CATEGORIES:
        channel = channels[category]
        if not isinstance(channel, dict) or any(not str(channel.get(key, '')).strip()
                for key in ('collector', 'assessor', 'method')):
            raise ValueError('Missing collector/assessor/method for ' + category)
    observer = plan.get('blind_observer', {})
    if not observer.get('identity') or observer.get('canonical_unseen') is not True:
        raise ValueError('A context-isolated blind observer must be assigned before launch')
    ready = json.loads(local(observer.get('ready_receipt', '')).read_text(encoding='utf-8-sig'))
    if (ready.get('test_id') != plan['test_id'] or ready.get('observer') != observer['identity']
            or ready.get('ready') is not True or ready.get('canonical_unseen') is not True):
        raise ValueError('Blind observer readiness receipt does not match this test')
    cases = plan.get('cases', [])
    if not cases or len({c.get('id') for c in cases}) != len(cases):
        raise ValueError('A nonempty, unique scene coverage plan is required')
    for case in cases:
        if not case.get('id') or not case.get('segment_id'):
            raise ValueError('Each scene needs an ID and segment')
        reference = case.get('reference', {})
        image = local(reference.get('path', ''))
        if hashlib.sha256(image.read_bytes()).hexdigest() != reference.get('sha256'):
            raise ValueError('Reference hash mismatch for ' + case['id'])
        receipt = local(reference.get('provenance', ''))
        if not receipt.stat().st_size:
            raise ValueError('Reference provenance is empty')
        if plan.get('entry_mode') == 'segment':
            scenario = local(case.get('scenario_path', ''))
            if hashlib.sha256(scenario.read_bytes()).hexdigest() != case.get('scenario_sha256'):
                raise ValueError('Scenario hash mismatch for ' + case['id'])
            if case['segment_id'] != plan.get('segment_id'):
                raise ValueError('One segment test may only contain its own scene cases')
    return dict(plan, plan_path=str(plan_path), plan_sha256=hashlib.sha256(plan_path.read_bytes()).hexdigest())
