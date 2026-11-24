"""Python API and CLI for the isolated headless Godot clutter fixture."""

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
RUNTIME = ROOT / '.runtime'
GODOT = RUNTIME / 'godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe'


def evaluate_rooms(requests, *, physics=True, controls=False, godot=GODOT):
    """Return clutter-report/v1; each request supplies room_id (str), seed (int)."""
    rooms = []
    for req in requests:
        room_id, seed = req['room_id'], req['seed']
        if not isinstance(room_id, str) or not room_id.strip():
            raise ValueError('room_id must be a nonempty string')
        if type(seed) is not int or not -(2**53 - 1) <= seed <= 2**53 - 1:
            raise ValueError('seed must be a JSON-safe signed integer')
        density, max_layers = _packing(req.get('density', 1.0), req.get('max_layers', 3))
        rooms.append({'room_id': room_id, 'seed': str(seed), 'density': density, 'max_layers': max_layers})
    report = _invoke({'rooms': rooms, 'physics': physics, 'controls': controls}, godot)
    if len(report['rooms']) != len(rooms):
        raise RuntimeError('Incomplete room report')
    return report


def _invoke(payload, godot):
    RUNTIME.mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='clutter-run-', dir=RUNTIME))
    for name in ('project.godot', 'fixture.gd', 'layout.gd'):
        shutil.copyfile(HERE / name, work / name)
    (work / 'requests.json').write_text(json.dumps(payload), encoding='utf-8')
    result = subprocess.run([str(Path(godot).resolve()), '--headless', '--path', str(work),
                             '--fixed-fps', '60', '--script', 'res://fixture.gd'],
                            capture_output=True, encoding='utf-8', errors='replace', timeout=180)
    (work / 'godot.log').write_text(result.stdout + result.stderr, encoding='utf-8')
    output = work / 'report.json'
    if not output.is_file() or result.returncode not in (0, 1) or 'ERROR:' in result.stderr:
        raise RuntimeError(f'Godot fixture failed ({result.returncode}); see {work / "godot.log"}')
    report = json.loads(output.read_text(encoding='utf-8'))
    if report['ok'] != (result.returncode == 0):
        raise RuntimeError(f'Incomplete or inconsistent report: {output}')
    return report


def _packing(density, max_layers):
    if type(density) not in (int, float) or not 0 <= density <= 1:
        raise ValueError('density must be a number from 0 to 1')
    if type(max_layers) is not int or not 1 <= max_layers <= 5:
        raise ValueError('max_layers must be an integer from 1 to 5')
    return density, max_layers


def generate_layout(room_id, seed, *, density=1.0, max_layers=3, godot=GODOT):
    """Return clutter-layout/v1 for a room, validated without walking the capsule."""
    row = evaluate_rooms([{'room_id': room_id, 'seed': seed, 'density': density,
                           'max_layers': max_layers}], physics=False, godot=godot)['rooms'][0]
    if row['status'] != 'layout_only':
        raise ValueError(f'Layout validation failed: {row["layout_errors"]}')
    return row['layout']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--batch', type=Path, help='JSON array of room_id/seed requests')
    mode.add_argument('--room-id')
    mode.add_argument('--sweep', action='store_true', help='20,000 geometric cases and stratified capsule samples')
    mode.add_argument('--self-test', action='store_true')
    parser.add_argument('--seed', type=int)
    parser.add_argument('--density', type=float)
    parser.add_argument('--max-layers', type=int)
    parser.add_argument('--layout-only', action='store_true')
    parser.add_argument('--godot', type=Path, default=GODOT)
    args = parser.parse_args()
    if any(v is not None for v in (args.seed, args.density, args.max_layers)) and args.room_id is None:
        parser.error('--seed, --density and --max-layers are only used with --room-id; for --batch put values in each row')
    if args.sweep:
        report = _invoke({'sweep': True, 'physics': not args.layout_only}, args.godot)
        print(json.dumps(report, indent=2))
        return 0 if report['ok'] else 1
    if args.self_test:
        if args.layout_only:
            parser.error('--self-test requires physics')
        rooms = [{'room_id': f'fixture-{seed}', 'seed': seed} for seed in [*range(32), -1, -(2**53-1), 2**53-1, 31]]
    elif args.batch:
        rooms = json.loads(args.batch.read_text(encoding='utf-8-sig'))
    else:
        if args.seed is None:
            parser.error('--room-id requires --seed')
        rooms = [{'room_id': args.room_id, 'seed': args.seed,
                  'density': 1.0 if args.density is None else args.density,
                  'max_layers': 3 if args.max_layers is None else args.max_layers}]
    report = evaluate_rooms(rooms, godot=args.godot, physics=not args.layout_only, controls=args.self_test)
    print(json.dumps(report, ensure_ascii=True, indent=2))
    return 0 if report['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
