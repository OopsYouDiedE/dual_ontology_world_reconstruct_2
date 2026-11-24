"""Run and summarize isolated, real-scene Human Sol benchmarks."""
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
BATCH = ROOT / '.runtime/human_batch'
PROFILES = ('cautious', 'curious', 'direct')
DELAYS = dict(zip(PROFILES, ((12, 14), (15, 17), (19, 21))))
HOLDS = dict(zip(PROFILES, (41, 43, 48)))
EXIT = {'completed': 0, 'failed': 1, 'tick_budget': 1}
ERROR = re.compile(r'^\s*(?:SCRIPT |USER |SHADER |PUSH )?ERROR:', re.MULTILINE)


def save(path, data):
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    temp.replace(path)


def godot_path(value):
    if not value:
        value = (ROOT / '.runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64.exe'
                 if os.name == 'nt' else 'godot')
    exe = Path(shutil.which(str(value)) or value).resolve(strict=True)
    # Own the actual Godot PID on Windows, not its console launcher.
    if os.name == 'nt' and exe.stem.lower().endswith('_console'):
        exe = exe.with_name(exe.stem[:-8] + exe.suffix).resolve(strict=True)
    return exe


def inspect_report(report, profile, seed, ticks, user, code, fixture):
    if not isinstance(report, dict):
        raise ValueError('report must be an object')
    for key, expected in (('profile', profile), ('seed', seed), ('physics_hz', 60),
                          ('fixture', 'light' if fixture == 'strategy-light' else 'full')):
        if report.get(key) != expected:
            raise ValueError(f'unexpected {key}: {report.get(key)!r}')
    outcome, tick = report['outcome'], report['tick']
    if EXIT.get(outcome) != code or not 0 <= tick <= ticks or (outcome == 'tick_budget' and tick != ticks):
        raise ValueError('inconsistent outcome, tick or exit code')
    if user.resolve() not in Path(report['user_dir']).resolve().parents:
        raise ValueError('Godot user data escaped sandbox')
    p = report['policy_parameters']
    lo, hi = DELAYS[profile]
    if not (lo <= p['delay'] <= hi and report['delay_ticks'] == p['delay']
            and -3 <= p['hold_offset'] <= 3 and p['hold'] == HOLDS[profile] + p['hold_offset']
            and p['side'] in (-1, 1)):
        raise ValueError('invalid sampled policy parameters')
    return {k: report[k] for k in ('outcome', 'tick', 'reason', 'distance_m', 'decisions',
                                   'regions', 'longest_dwell', 'policy_parameters')}


def run_case(exe, directory, profile, seed, ticks, timeout, fixture):
    directory.mkdir()
    user = directory / 'user'
    user.mkdir()
    cmd = [str(exe), '--headless', '--fixed-fps', '60', '--path', str(ROOT),
           '--log-file', str(directory / 'engine.log'), '-s', 'res://tools/expedition/human_sol.gd',
           '--', f'--{fixture}', '--rogue-mcp-dir=', f'--run-seed={seed}', f'--profile={profile}', f'--ticks={ticks}',
           f'--output={directory / "report.json"}', f'--batch-user-root={user.as_posix()}']
    env = dict(os.environ, APPDATA=str(user), LOCALAPPDATA=str(user),
               XDG_DATA_HOME=str(user), XDG_CONFIG_HOME=str(user), XDG_CACHE_HOME=str(user))
    row = dict(profile=profile, seed=seed, directory=directory.name, command=cmd, returncode=None)
    start = time.perf_counter()
    with (directory / 'console.log').open('wb') as log:
        try:
            result = subprocess.run(cmd, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT,
                                    timeout=timeout, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
            row['returncode'] = result.returncode
        except subprocess.TimeoutExpired:
            row.update(status='timeout', detail=f'Exceeded {timeout:g} s; Godot killed')
        except OSError as e:
            row.update(status='launch_error', detail=str(e))
    row['wall_seconds'] = round(time.perf_counter() - start, 4)
    errors = {}
    for name in ('engine.log', 'console.log'):
        path = directory / name
        if path.exists():
            errors[name] = len(ERROR.findall(path.read_text(encoding='utf-8', errors='replace')))
    row['log_error_lines'] = errors
    try:
        report = json.loads((directory / 'report.json').read_text(encoding='utf-8'))
        row.update(inspect_report(report, profile, seed, ticks, user, row['returncode'], fixture))
    except (OSError, ValueError, KeyError, TypeError) as e:
        row.setdefault('status', 'invalid_report')
        row.setdefault('detail', str(e))
    if any(errors.values()) and row.get('status') not in ('timeout', 'launch_error'):
        row.update(status='engine_error', detail='See per-case logs')
    row.setdefault('status', 'ok')
    save(directory / 'case.json', row)
    return row


def summarize(batch, require_completion=False):
    data = json.loads((batch / 'batch.json').read_text(encoding='utf-8'))
    rows = data['cases']
    print(f'{batch} | {len(rows)}/{data["planned"]} cases | {data["ticks"]} tick budget @ 60 Hz'
          f' | fixture: {data.get("fixture", "unspecified")}')
    print('profile      seed               status          outcome        tick      m   dwell   wall s   sim/wall  delay/hold/side')
    for r in rows:
        p = r.get('policy_parameters')
        perf = (f'{r["tick"]:6} {r["distance_m"]:6.1f} {r["longest_dwell"][1]-r["longest_dwell"][0]:7} '
                if p else '     -      -       - ')
        speed = f'{r["tick"]/60/r["wall_seconds"]:6.2f}x' if p and r['wall_seconds'] else '      -'
        params = f'{p["delay"]}/{p["hold"]}/{p["side"]:+g}' if p else '-'
        print(f'{r["profile"]:10} {r["seed"]:20} {r["status"]:15} {r.get("outcome", "-"):12} '
              f'{perf}{r["wall_seconds"]:8.2f} {speed:>10}  {params}')
    for field in ('status', 'outcome'):
        counts = Counter(r[field] for r in rows if field in r)
        print(f'{field.capitalize()} counts:', ', '.join(f'{k}={v}' for k, v in sorted(counts.items())) or 'none')
    sim = sum(r.get('tick', 0) for r in rows) / 60
    clean_sim = sum(r['tick'] for r in rows if r['status'] == 'ok') / 60
    wall = data.get('batch_wall_seconds', 0)
    if wall:
        print(f'Aggregate: {sim:.2f} simulated s / {wall:.2f} batch wall s = {sim/wall:.2f}x '
              f'({data["jobs"]} workers; validated reports)')
        if clean_sim != sim:
            print(f'Clean cases: {clean_sim:.2f} simulated s / {wall:.2f} batch wall s = {clean_sim/wall:.2f}x')
    bad = len(rows) != data['planned'] or any(r['status'] != 'ok' for r in rows)
    return int(bad or (require_completion and any(r['outcome'] != 'completed' for r in rows)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='mode', required=True)
    run = sub.add_parser('run')
    run.add_argument('--profiles', nargs='+', choices=PROFILES, default=PROFILES)
    run.add_argument('--seeds', nargs='+', type=int, required=True)
    run.add_argument('--ticks', type=int, default=7200)
    run.add_argument('--timeout', type=float, default=120, help='wall seconds per case')
    run.add_argument('--godot', default=os.environ.get('DV_GODOT'))
    run.add_argument('--jobs', type=int, default=1, help='concurrent Godot processes (1-8)')
    run.add_argument('--full', action='store_true', help='request the full rendering-effects fixture (still headless)')
    summary = sub.add_parser('summary')
    summary.add_argument('batch', type=Path)
    for command in (run, summary):
        command.add_argument('--require-completion', action='store_true',
                             help='exit 1 unless every case reached an ending card')
    args = parser.parse_args()
    if args.mode == 'summary':
        return summarize(args.batch.resolve(), args.require_completion)
    if not 1 <= args.jobs <= 8:
        run.error('--jobs must be between 1 and 8')
    if not 300 <= args.ticks < 2**31 or not 0 < args.timeout < float('inf'):
        run.error('requires 300 <= ticks < 2^31 and a finite positive timeout')
    # Godot JSON numeric values round-trip exactly over this seed range.
    if any(not -2**53 < seed < 2**53 for seed in args.seeds):
        run.error('seeds must be strictly between -2^53 and 2^53')
    if len(set(args.profiles)) != len(args.profiles) or len(set(args.seeds)) != len(args.seeds):
        run.error('profiles and seeds must be unique')
    try:
        exe = godot_path(args.godot)
    except OSError as e:
        run.error(str(e))
    label = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:8]
    batch = BATCH / label
    batch.mkdir(parents=True)
    print(f'Batch: {batch}', flush=True)
    matrix = [(profile, seed) for profile in args.profiles for seed in args.seeds]
    jobs = min(args.jobs, len(matrix))
    fixture = 'full' if args.full else 'strategy-light'
    data = dict(schema=1, fixture=fixture, godot=str(exe), profiles=args.profiles, seeds=args.seeds, ticks=args.ticks,
                timeout_seconds=args.timeout, planned=len(matrix), jobs=jobs, cases=[])
    save(batch / 'batch.json', data)
    finished = {}
    start = time.perf_counter()
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        futures = {pool.submit(run_case, exe, batch / f'{profile}-{seed}', profile, seed,
                               args.ticks, args.timeout, fixture): i for i, (profile, seed) in enumerate(matrix)}
        for future in as_completed(futures):
            row = future.result()
            finished[futures[future]] = row
            data['cases'] = [finished[i] for i in sorted(finished)]
            save(batch / 'batch.json', data)
            print(f'{row["profile"]}/{row["seed"]}: {row["status"]} {row.get("outcome", "")} '
                  f'({row["wall_seconds"]:.2f} s)', flush=True)
    data['batch_wall_seconds'] = round(time.perf_counter() - start, 4)
    save(batch / 'batch.json', data)
    return summarize(batch, args.require_completion)


if __name__ == '__main__':
    raise SystemExit(main())
