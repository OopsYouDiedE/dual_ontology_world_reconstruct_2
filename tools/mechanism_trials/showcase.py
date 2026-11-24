"""Make a batch contact sheet from authentic Game MCP frame manifests, never judge art."""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
from gate import artifact_valid, evaluate
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CAPTURE = ROOT / '.runtime/academy-mechanisms'
DOCS = ROOT / 'docs/design/mechanism-trials'


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def font(size):
    for name in ('segoeui.ttf', 'DejaVuSans.ttf'):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def show(capture, entries, out):
    w, h, margin, gutter, caption, head = 580, 326, 26, 18, 67, 84
    codes = {'disqualified': ('RED-TEAM CLEAR', '#ef9a79'),
             'awaiting-window': ('UNDER RED-TEAM TEST', '#e0c694'),
             'evidence-incomplete': ('EVIDENCE INCOMPLETE', '#e0c694'),
             'eligible-for-astra': ('READY FOR READ-ONLY JUDGE', '#8fcfc2'),
             'accepted': ('ACCEPTED', '#8fcfc2'), 'vetoed': ('VETOED', '#ef9a79')}
    stamp = datetime.now(timezone.utc)
    canvas = Image.new('RGB', (2*w + 2*margin + gutter, head + margin + (h+caption+gutter)*((len(entries)+1)//2)), '#101b22')
    draw = ImageDraw.Draw(canvas)
    draw.text((margin, 16), 'THE SLEEPING ACADEMY / MECHANISM TRIALS', font=font(27), fill='#f3dec1')
    draw.text((margin, 52), 'Real Forward+ frames  /  native 1280 × 720  /  prototype status below each frame', font=font(17), fill='#9cc3bd')
    audit = []
    for i, (number, title, folder, filename, desc) in enumerate(entries):
        capture_dir = (capture / folder).resolve()
        manifest = read_json(capture_dir / 'manifest.json')
        frame = next((f for f in manifest['frames'] if f['file'] == filename), None)
        if not frame or frame['renderer'] != 'forward_plus' or frame['viewport'] != [1280, 720] or not artifact_valid(frame, capture_dir):
            raise ValueError(f'Invalid frame {number} {folder}/{filename}')
        ledger = DOCS / (number.lower() + '-ledger.json')
        result = evaluate(read_json(ledger), DOCS, stamp) if ledger.is_file() else {'status': 'prototype'}
        badge, color = codes.get(result['status'], ('PROTOTYPE', '#b0c6ca'))
        x = margin + (i % 2)*(w+gutter)
        y = head + (i // 2)*(h+caption+gutter)
        with Image.open(capture_dir / filename) as f:
            canvas.paste(f.convert('RGB').resize((w, h), Image.Resampling.LANCZOS), (x, y))
        draw.rectangle((x, y+h, x+w-1, y+h+caption), fill='#192832')
        draw.text((x+11, y+h+7), f'{number}  {title}', font=font(21), fill='#f3dec1')
        tag = font(13)
        tag_width = draw.textbbox((0, 0), badge, font=tag)[2]
        draw.text((x+w-tag_width-11, y+h+13), badge, font=tag, fill=color)
        draw.text((x+11, y+h+36), desc, font=font(15), fill='#aacbc2')
        audit.append({'candidate': number, 'state': result, 'capture': folder, 'frame': filename,
                      'frame_sha256': frame['sha256']})
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out, quality=90, subsampling=0)
    out.with_suffix('.json').write_text(json.dumps({'generated_at': stamp.isoformat(), 'tile_manifest': audit,
                                                   'jpg_sha256': hashlib.sha256(out.read_bytes()).hexdigest()}, indent=2), encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capture', type=Path, default=DEFAULT_CAPTURE)
    parser.add_argument('--out', type=Path, default=DEFAULT_CAPTURE / 'batch-a01-a07.jpg')
    parser.add_argument('--entries', type=Path, default=DOCS / 'showcase.json')
    args = parser.parse_args()
    show(args.capture.resolve(), read_json(args.entries), args.out.resolve())
