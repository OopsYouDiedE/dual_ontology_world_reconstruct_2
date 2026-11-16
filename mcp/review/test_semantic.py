"""Exercise semantic MCP validation using visibly synthetic, sandbox-only data.

No independent observer is created or claimed here.  One-pixel image fixtures,
synthetic text and synthetic scores never enter published history or acceptance.
"""
from __future__ import annotations

import asyncio
from copy import deepcopy
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import uuid
import zlib

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'mcp'))
sys.path.insert(0, str(ROOT / 'mcp/review'))
sys.path.insert(0, str(ROOT / 'tools/testing'))
from client import invoke
from core import Store
import capture_provenance as provenance


def png_1px(rgb):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(b'\x00' + bytes(rgb))) + chunk(b'IEND', b''))


def fixture(sandbox, modality, revision):
    directory = sandbox / modality
    directory.mkdir(parents=True)

    def rel(path):
        return path.relative_to(ROOT).as_posix()

    def save(name, value):
        path = directory / name
        path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        return rel(path)

    original = directory / 'synthetic-original-1px.png'
    masked = directory / 'synthetic-input-1px.png'
    original.write_bytes(png_1px((200, 0, 180)))
    masked.write_bytes(original.read_bytes() if modality == 'original_subtitled_stills' else png_1px((0, 200, 80)))
    original_hash = hashlib.sha256(original.read_bytes()).hexdigest()
    masked_hash = hashlib.sha256(masked.read_bytes()).hexdigest()
    identity = provenance.project_identity(ROOT)
    identity['process_id'] = os.getpid()
    original.with_suffix('.png.json').write_text(json.dumps({
        'source_identity': identity, 'image_sha256': original_hash,
        'capture_kind': 'synthetic-1px-test-fixture', 'acceptance_eligible': False,
        'synthetic_test_fixture': True,
    }, ensure_ascii=False, indent=2), encoding='utf-8')
    frame_id = 'G02-F001'
    groups = [{'group_id': 'G02', 'action_observed': 'Synthetic observation, not a real player.',
               'intent_guessed': 'Synthetic guess.', 'uncertainty': 'All data is test-only.',
               'visual_only': 'Synthetic pixels.', 'dialogue_understanding': 'No real dialogue.',
               'claims': [{'frame_ids': [frame_id], 'action_observed': 'Fixture action',
                           'intent_guessed': 'Fixture intent', 'evidence_basis': 'visual'}]}]
    observation = save('synthetic-observations.json', {'synthetic_test_fixture': True, 'blind': True,
                       'reviewer': 'Terra', 'modality': modality, 'groups': groups})
    mapping = save('synthetic-map.json', [{'group_id': 'G02', 'segment_id': 'corridor', 'frames': [{
        'frame_id': frame_id, 'original': rel(original), 'original_sha256': original_hash,
        'masked': rel(masked), 'masked_sha256': masked_hash, 'masks': [] if modality == 'original_subtitled_stills' else [[0, 0, 1, 1]],
    }]}])
    manifest = save('synthetic-manifest.json', {'synthetic_test_fixture': True,
                    'text_mode': 'original_subtitles' if modality == 'original_subtitled_stills' else 'masked',
                    'groups': [{'group_id': 'G02', 'frame_ids': [frame_id]}]})
    truth = directory / 'synthetic-truth.txt'
    truth.write_text('Synthetic protocol target, not game plot or an observation.\n', encoding='utf-8')
    return {
        'schema_version': 1, 'synthetic_test_fixture': True,
        'id': 'synthetic-' + ('original' if modality == 'original_subtitled_stills' else 'masked'),
        'segment_id': 'corridor', 'group_id': 'G02', 'modality': modality, 'revision': revision,
        'evaluated_at': datetime.now().astimezone().isoformat(),
        'observations': observation, 'source_map': mapping, 'input_manifest': manifest,
        'comparisons': [{'frame_ids': [frame_id], 'expected_action': 'Synthetic target action',
                         'expected_intent': 'Synthetic target intent', 'implementation': 'Test fixture',
                         'difference': 'No real observation', 'truth_sources': [{'path': rel(truth), 'locator': 'test'}],
                         'action_score': 5, 'intent_score': 0}],
        'conclusion': 'Synthetic protocol data; not an independent review or score.',
        'next_fix': 'Test only.',
    }


async def main():
    sandbox = ROOT / '.runtime/review-tests' / ('semantic-' + uuid.uuid4().hex)
    sandbox.mkdir(parents=True)
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    record = fixture(sandbox, 'text_masked_stills', revision)
    original = fixture(sandbox, 'original_subtitled_stills', revision)
    checks = []

    async def call(value, expected_error, label):
        response = (await invoke('semantic_append', dict(work_id='semantic-protocol-test',
                    summary='Synthetic sandbox-only protocol validation', record=value), test_sandbox=sandbox))['result']
        assert bool(response.get('isError')) == expected_error, (label, response)
        checks.append(dict(check=label, passed=True))
        return response

    first = await call(record, False, 'synthetic sandbox append via real MCP protocol')
    assert first['structuredContent']['event']['server_identity']['server_pid'] != os.getpid()
    repeat = await call(record, False, 'identical retry is idempotent')
    assert repeat['structuredContent']['duplicate'] is True
    changed = deepcopy(record); changed['conclusion'] = 'different conclusion'
    await call(changed, True, 'immutable comparison overwrite refused')
    changed = deepcopy(record); changed['id'] = 'invalid-segment-test'; changed['segment_id'] = 'wake'
    await call(changed, True, 'cross-segment group refused')
    changed = deepcopy(record); changed['id'] = 'invalid-frame-test'; changed['comparisons'][0]['frame_ids'] = ['G02-F999']
    await call(changed, True, 'unknown frame refused')
    changed = deepcopy(record); changed['id'] = 'invalid-score-test'; changed['comparisons'][0]['intent_score'] = 8
    await call(changed, True, 'arbitrary target score refused')
    changed = deepcopy(record)
    private = json.loads((ROOT / record['source_map']).read_text(encoding='utf-8'))
    private[0]['frames'][0]['masked_sha256'] = '0' * 64
    changed_map = sandbox / 'changed-map.json'; changed_map.write_text(json.dumps(private), encoding='utf-8')
    changed['id'] = 'tampered-image-test'; changed['source_map'] = changed_map.relative_to(ROOT).as_posix()
    await call(changed, True, 'masked image hash mismatch refused')
    await call(original, False, 'synthetic original-subtitle format accepted in sandbox')
    changed = deepcopy(original); changed['id'] = 'wrong-original-modality-test'; changed['input_manifest'] = record['input_manifest']
    await call(changed, True, 'subtitled input cannot masquerade as masked input')
    original_map = json.loads((ROOT / original['source_map']).read_text(encoding='utf-8'))
    original_map[0]['frames'][0]['masks'] = [[0, 0, 1, 1]]
    masked_original = sandbox / 'masked-original-map.json'; masked_original.write_text(json.dumps(original_map), encoding='utf-8')
    changed = deepcopy(original); changed['id'] = 'original-mask-test'; changed['source_map'] = masked_original.relative_to(ROOT).as_posix()
    await call(changed, True, 'original subtitle pixels cannot be masked')
    raw = json.loads((ROOT / original['observations']).read_text(encoding='utf-8'))
    raw['groups'][0]['claims'][0]['evidence_basis'] = 'assumed'
    invalid_basis = sandbox / 'invalid-basis.json'; invalid_basis.write_text(json.dumps(raw), encoding='utf-8')
    changed = deepcopy(original); changed['id'] = 'original-basis-test'; changed['observations'] = invalid_basis.relative_to(ROOT).as_posix()
    await call(changed, True, 'subtitled claim needs visual or dialogue basis')
    changed = deepcopy(record); changed['id'] = 'missing-marker-test'; changed.pop('synthetic_test_fixture')
    await call(changed, True, 'synthetic observation marker cannot be dropped from record')
    changed = deepcopy(record); changed['id'] = 'external-truth-test'
    changed['comparisons'][0]['truth_sources'][0]['path'] = '../outside-evidence.txt'
    await call(changed, True, 'outside-project truth source refused')
    try:
        Store().semantic_append(work_id='synthetic-production-denial', summary='Synthetic only', record=record)
        raise AssertionError('Production accepted a synthetic semantic fixture')
    except ValueError as error:
        assert 'Synthetic semantic' in str(error)
    checks.append(dict(check='production semantic store rejects explicitly synthetic fixture', passed=True))
    report = {'passed': True, 'checks': checks, 'sandbox': str(sandbox), 'synthetic_test_fixture': True,
              'production_written': False, 'independent_observer_claimed': False,
              'at': datetime.now().astimezone().isoformat()}
    output = sandbox / 'result.json'
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'passed': True, 'checks': len(checks), 'report': str(output),
                      'synthetic_test_fixture': True, 'production_written': False}))


if __name__ == '__main__':
    asyncio.run(main())
