"""Run the first expedition's 60 Hz regression matrix; output lives under .runtime/."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
SCENE = 'res://scenes/expedition_01/'
TOOLS = 'res://tools/expedition/'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--logic-only', action='store_true')
    parser.add_argument('--seed', type=int, default=31)
    args = parser.parse_args()
    out = ROOT / '.runtime' / 'first-expedition-checks' / str(args.seed)
    out.mkdir(parents=True, exist_ok=True)
    exe = os.environ.get('DV_GODOT') or ROOT / '.runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe'
    cases = [(n, SCENE + n, [], False) for n in ('ContractTest', 'ArchiveTest', 'BoardBlackoutTest', 'StoryOrderTest', 'HaleFollowTest', 'FeelTest', 'HearingTest', 'NewVerbsTest', 'NicheTest', 'MaintenanceLoopTest', 'ShaftRecoveryTest', 'WalkTest')]
    cases.extend((flag, SCENE + 'WalkTest', ['--' + flag], False) for flag in ('south', 'clock-only', 'oil-only', 'skip-window', 'transit-only'))
    cases += [('human-policy', TOOLS + 'human_sol_test', [], False), ('rehearsal', TOOLS + 'record_first_expedition', [], False)]
    if not args.logic_only:
        cases += [('framing', TOOLS + 'framing_audit', [], True), ('mouse', SCENE + 'MouseLifecycleTest', [], True)]
    cases.insert(2, ('archive-replay', SCENE + 'ArchiveTest', [], False))
    rows = []
    for label, script, flags, display in cases:
        log = out / (label + '.log')
        renderer = ['--rendering-method', 'forward_plus', '--windowed', '--position', '-32000,-32000'] if display else ['--headless']
        cmd = [exe, '--path', '.', *renderer, '--audio-driver', 'Dummy', '--fixed-fps', '60', '--script', script + '.gd', '--', '--run-seed=' + str(args.seed), *flags]
        is_trace = label in ('ArchiveTest', 'archive-replay')
        if is_trace:
            trace_dir = out / label
            trace_dir.mkdir(exist_ok=True)
            cmd.append('--archive-trace-dir=' + trace_dir.as_posix())
            trace_names = ('archive-direct.json', 'archive-foldback-repeat.json')
            for name in trace_names:
                (trace_dir / name).unlink(missing_ok=True)
        start = time.monotonic()
        with log.open('wb') as f:
            try:
                rc = subprocess.run(cmd, cwd=ROOT, stdout=f, stderr=subprocess.STDOUT, timeout=240).returncode
            except subprocess.TimeoutExpired:
                rc = 124
        errors = re.findall(r'(?m)^\s*(?:(?:SCRIPT |SHADER )?ERROR:|FAIL[: ]).*', log.read_text(encoding='utf8', errors='replace'))
        if is_trace:
            for name in trace_names:
                trace = trace_dir / name
                first = out / 'ArchiveTest' / name
                if not trace.is_file() or not trace.stat().st_size:
                    errors.append(f'Missing decision trace: {name}')
                elif label == 'archive-replay' and (not first.is_file() or first.read_bytes() != trace.read_bytes()):
                    errors.append(f'Different decision trace on same-seed replay: {name}')
        ok = rc == 0 and not errors
        rows.append(dict(case=label, ok=ok, exit=rc, seconds=round(time.monotonic()-start, 2), errors=errors[:4]))
        print(f'{label}: {"PASS" if ok else "FAIL"} ({rows[-1]["seconds"]} s)', flush=True)
        (out / 'report.json').write_text(json.dumps(rows, indent=2, ensure_ascii=False), encoding='utf8')
    return int(any(not row['ok'] for row in rows))


if __name__ == '__main__':
    sys.exit(main())
