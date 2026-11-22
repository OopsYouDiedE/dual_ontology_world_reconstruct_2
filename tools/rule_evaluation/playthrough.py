"""Render every packet of an admitted Oracle run in Godot, then encode MP4."""
import argparse
from dataclasses import asdict
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT), str(ROOT / "mcp" / "game")]
import environment
from core.rule_evaluation.gates import evaluate_seed
from core.rule_evaluation.world import World

FPS = 30


def input_digests():
    paths = [ROOT / 'project.godot', Path(__file__).resolve()]
    rules = ROOT / 'core' / 'rule_evaluation'
    paths += [rules / f'{name}.py' for name in ('bridge', 'dsl', 'gates', 'layout', 'oracle', 'physics', 'world')]
    if (rules / 'logic.py').exists():
        paths.append(rules / 'logic.py')
    paths += list((rules / 'rooms').glob('*.py'))
    paths.append(ROOT / 'scenes/blue_prince_lab/reference/plates.jpg')
    paths += [p for p in (ROOT / 'scenes' / 'rule_evaluation').glob('*') if p.suffix in {'.gd', '.tscn'}]
    return {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}


def schedule(seed, development=False, replay=None):
    final, gate = evaluate_seed(seed)
    if not (gate['zero_panic'] and (gate['sampling_pass'] or development) and gate['reproducible']):
        raise ValueError(f'Seed {seed} failed admission: {gate}')
    w = World(seed)
    if replay and (replay['schema'] != 1 or json.dumps(replay['config'], sort_keys=True) != json.dumps(asdict(w.config), sort_keys=True)):
        raise ValueError('Film replay must use the live scene default configuration')
    w.observe()
    rows = []
    for packet in (replay['packets'] if replay else final.decision_packets):
        level, tick, offset = w.index + 1, w.tick, len(w.events)
        before = [tuple(a.pos) for a in w.actors]
        old_objects = {e['entity_id']: e['primitive_geometry']['position'] for e in w.visual_fixtures()}
        was_open = w.exit_open()
        w.step(packet)
        events = w.events[offset:]
        moved = [i for i, a in enumerate(w.actors) if i < len(before) and before[i] != tuple(a.pos)]
        changes = [] if w.index + 1 != level else [e['entity_id'] for e in w.visual_fixtures()
                   if old_objects.get(e['entity_id']) != e['primitive_geometry']['position']]
        acts = [e for e in events if e['kind'] == 'INTERACT']
        said = [e for e in events if e['kind'] == 'PERSUADED']
        queried = [e for e in events if e['kind'] == 'QUERY']
        actor, target, proof = -1, '', ''
        caption, frames = '', 8
        if w.index + 1 != level:
            caption, frames = 'Expedition complete' if w.status == 'CAMP' else 'Chamber entered', 48
        elif acts:
            event = acts[-1]
            actor, target = event['actor'], event['action']['target_entity_id']
            op = event['action']['op_type'].replace('_', ' ')
            name = (w.entities[target].get('label') or target.replace('_', ' ')).split(' | ', 1)[0]
            caption, frames = f'{["Lead", "Hale", "Finch"][actor]}  /  {op.title()} · {name}', 34
            if w.exit_open() and not was_open:
                caption += '  /  Egress unlocked'
            if actor > 0 and changes:
                proof = f'{level:02d}-{target}-{op.replace(" ", "-")}'
            elif target == 'console' and event['action']['op_type'] in {'read', 'unload'}:
                proof = f'{level:02d}-{target}-{op}'
        elif said:
            event = said[-1]
            caption = f'{["Lead", "Hale", "Finch"][event["actor"]]} accepts witnessed evidence  /  {event["evidence"]}'
            frames = 30
        elif moved:
            actor = moved[0]
            caption = 'Repositioning  /  ' + ' + '.join(['Lead', 'Hale', 'Finch'][i] for i in moved)
        elif queried:
            caption, frames = 'Radio check  /  companion rulebook synchronized', 20
        rows.append(dict(action=packet, tick=w.tick, previous_tick=tick, level=level, caption=caption,
                         frames=frames, actor=actor, target=target, moved=moved, changes=changes, proof=proof))
    expected = replay['state_sha256'] if replay else gate['state_sha256']
    if (w.state_hash() != expected or w.status != 'CAMP'
            or (replay and w.checkpoints != replay['hashes'])):
        raise RuntimeError('Movie schedule diverged from the recorded successful run')
    return dict(seed=seed, gate=gate, fps=FPS, rows=rows, final_tick=w.tick,
                final_state_sha256=expected, policy=replay['policy'] if replay else 'oracle')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    selection = p.add_mutually_exclusive_group()
    selection.add_argument('--seed', type=int)
    selection.add_argument('--replay', type=Path, help='Verified batch replay under the live default configuration')
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--development', action='store_true', help='Allow unrelated hazard admission defects during renderer iteration')
    args = p.parse_args()
    out = args.out.resolve()
    out.relative_to(ROOT / '.runtime')
    out.mkdir(parents=True, exist_ok=False)
    digests = input_digests()
    data = json.loads(args.replay.read_text(encoding='utf-8')) if args.replay else None
    seed = data['seed'] if data else (args.seed if args.seed is not None else 1)
    source = schedule(seed, args.development, data)
    source['input_sha256'] = digests
    path = out / 'schedule.json'
    path.write_text(json.dumps(source, ensure_ascii=True, indent=2), encoding='utf-8')
    receipt, avi, log = [out / name for name in ('receipt.json', 'viewport.avi', 'godot.log')]
    exe = Path(environment.resolve_godot()).resolve()
    if os.name == 'nt' and exe.name.lower().endswith('_console.exe'):
        exe = exe.with_name(exe.name.replace('_console.exe', '.exe'))
    env = os.environ.copy()
    for key in ('APPDATA', 'LOCALAPPDATA') if os.name == 'nt' else ('XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME'):
        folder = out / 'profile' / key.lower()
        folder.mkdir(parents=True)
        env[key] = str(folder)
    dotnet = environment.resolve_dotnet(required=False)
    if dotnet:
        env['DOTNET_ROOT'] = str(Path(dotnet).parent)
        env['PATH'] = env['DOTNET_ROOT'] + os.pathsep + env.get('PATH', '')
    subprocess.run([str(exe), '--path', str(ROOT), '--rendering-method', 'forward_plus', '--language', 'en',
                    '--windowed', '--position', '-32000,-32000',
                    '--log-file', str(log), '--fixed-fps', str(FPS), '--write-movie', str(avi),
                    'res://scenes/rule_evaluation/Evaluation.tscn', '--', f'--python={sys.executable}',
                    f'--run-seed={seed}', f'--eval-film={path}', f'--eval-film-receipt={receipt}',
                    '--eval-film-mode=' + ('development' if args.development else 'admitted')],
                   env=env, cwd=ROOT, check=True, timeout=1000)
    if digests != input_digests():
        raise RuntimeError('Integrated inputs changed during capture; rerun against stable inputs')
    text = log.read_text(encoding='utf-8')
    result = json.loads(receipt.read_text(encoding='utf-8'))
    if ('Forward+' not in text or re.search(r'SCRIPT ERROR|Parse Error|ERROR:', text)
            or result['renderer'] != 'forward_plus' or result['status'] != 'CAMP'
            or result['state_sha256'] != source['final_state_sha256']
            or result['tick'] != source['final_tick'] or result['packets'] != len(source['rows'])):
        raise RuntimeError(f'Godot capture failed validation; see {log} and {receipt}')
    ffmpeg = shutil.which('ffmpeg')
    if not ffmpeg:
        raise FileNotFoundError('ffmpeg is required on PATH')
    mp4 = out / 'full-playthrough.mp4'
    subprocess.run([ffmpeg, '-v', 'error', '-i', str(avi), '-an', '-c:v', 'libx264', '-crf', '17',
                    '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(mp4)], check=True)
    for key, frame in result['stills'].items():
        subprocess.run([ffmpeg, '-v', 'error', '-ss', f'{(frame + .02) / FPS:.6f}', '-i', str(avi),
                        '-frames:v', '1', str(out / f'{key}.png')], check=True)
    print(mp4)


if __name__ == '__main__':
    main()
