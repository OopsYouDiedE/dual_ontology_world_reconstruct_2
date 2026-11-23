"""Release gate for the playable expedition. Run from any working directory."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / '.runtime' / 'production-check'
GODOT = os.environ.get('DV_GODOT') or str(ROOT / '.runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe')


def check(name, args, *, marker=None, timeout=600):
    log = OUT / (name + '.log')
    print(f'{name}: {log}', flush=True)
    with log.open('wb') as output:
        result = subprocess.run(args, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT,
                                env={**os.environ, 'DV_GODOT': GODOT}, timeout=timeout)
    text = log.read_text('utf-8', errors='replace')
    errors = re.findall(r'(?m)^\s*(?:(?:SCRIPT |SHADER )?ERROR:|FAIL ).*', text)
    if result.returncode or errors or (marker and marker not in text):
        raise SystemExit(f'{name} failed ({result.returncode}): ' + ('; '.join(errors[:3]) or str(log)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--logic-only', action='store_true', help='skip the Forward+ gates')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    check('build', ['dotnet', 'build', 'DualOntologyWorldReconstruct2.csproj'])
    check('import', [GODOT, '--headless', '--editor', '--import', '--path', '.'])
    check('topology', ['dotnet', 'run', '--project', 'core/rogue_topology/tests/DuelView.RogueTopology.Tests.csproj'])
    for name, script, marker, tail in [
        ('look', 'expedition/hall04_test', 'PASS: Hall 04', []),
        ('route', 'expedition/route_test', 'PASS: 256 seeds', []),
        ('architecture', 'building_construction/tests/production_pipeline_test', 'PASS ', []),
        ('daylight', 'test/room_daylight', 'Room daylight contract: PASS', []),
        ('campaign', 'test/night_watch', 'Expedition integration passed:', ['--', '--no-rule-save']),
    ]:
        check(name, [GODOT, '--headless', '--path', '.', '-s', f'res://tools/{script}.gd', *tail], marker=marker)
    if not args.logic_only:
        check('cast', [GODOT, '--path', '.', '--rendering-method', 'forward_plus', '-s',
                       'res://tools/expedition/production_cast_test.gd'], marker='PASS: one 6.5-head')
        for lane, seed in [('east', '1'), ('west', '2')]:
            check(lane, [sys.executable, 'tools/expedition/viewport_run.py', '--lane', lane,
                         '--seed', seed, '--out', str(OUT / lane)], timeout=1200)
    print('Passed: ' + ('logic gates' if args.logic_only else 'logic and Forward+ gates'))


if __name__ == '__main__':
    main()
