"""Exercise semantic validation and immutable writes over real MCP stdio."""
import asyncio
from copy import deepcopy
from datetime import datetime
import json
from pathlib import Path
import sys
import uuid

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'mcp/review'))
sys.path.insert(0,str(ROOT/'tools/testing'))
from client import invoke
import visual_semantic_reviews as semantic


async def main():
    record=json.loads((ROOT/'artifacts/acceptance/visual-blind-20261116-v3/comparisons/corridor.json').read_text(encoding='utf-8'))
    sandbox=ROOT/'.runtime/review-tests'/('semantic-'+uuid.uuid4().hex)
    sandbox.mkdir(parents=True)
    checks=[]
    async def call(r,expected_error,label):
        response=(await invoke('semantic_append',dict(work_id='semantic-protocol-test',summary='Isolated protocol validation',record=r),test_sandbox=sandbox))['result']
        assert bool(response.get('isError'))==expected_error,(label,response)
        checks.append(dict(check=label,passed=True))
        return response
    first=await call(record,False,'real protocol append')
    repeat=await call(record,False,'identical retry is idempotent')
    assert repeat['structuredContent']['duplicate'] is True
    changed=deepcopy(record);changed['conclusion']='different conclusion'
    await call(changed,True,'immutable comparison overwrite refused')
    changed=deepcopy(record);changed['id']='invalid-segment-test';changed['segment_id']='wake'
    await call(changed,True,'cross-segment blind group refused')
    changed=deepcopy(record);changed['id']='invalid-frame-test';changed['comparisons'][0]['frame_ids']=['G02-F999']
    await call(changed,True,'unknown frame refused')
    changed=deepcopy(record);changed['id']='invalid-score-test';changed['comparisons'][0]['intent_score']=8
    await call(changed,True,'unexplained arbitrary target score refused')
    changed=deepcopy(record)
    private=json.loads((ROOT/record['source_map']).read_text(encoding='utf-8'))
    private[1]['frames'][0]['masked_sha256']='0'*64
    changed_map=sandbox/'changed-map.json';changed_map.write_text(json.dumps(private),encoding='utf-8')
    changed['id']='tampered-image-test';changed['source_map']=changed_map.relative_to(ROOT).as_posix()
    await call(changed,True,'masked image hash mismatch refused')
    original=json.loads((ROOT/'artifacts/acceptance/opening-observer-20261116-v1/comparisons/corridor.json').read_text(encoding='utf-8'))
    await call(original,False,'original subtitle review accepted over real protocol')
    changed=deepcopy(original);changed['id']='wrong-original-modality-test';changed['input_manifest']=record['input_manifest']
    await call(changed,True,'subtitled input cannot masquerade as masked input')
    original_map=json.loads((ROOT/original['source_map']).read_text(encoding='utf-8'))
    original_map[1]['frames'][0]['masks']=[[0,0,100,100]]
    masked_original=sandbox/'masked-original-map.json';masked_original.write_text(json.dumps(original_map),encoding='utf-8')
    changed=deepcopy(original);changed['id']='original-mask-test';changed['source_map']=masked_original.relative_to(ROOT).as_posix()
    await call(changed,True,'original subtitle pixels must remain unmasked')
    raw=json.loads((ROOT/original['observations']).read_text(encoding='utf-8'))
    raw['groups'][1]['claims'][0]['evidence_basis']='assumed'
    invalid_basis=sandbox/'invalid-basis.json';invalid_basis.write_text(json.dumps(raw),encoding='utf-8')
    changed=deepcopy(original);changed['id']='original-basis-test';changed['observations']=invalid_basis.relative_to(ROOT).as_posix()
    await call(changed,True,'subtitled claims require explicit visual or dialogue basis')
    report=dict(passed=True,checks=checks,sandbox=str(sandbox),production_written=False,
        at=datetime.now().astimezone().isoformat())
    output=sandbox/'result.json';output.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(dict(passed=True,checks=len(checks),report=str(output))))


if __name__=='__main__':asyncio.run(main())
