"""Build cast contact sheets from the original GameMcp viewport PNGs."""
import argparse
import json
import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

MOTION = {
    'r05': ('R-05  Detective', 'suit', 'Formal suit'),
    'halvard': ('R-06  Halvard', 'workwear', 'Work overalls'),
    'jane': ('R-03  Jane Cox', 'shorts', 'T-shirt + shorts'),
    'qingyue': ('R-10  Qingyue', 'skirt', 'Blouse + skirt'),
}
STATIC = {'lucian': 'R-01  Lucian', 'ward': 'R-04  Ward',
          'shending': 'R-07  Shen Ding', 'caretaker': 'Caretaker'}


def font(size):
    path = Path(os.getenv('WINDIR', 'C:/Windows')) / 'Fonts/segoeui.ttf'
    return ImageFont.truetype(str(path), size) if path.exists() else ImageFont.load_default(size=size)


def panel(path, width):
    with Image.open(path) as original:
        w, h = original.size
        # Same normalized crop for all reviews: keep figure, remove debug UI.
        cropped = original.crop((round(w * .339), round(h * .087), round(w * .661), round(h * .963)))
        height = round(cropped.height / cropped.width * width)
        return cropped.convert('RGB').resize((width, height), Image.Resampling.LANCZOS)


def sheet(output, title, subtitle, groups):
    width, image_width, gap, pad = 1120, 264, 10, 17
    first_image = groups[0][1][0][0]
    height = panel(first_image, image_width).height
    row_height = height + 112
    canvas = Image.new('RGB', (width, 91 + row_height * len(groups)), '#282321')
    draw = ImageDraw.Draw(canvas)
    draw.text((pad, 10), title, font=font(31), fill='#ffe6cc')
    draw.text((pad, 52), subtitle, font=font(17), fill='#d1bdb2')
    for index, (label, items) in enumerate(groups):
        y = 85 + index * row_height
        draw.text((pad, y), label, font=font(21), fill='#facfad')
        for col, (image, caption, detail) in enumerate(items):
            x = pad + col * (image_width + gap)
            draw.text((x, y + 32), caption, font=font(18), fill='#fef0e3')
            canvas.paste(panel(image, image_width), (x, y + 60))
            draw.text((x, y + height + 64), detail, font=font(16), fill='#d5bfb2')
    canvas.save(output, quality=94, subsampling=0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('receipt', type=Path)
    args = parser.parse_args()
    data = json.loads(args.receipt.read_text(encoding='utf-8-sig'))
    assert data['status'] == 'MPFB_WARDROBE_VIEWPORT_PASS'
    shot = data['screenshots']
    out = args.receipt.parent
    sheet(out/'eight-cast-overview.jpg', 'ACADEMY  /  EIGHT CHARACTER MODELS',
          'Godot Forward+  /  Review framing normalized for static sources', [
              ('01  /  MPFB wardrobe + original embedded motion',
               [(shot[key][outfit]['front'], name, label) for key, (name, outfit, label) in MOTION.items()]),
              ('02  /  Independent original meshes + base garment (static)',
               [(shot[key]['base']['front'], name, 'Original static base') for key, name in STATIC.items()]),
          ])
    sheet(out/'eight-cast-motion.jpg', 'NATIVE MOTION  /  WARDROBE CHECK',
          'Each wardrobe variant plays its own model’s embedded MPFB pose check', [
              (f'{name}  /  {label}', [(shot[key][outfit][pose], title, detail) for pose, title, detail in (
                  ('front', 'Front', '0.00 s'), ('reach', 'Reach', '0.75 s'),
                  ('knee', 'Knee bend', '2.25 s'), ('back', 'Back', '0.00 s'),
              )]) for key, (name, outfit, label) in MOTION.items()
          ])
    sheet(out/'eight-cast-static.jpg', 'ORIGINAL STATIC MODELS  /  TURNAROUNDS',
          'Original base and underwear geometry  /  0 rig and animation tracks', [
              (title, [(shot[key]['base'][pose], name, '') for key, name in STATIC.items()])
              for pose, title in [('front', 'Front'), ('side', 'Side'), ('back', 'Back')]
          ])


if __name__ == '__main__':
    main()
