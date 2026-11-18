"""Generate revision-bound segment plans from the same 25-case review inventory."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SCENARIOS = Path('assets/data/test_scenarios')
REFERENCES = Path('artifacts/references/all-segments-20261118')
CHAPTER_REFERENCES = {'wake-bedroom': 'R05-morning', 'corridor-meeting': 'corridor-morning',
                      'kitchen-evidence': 'kitchen-morning', 'kitchen-reconstruction': 'kitchen-morning'}


def _hash(root, path):
    target = (root / path).resolve()
    if not target.is_relative_to(root) or not target.is_file():
        raise ValueError(f'Missing project input: {path}')
    return hashlib.sha256(target.read_bytes()).hexdigest()


def _channel(collector, assessor, method):
    return dict(collector=collector, assessor=assessor, method=method)


def make_plan(root, segment, observer, test_id, *, skip_audio=False):
    root = Path(root).resolve()
    if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_-]{0,100}', test_id) or not observer.strip():
        raise ValueError('A safe unique test ID and the assigned observer are required')
    directory = Path('.runtime/segment-plans') / test_id
    inventory = json.loads((root / SCENARIOS / 'mainline_survey.json').read_text(encoding='utf-8'))
    cases = []
    for row in inventory:
        if row['segment_id'] != segment:
            continue
        case = row['id']
        scenario = Path(row['scenario_path'].removeprefix('res://'))
        if (root / scenario).resolve().parent != (root / SCENARIOS / 'segments').resolve():
            raise ValueError(f'Plan case must use a project segment: {case}')
        fixture = json.loads((root / scenario).read_text(encoding='utf-8-sig'))
        if not isinstance(fixture, dict) or fixture.get('id') != case or fixture.get('mode', 'story') != 'story':
            raise ValueError(f'Plan case must match the named story fixture: {case}')
        reference = REFERENCES / (case + '.png')
        receipt = REFERENCES / (case + '.provenance.json')
        if case in CHAPTER_REFERENCES:
            name = CHAPTER_REFERENCES[case]
            reference = Path('output/imagegen/chapter1') / (name + '-v1.png')
            receipt = Path('artifacts/references/chapter1-20261116') / (name + '-receipt.json')
        _hash(root, receipt)
        reference_hash = _hash(root, reference)
        provenance = json.loads((root / receipt).read_text(encoding='utf-8-sig'))
        if provenance.get('output_sha256') != reference_hash:
            raise ValueError(f'Reference image does not match its provenance: {case}')
        cases.append(dict(id=case, segment_id=segment, scenario_path=scenario.as_posix(),
                          scenario_sha256=_hash(root, scenario),
                          reference=dict(path=reference.as_posix(), sha256=reference_hash,
                                         provenance=receipt.as_posix(),
                                         comparison_scope='Lighting, composition and material appearance.')))
    if not cases:
        raise ValueError(f'Unknown story segment: {segment}')
    audio = (_channel('disabled-user-waiver', 'not-assessed-user-waiver', 'Audio skipped by user request')
             if skip_audio else _channel('runtime-master-audio', 'runtime-metrics', 'Same-session PCM and loudness'))
    channels = dict(
        fluidity=_channel('runtime-frame-times', 'runtime-metrics', 'Continuous frame pacing with warmup exclusions'),
        text_density=_channel('runtime-visible-text', 'runtime-metrics', 'Visible English text and on-screen density'),
        action_sfx_integrity=_channel('runtime-frame-capture', observer, 'Visible physical motion, contact and clipping'),
        audio_loudness=audio,
        blind_narrative_match=_channel(observer, 'main-agent', 'Blind account before reference comparison'),
        aesthetic_similarity=_channel('runtime-frame-capture', observer, 'Same-session frames versus preassigned reference'),
        narrative_flow=_channel(observer, observer, 'Pacing and progression across the planned cases'))
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    ready = directory / 'readiness.json'
    plan_path = directory / 'plan.json'
    plan = dict(schema_version=1, collection_mode='simultaneous', entry_mode='segment', segment_id=segment,
                test_id=test_id, revision=revision, max_fps=60, max_hosts=3, audio_capture_enabled=not skip_audio,
                blind_observer=dict(identity=observer, canonical_unseen=True, ready_receipt=ready.as_posix()),
                channels=channels, cases=cases)
    # Exclusive creation preserves previous plans and observer receipts.
    (root / directory).mkdir(parents=True, exist_ok=False)
    (root / plan_path).write_text(json.dumps(plan, indent=2) + '\n', encoding='utf-8')
    return dict(test_id=test_id, observer=observer, plan_path=plan_path.as_posix(), readiness_path=ready.as_posix(),
                scenario_path=cases[0]['scenario_path'], case_ids=[c['id'] for c in cases])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('segment')
    parser.add_argument('observer')
    parser.add_argument('test_id')
    parser.add_argument('--skip-audio', action='store_true', help='Use only when audio collection has been waived')
    args = parser.parse_args()
    print(json.dumps(make_plan(ROOT, args.segment, args.observer, args.test_id, skip_audio=args.skip_audio)))


if __name__ == '__main__':
    main()
