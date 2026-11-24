"""Run paired real-expedition Human Sol trials without editing production files."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import subprocess
import time
import uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
TOOLS = ROOT / 'tools/expedition'
BATCH = runpy.run_path(str(TOOLS / 'human_batch.py'))


def stage(directory):
    source = (TOOLS / 'human_sol.gd').read_text(encoding='utf-8')
    source = re.sub(r'preload\("([\w.]+\.gd)"\)', r'preload("res://tools/expedition/\1")', source)
    portal = directory / 'portal.gd'
    shutil.copyfile(HERE / 'portal.gd', portal)
    relative = portal.relative_to(ROOT).as_posix()
    for needle, replacement in (
        ('var light:=', f'var portal:=preload("res://{relative}")\n\tvar layout:="A" if "--layout=A" in OS.get_cmdline_user_args() else "B"\n\tportal.install(level,layout)\n\tvar structure_probe:={{}}\n\tvar light:='),
        ('\t\ttick=i\n', '\t\ttick=i\n\t\tif i==8:structure_probe=portal.probe(level,vision)\n'),
        ('\taudit_log.finish(report)', '\treport["layout"]=layout\n\treport["structure_probe"]=structure_probe\n\taudit_log.finish(report)'),
    ):
        if source.count(needle) != 1:
            raise ValueError(f'Human Sol hook changed: {needle!r}')
        source = source.replace(needle, replacement)
    harness = directory / 'human_structure.gd'
    harness.write_text(source, encoding='utf-8')
    return 'res://' + harness.relative_to(ROOT).as_posix()


def case(directory, script, exe, layout, profile, seed, ticks, timeout):
    user = directory / 'user'
    user.mkdir(parents=True)
    cmd = [str(exe), '--headless', '--fixed-fps', '60', '--path', str(ROOT),
           '--log-file', str(directory / 'engine.log'), '-s', script, '--',
           '--strategy-light', '--rogue-mcp-dir=', f'--layout={layout}', f'--profile={profile}',
           f'--run-seed={seed}', f'--ticks={ticks}', f'--output={directory / "report.json"}',
           f'--batch-user-root={user.as_posix()}']
    env = dict(os.environ, **dict.fromkeys(('APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME',
                                           'XDG_CONFIG_HOME', 'XDG_CACHE_HOME'), str(user)))
    row = dict(layout=layout, profile=profile, seed=seed, command=cmd)
    start = time.monotonic()
    try:
        with (directory / 'console.log').open('wb') as log:
            row['returncode'] = subprocess.run(cmd, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT,
                                               timeout=timeout, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0)).returncode
        for log in directory.glob('*.log'):
            if BATCH['ERROR'].search(log.read_text(encoding='utf-8', errors='replace')):
                raise ValueError(f'engine errors in {log.name}')
        report = json.loads((directory / 'report.json').read_text(encoding='utf-8'))
        row.update(BATCH['inspect_report'](report, profile, seed, ticks, user, row['returncode'], 'strategy-light'))
        expected = {'center_clear': layout == 'A', 'opening_clear': True, 'sensor_hits_portal_plane': layout == 'B'}
        if report['layout'] != layout or report['structure_probe'] != expected:
            raise ValueError(f'unexpected geometry probe: {report["structure_probe"]}')
        path = report['path_samples']
        hits = [point for point in path if point[1] >= 4.8]
        row.update(status='ok', geometry=expected, first_beyond=hits[0] if hits else None,
                   max_x_m=max(point[1] for point in path), feet=report['feet'],
                   dwell_ticks=row['longest_dwell'][1] - row['longest_dwell'][0])
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as exc:
        row.update(status='infra_error', error=str(exc))
    row['wall_seconds'] = round(time.monotonic() - start, 2)
    BATCH['save'](directory / 'case.json', row)
    print(profile, seed, layout, row.get('error', row.get('outcome')), flush=True)
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seeds', nargs='+', type=int, default=[31, 113, 271])
    parser.add_argument('--ticks', type=int, default=7200)
    parser.add_argument('--timeout', type=float, default=180)
    parser.add_argument('--godot', default=os.getenv('DV_GODOT'))
    args = parser.parse_args()
    if len(set(args.seeds)) != len(args.seeds) or len(args.seeds) < 2 or args.ticks < 300 or args.timeout <= 0:
        parser.error('use two or more distinct seeds, at least 300 ticks, and a positive timeout')
    exe = BATCH['godot_path'](args.godot)
    directory = ROOT / '.runtime' / f'structure-{uuid.uuid4().hex[:10]}'
    directory.mkdir()
    script = stage(directory)
    files = [*TOOLS.glob('*.gd'), *(ROOT / 'scenes/expedition_01').glob('*.gd'),
             ROOT / 'project.godot', ROOT / 'scenes/expedition_01/Expedition.tscn', HERE / 'portal.gd', Path(__file__)]
    def hashes():
        return {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}
    summary = dict(ticks=args.ticks, profiles=BATCH['PROFILES'], seeds=args.seeds, inputs_sha256=hashes(), pairs=[])
    print(directory, flush=True)
    for profile in BATCH['PROFILES']:
        for seed in args.seeds:
            order = 'AB' if len(summary['pairs']) % 2 == 0 else 'BA'
            arms = {arm: case(directory / f'{profile}-{seed}-{arm}', script, exe, arm, profile, seed,
                              args.ticks, args.timeout) for arm in order}
            a, b = arms['A'], arms['B']
            pair = dict(profile=profile, seed=seed, order=order, arms=arms, status='invalid')
            if a['status'] == b['status'] == 'ok' and a['policy_parameters'] == b['policy_parameters']:
                pair.update(status='ok', delta_b_minus_a={key: round(b[key] - a[key], 4) for key in
                            ('distance_m', 'max_x_m', 'decisions', 'dwell_ticks')},
                            first_beyond_delta_ticks=(b['first_beyond'][0] - a['first_beyond'][0]
                                                     if a['first_beyond'] and b['first_beyond'] else None))
            summary['pairs'].append(pair)
            BATCH['save'](directory / 'pairs.json', summary)
    summary['inputs_unchanged'] = summary['inputs_sha256'] == hashes()
    BATCH['save'](directory / 'pairs.json', summary)
    return int(not summary['inputs_unchanged'] or any(p['status'] != 'ok' for p in summary['pairs']))


if __name__ == '__main__':
    raise SystemExit(main())
