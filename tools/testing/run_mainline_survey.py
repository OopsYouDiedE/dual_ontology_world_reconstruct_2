"""Run the chapter survey in the project-owned rendered Godot host."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from survey_plan import resolve_case

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'mcp'))
import capture_provenance as provenance

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', default='assets/data/test_scenarios/mainline_survey.json')
    parser.add_argument('--output')
    parser.add_argument('--segment', action='append')
    parser.add_argument('--timeout', type=float, default=420)
    args = parser.parse_args()
    provenance.assert_runtime_root(ROOT)
    plan = provenance.project_path(args.plan, ROOT)
    cases = json.loads(plan.read_text(encoding='utf-8-sig'))
    if args.segment:
        cases = [c for c in cases if c['segment_id'] in args.segment]
    if not cases: parser.error('No matching story segments')
    cases = [resolve_case(case, ROOT) for case in cases]
    output = provenance.project_path(args.output or 'artifacts/acceptance/mainline-survey-'+datetime.now().strftime('%Y%m%d-%H%M%S-%f'), ROOT)
    output.mkdir(parents=True, exist_ok=False)
    local_plan = output / 'plan.json'
    local_plan.write_text(json.dumps(cases, ensure_ascii=False, indent=2), encoding='utf-8')
    command = [provenance.host_executable(ROOT / '.runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64.exe'),
        '--path', str(ROOT), '--script', 'res://tools/test/mainline_survey.gd', '--',
        '--survey-plan='+str(local_plan), '--survey-output='+str(output), '--dv-checkpoint-auto=false',
        '--dv-checkpoint-stop='+str(output/'interrupt.request')]
    sources = ['tools/test/mainline_survey.gd', 'tools/testing/TestStoryHost.gd',
        'scenes/dual_world/DualWorldMain.gd', 'scenes/components/testing/StoryCheckpoint.gd']
    receipt = dict(project=provenance.project_identity(ROOT), command=command, acceptance_eligible=False,
        revision=subprocess.check_output(['git','rev-parse','HEAD'], cwd=ROOT, text=True).strip(),
        working_tree_diff=subprocess.check_output(['git','diff','--stat'], cwd=ROOT, text=True),
        source_sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in sources},
        start=datetime.now().astimezone().isoformat())
    path = output / 'launch.json'
    with (output / 'godot.log').open('w', encoding='utf-8') as log:
        process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
            creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        receipt['host_pid'] = process.pid
        path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding='utf-8')
        print(json.dumps(dict(started=True, pid=process.pid, output=str(output))), flush=True)
        try: code = process.wait(timeout=args.timeout)
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            receipt['interrupted'] = True
            (output/'interrupt.request').write_text(str(process.pid), encoding='utf-8')
            try: code = process.wait(timeout=10) or 124
            except subprocess.TimeoutExpired:
                process.terminate()
                code = process.wait(timeout=10) or 124
    errors = [line for line in (output/'godot.log').read_text(encoding='utf-8', errors='replace').splitlines() if line.startswith(('ERROR:', 'SCRIPT ERROR:'))]
    receipt.update(exit_code=code, runtime_errors=errors, end=datetime.now().astimezone().isoformat(),
        outcome='blocked' if code or errors else 'captured_pending_review')
    path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(dict(output=str(output), outcome=receipt['outcome'], runtime_errors=len(errors))))
    return code or int(bool(errors))

if __name__ == '__main__':
    raise SystemExit(main())
