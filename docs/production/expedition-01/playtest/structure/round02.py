"""Capture same-camera Forward+ lighting studies and place them side by side."""
import os
from pathlib import Path
import subprocess
import uuid

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[5]
SCRIPT = Path(__file__).with_suffix('.gd').relative_to(ROOT).as_posix()


def main():
    out = ROOT/'.runtime/design-review/round-02'
    out.mkdir(parents=True, exist_ok=True)
    scratch = ROOT/'.runtime'/f'structure-round02-{uuid.uuid4().hex[:8]}'
    user = scratch/'user'
    user.mkdir(parents=True)
    env = dict(os.environ, **dict.fromkeys(('APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME',
                                           'XDG_CONFIG_HOME', 'XDG_CACHE_HOME'), str(user)))
    default = ROOT/'.runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64.exe'
    exe = Path(os.getenv('DV_GODOT') or default)
    if exe.stem.lower().endswith('_console'):
        exe = exe.with_name(exe.stem[:-8] + exe.suffix)
    cmd = [str(exe), '--path', str(ROOT), '--resolution', '1280x720', '--rendering-method', 'forward_plus',
           '--fixed-fps', '60', '--log-file', str(scratch/'engine.log'), '-s', f'res://{SCRIPT}', '--', str(scratch)]
    print(scratch, flush=True)
    subprocess.run(cmd, cwd=ROOT, env=env, check=True, timeout=150)
    log = (scratch/'engine.log').read_text(encoding='utf-8', errors='replace')
    if 'ERROR:' in log or 'Forward+ /' not in log:
        raise RuntimeError(f'Check renderer and errors: {scratch}/engine.log')
    a, b = (Image.open(scratch/name).convert('RGB') for name in ('arcade-side.png', 'arcade-gate.png'))
    if a.size != b.size or a.size != (1280, 720) or a.tobytes() == b.tobytes():
        raise RuntimeError('Unexpected viewport images')
    width, height = a.size
    pair = Image.new('RGB', (width*2+4, height+66), '#1b1b1a')
    draw = ImageDraw.Draw(pair)
    font = ImageFont.truetype('segoeui.ttf', 26)
    for x, image, title in ((0, a, '01   SIDE LIGHT RHYTHM'), (width+4, b, '02   END GATE EMPHASIS')):
        pair.paste(image, (x, 66))
        draw.text((x+24, 14), title, font=font, fill='#f2e6d7')
    pair.save(out/'arcade.png')
    print(out/'arcade.png')


if __name__ == '__main__':
    main()
