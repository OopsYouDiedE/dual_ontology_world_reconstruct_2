"""Run the room fast check, then capture one production observation from a snapshot."""
from __future__ import annotations

import argparse
import asyncio
from datetime import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'mcp'))
import capture_provenance as provenance
sys.path.insert(0, str(ROOT / 'mcp/review'))
from client import invoke


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def run_mode(mode, folder, kind, snapshot, work):
    executable = provenance.host_executable(ROOT / '.runtime/godot/4.7.2-standard/Godot_v4.7.2-stable_win64.exe')
    fast = mode == 'fast'
    script = 'tools/test/' + ('room_fast_check.gd' if fast else 'observation_snapshot_probe.gd')
    report = folder / ('fast-check.json' if fast else 'report.json')
    options = ['--headless'] if fast else ['--rendering-method', 'gl_compatibility', '--resolution', '1440x900']
    args = ['--dv-fast-output=' + str(report)] if fast else ['--probe-kind=' + kind, '--probe-output=' + str(folder)]
    command = [executable, *options, '--path', str(ROOT), '--script', 'res://' + script, '--',
               '--dv-snapshot=' + str(snapshot), '--dv-checkpoint-auto=false',
               '--dv-save-slot=observation-probe-development', *args]
    started = time.monotonic()
    process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    print(json.dumps({'mode': mode, 'pid': process.pid, 'folder': str(folder)}), flush=True)
    timed_out = False
    try:
        raw = process.communicate(timeout=5 if fast else 20)[0]
    except (subprocess.TimeoutExpired, KeyboardInterrupt):
        timed_out = True
        process.terminate()
        raw = process.communicate(timeout=5)[0]
    elapsed = time.monotonic() - started
    log = raw.decode('utf-8', errors='replace')
    (folder / (mode + '.log')).write_text(log, encoding='utf-8')
    result = json.loads(report.read_text(encoding='utf-8-sig')) if report.is_file() else {}
    identity = result.get('project' if fast else 'source_identity')
    identity_error = None
    try:
        provenance.validate_source(identity, provenance.project_identity(ROOT), pid=process.pid, executable=executable)
    except ValueError as error:
        identity_error = str(error)
    passed = bool(result.get('pass')) and process.returncode == 0 and not timed_out and not identity_error
    passed = passed and not any(s in log for s in ('SCRIPT ERROR', 'Shader compilation failed', 'ERROR:'))
    if fast:
        passed = passed and elapsed < 5
    sources = [script, 'scenes/components/interaction/RoomObservation.gd',
               'scenes/components/world/WindowCourtyard.gd', 'scenes/components/testing/RoomFastCheck.gd',
               'scenes/components/interaction/InRoomEvidenceCloseup.gd']
    launch = folder / (mode + '.launch.json')
    write(launch, {'mode': mode, 'pass': passed, 'pid': process.pid, 'command': command,
                  'source_identity': identity, 'identity_error': identity_error, 'elapsed_s': elapsed,
                  'exit_code': process.returncode, 'timed_out': timed_out,
                  'source_sha256': {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in sources}})
    evidence = [launch.relative_to(ROOT).as_posix(), (folder / (mode + '.log')).relative_to(ROOT).as_posix()]
    if report.is_file():
        evidence.append(report.relative_to(ROOT).as_posix())
    response = asyncio.run(invoke('progress_append', {
        'work_id': work, 'segment_id': 'wake', 'kind': 'check',
        'summary': kind + (' 原房间七处快检' if fast else ' 原场景四阶段采集'),
        'result': f'pass={passed}, PID={process.pid}, {elapsed:.3f}s; development probe, acceptance pending.',
        'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'evidence': evidence}))['result']
    if response.get('isError'):
        raise RuntimeError(response)
    print(json.dumps({'mode': mode, 'pass': passed, 'elapsed_s': elapsed,
                      'event_id': response['structuredContent']['event']['event_id']}), flush=True)
    return passed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kind', required=True, choices=['bed', 'lamp', 'desk', 'window', 'wardrobe', 'wash'])
    parser.add_argument('--snapshot', default='.runtime/checkpoints/fixtures/opening-free.json')
    parser.add_argument('--output', default='artifacts/acceptance/observation-probe-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
    parser.add_argument('--work-id', required=True)
    args = parser.parse_args()
    provenance.assert_runtime_root(ROOT)
    snapshot = provenance.project_path(args.snapshot, ROOT)
    folder = provenance.project_path(args.output, ROOT)
    if not snapshot.is_file():
        parser.error('Project checkpoint missing')
    folder.mkdir(parents=True, exist_ok=False)
    if not run_mode('fast', folder, args.kind, snapshot, args.work_id):
        return 1
    return 0 if run_mode('capture', folder, args.kind, snapshot, args.work_id) else 1


if __name__ == '__main__':
    raise SystemExit(main())
