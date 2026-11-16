"""Publish real development survey evidence through the project review MCP."""
from __future__ import annotations
import argparse
import asyncio
import csv
from datetime import datetime
import json
from pathlib import Path
import subprocess
import sys
import yaml

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'mcp'))
sys.path.insert(0, str(ROOT / 'mcp/review'))
import capture_provenance as provenance
from client import invoke

async def publish(directory):
    provenance.assert_runtime_root(ROOT)
    directory = provenance.project_path(directory, ROOT)
    survey = json.loads((directory / 'survey.json').read_text(encoding='utf-8'))
    launch = json.loads((directory / 'launch.json').read_text(encoding='utf-8'))
    pid = launch['host_pid']
    log = (directory / 'godot.log').read_text(encoding='utf-8', errors='replace')
    errors = [line for line in log.splitlines() if line.startswith(('ERROR:', 'SCRIPT ERROR:'))]
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    summaries = []
    for case in survey['cases']:
        provenance.validate_source(case['source_identity'], provenance.project_identity(ROOT), pid=pid)
        for image in case['images']:
            verified = provenance.verify_image(image['path'], ROOT, allow_fixture=True)
            provenance.validate_source(verified['source_identity'], provenance.project_identity(ROOT), pid=pid)
        frames = list(csv.DictReader((directory / case['id'] / 'metrics/frames.csv').open(encoding='utf-8')))
        steady = [float(f['frame_ms']) for f in frames if f['measurement_phase'] == 'steady']
        audio_path = directory / case['id'] / 'metrics/audio.json'
        audio = json.loads(audio_path.read_text(encoding='utf-8')) if audio_path.is_file() else {}
        narrative = max(sum(len(t['text']) for t in image['visible_text'] if t['class'] != 'Label3D' and t['text'] not in ('E', '▼')) for image in case['images'])
        summaries.append(dict(id=case['id'], segment_id=case['segment_id'], images=len(case['images']),
            evidence_collected=[a['id'] for a in case['actions'] if a.get('collected')],
            snapshot_saved=case['snapshot_saved'], snapshot_restored=case['snapshot_restored'],
            sampled_text_max_characters=narrative, steady_frames=len(steady),
            steady_spikes_over_33_3_ms=sum(t > 33.3 for t in steady), steady_max_ms=max(steady, default=None),
            integrated_lufs=audio.get('integrated_lufs'), true_peak_dbtp=audio.get('true_peak_dbtp'),
            issues=case['issues'], acceptance_eligible=False))
    result = dict(captured_at=datetime.now().astimezone().isoformat(), host_pid=pid,
        launch_revision=launch['revision'], launch_working_tree_diff=launch.get('working_tree_diff', ''),
        cases=summaries, runtime_errors=errors, acceptance_eligible=False,
        scope='Mock/snapshot development continuation, not continuous title-to-chapter acceptance',
        limitations=['每个入口独立注入进度；跨入口行走及因果连续性仍需后续测试。',
                    '暂停 Mock 的无证物房间只验证显示与快照；移动输入可能被暂停状态拦截。',
                    '性能采样包含截图像素读取与快照恢复开销；PNG 编码和音频分析在后台。'])
    summary_path = directory / 'summary.yaml'
    summary_path.write_text(yaml.safe_dump(result, allow_unicode=True, sort_keys=False), encoding='utf-8')
    for segment in dict.fromkeys(c['segment_id'] for c in survey['cases']):
        cases = [c for c in survey['cases'] if c['segment_id'] == segment]
        rows = [c for c in summaries if c['segment_id'] == segment]
        event_summary = f"主线遍历：{segment}，{len(cases)} 个入口"
        evidence = [str(summary_path), str(directory / 'launch.json'), str(directory / 'godot.log')]
        for case in cases:
            evidence.extend([str(directory / case['id'] / 'report.json'), case['snapshot']])
            evidence.extend(image['path'] for image in case['images'])
        found = sum(len(c['evidence_collected']) for c in rows)
        text = f"已采集 {sum(c['images'] for c in rows)} 帧；调查取得 {found} 件证物；快照恢复 {sum(c['snapshot_restored'] for c in rows)}/{len(rows)}。"
        if segment == 'shaft': text += f" 北楼梯/监控室出现角色落点不足，日志共 {len(errors)} 次，列为阻塞。"
        if segment == 'poem': text += ' 三个分支均已触发；当前采样仍主要依赖对白。'
        if segment == 'dinner': text += ' 分工节点在 Mock 条件下触发第一章完成；实际夜归路线待测。'
        if segment == 'chapter_end': text += ' 本入口注入章节完成状态，只验证夜间展示与快照。'
        text += f" 稳态超线 {sum(c['steady_spikes_over_33_3_ms'] for c in rows)} 帧；七项独立验收待评。"
        args = dict(work_id='mainline-survey-'+directory.name+'-'+segment, segment_id=segment, kind='check',
            summary=event_summary, result=text, revision=revision, evidence=evidence)
        response = (await invoke('progress_append', args))['result']
        if response.get('isError'): raise RuntimeError(response)
        event = response['structuredContent']['event']
        print(json.dumps(dict(segment=segment, event_id=event['event_id'], result=text), ensure_ascii=False), flush=True)
        args.update(kind='complete', summary='完成本段开发轨迹采集：'+segment,
            result='截图、监控、快照和已发现问题已入册；后续修复及独立验收待进行。', related_event_ids=[event['event_id']])
        response = (await invoke('progress_append', args))['result']
        if response.get('isError'): raise RuntimeError(response)
    print(json.dumps(dict(cases=len(summaries), images=sum(c['images'] for c in summaries), runtime_errors=len(errors), summary=str(summary_path)), ensure_ascii=False))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory')
    asyncio.run(publish(parser.parse_args().directory))
