"""Cross the three archive approaches with four loadouts and three shaft strategies."""
import argparse
import itertools
import json
import os
import re
import subprocess
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from human_batch import godot_path

ROOT = Path(__file__).resolve().parents[2]
APPROACH = {'witness': [], 'skip': ['--skip-window'], 'transit': ['--transit-only']}
LOADOUT = {'both': [], 'clock': ['--clock-only'], 'oil': ['--oil-only'], 'neither': ['--south']}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--jobs', type=int, default=3)
    p.add_argument('--seed', type=int, default=31)
    p.add_argument('--approaches', nargs='+', choices=APPROACH, default=list(APPROACH))
    p.add_argument('--loadouts', nargs='+', choices=LOADOUT, default=list(LOADOUT))
    p.add_argument('--crossings', nargs='+', choices=['north', 'self', 'south'], default=['north', 'self', 'south'])
    p.add_argument('--radii', nargs='+', type=float, default=[0.12], help='waypoint arrival radii (meters)')
    p.add_argument('--settle-ticks', nargs='+', type=int, default=[116], help='extra waiting after initial 44 ticks, where the trial is taken')
    p.add_argument('--full', action='store_true', help='keep full scene effects (still headless)')
    args = p.parse_args()
    if not 1 <= args.jobs <= 12:
        p.error('jobs must be 1..12')
    if any(not 0.04 <= r <= 0.25 for r in args.radii) or any(not 1 <= t <= 600 for t in args.settle_ticks):
        p.error('radii must be 0.04..0.25 m; extra settle ticks 1..600')
    dims = [args.approaches, args.loadouts, args.crossings, args.radii, args.settle_ticks]
    if any(len(d) != len(set(d)) for d in dims):
        p.error('duplicate parameter value')
    exe = str(godot_path(os.getenv('DV_GODOT')))
    base = ROOT / '.runtime/route-matrix'
    base.mkdir(parents=True, exist_ok=True)
    out = Path(tempfile.mkdtemp(prefix=f'seed{args.seed}-', dir=base))

    def run(pair):
        approach, loadout, crossing, radius, settle = pair
        name = f'{approach}-{loadout}-{crossing}-r{radius}-t{settle}'
        folder = out / name
        folder.mkdir()
        trace = folder / 'decisions.json'
        log = folder / 'console.log'
        cmd = [exe, '--path', str(ROOT), '--headless', '--audio-driver', 'Dummy', '--fixed-fps', '60',
               '--log-file', str(folder / 'engine.log'), '--script', 'res://scenes/expedition_01/WalkTest.gd',
               '--', f'--run-seed={args.seed}', '--walk-trace=' + trace.as_posix(), *APPROACH[approach], *LOADOUT[loadout], '--crossing=' + crossing,
               f'--arrival-radius={radius}', f'--settle-ticks={settle}', '--route-output=' + (folder / 'route.json').as_posix()]
        if not args.full:
            cmd.append('--strategy-light')
        user = str(folder / 'user')
        Path(user).mkdir()
        env = dict(os.environ, APPDATA=user, LOCALAPPDATA=user, XDG_DATA_HOME=user, XDG_CONFIG_HOME=user, XDG_CACHE_HOME=user)
        t = time.perf_counter()
        with log.open('wb') as f:
            try:
                code = subprocess.run(cmd, cwd=ROOT, env=env, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0), stdout=f, stderr=subprocess.STDOUT, timeout=180).returncode
            except subprocess.TimeoutExpired:
                code = 124
        text = log.read_text(encoding='utf8', errors='replace')
        issues = re.findall(r'(?m)^\s*(?:(?:SCRIPT |SHADER )?ERROR:|FAIL[: ]).*', text)
        outcome, reason, ticks = "no_report", "", 0
        try:
            replay = json.loads((folder / 'route.json').read_text(encoding='utf8'))
            outcome, reason, ticks = replay['outcome'], replay.get('failure_reason', ''), replay['tick']
            if not replay['path_samples'] or not replay['hale_path_samples'] or not replay['events']:
                issues.append('incomplete spatial replay')
            if outcome == 'completed':
                facts = json.loads(trace.read_text(encoding='utf8'))['facts']
                if ('dual_gaze_b2' in facts) != (approach == 'witness'):
                    issues.append('unexpected window evidence')
        except (ValueError, KeyError, OSError) as e:
            issues.append(str(e))
        if outcome == 'completed' and not ticks:
            issues.append('missing route physics ticks')
        ok = code == 0 and 'PASS: A1 to evacuation;' in text and not issues
        print(name, 'PASS' if ok else 'FAIL', flush=True)
        return dict(case=name, ok=ok, exit=code, ticks=ticks, outcome=outcome, reason=reason, errors=issues, command=cmd, seconds=round(time.perf_counter()-t, 2))

    t = time.perf_counter()
    with ThreadPoolExecutor(args.jobs) as pool:
        rows = list(pool.map(run, itertools.product(*dims)))
    report = dict(seed=args.seed, jobs=args.jobs, elapsed_seconds=round(time.perf_counter()-t, 2), cases=rows)
    report['sim_seconds'] = round(sum(row['ticks'] for row in rows) / 60, 2)
    report['aggregate_realtime_multiple'] = round(report['sim_seconds'] / report['elapsed_seconds'], 2)
    (out / 'report.json').write_text(json.dumps(report, indent=2), encoding='utf8')
    print(out, report['elapsed_seconds'], 's')
    return int(not all(row['ok'] for row in rows))


if __name__ == '__main__':
    raise SystemExit(main())
