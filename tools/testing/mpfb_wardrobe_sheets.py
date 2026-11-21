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
NEW = {
    'lucian': ('R-01  Lucian', 'shirt', 'Striped shirt + jeans'),
    'ward': ('R-04  Ward', 'suit', 'Formal suit'),
    'shending': ('R-07  Shen Ding', 'workwear', 'Work overalls'),
    'caretaker': ('Caretaker', 'suit', 'Formal suit'),
}


def font(size):
    path = Path(os.getenv('WINDIR', 'C:/Windows')) / 'Fonts/segoeui.ttf'
    return ImageFont.truetype(str(path), size) if path.exists() else ImageFont.load_default(size=size)


def panel(path, width, crop_width=.322, center=.5):
    with Image.open(path) as original:
        w, h = original.size
        # Same normalized crop for all reviews: keep figure, remove debug UI.
        half_width = crop_width / 2
        cropped = original.crop((round(w * (center - half_width)), round(h * .087),
                                 round(w * (center + half_width)), round(h * .963)))
        height = round(cropped.height / cropped.width * width)
        return cropped.convert('RGB').resize((width, height), Image.Resampling.LANCZOS)


def sheet(output, title, subtitle, groups, *, crop_width=.322, profile_center=.5):
    width, image_width, gap, pad = 1120, 264, 10, 17
    first_image = groups[0][1][0][0]
    height = panel(first_image, image_width, crop_width).height
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
            center = profile_center if label.endswith('/  Profile') else .5
            canvas.paste(panel(image, image_width, crop_width, center), (x, y + 60))
            draw.text((x, y + height + 64), detail, font=font(16), fill='#d5bfb2')
    canvas.save(output, quality=94, subsampling=0)


def detail_sheets(shot, out):
    for pose, title in [('front', 'FRONT'), ('side', 'SIDE'), ('back', 'BACK'), ('portrait', 'FACE')]:
        sheet(out/f'eight-detail-{pose}.jpg', f'ACADEMY  /  REFINED MPFB CAST  /  {title}',
              'Godot Forward+  /  Same portrait zoom and light' if pose == 'portrait' else
              'Godot Forward+  /  Shared camera scale  /  Basic review clothes', [
                  (label, [(shot[key]['detail'][pose], name, '') for key, (name, _, _) in group.items()])
                  for label, group in [('01  /  First group', MOTION), ('02  /  Second group', NEW)]
              ])
    for suffix, group in [('first', MOTION), ('second', NEW)]:
        sheet(out/f'body-before-after-{suffix}.jpg', 'ACADEMY  /  MPFB BODY TUNING',
              'Same camera, light and neutral pose  /  Basic review clothes', [
                  (label, [(shot[key][version]['front'], name, '') for key, (name, _, _) in group.items()])
                  for label, version in [('A  /  Previous recipe', 'base'), ('B  /  Refined recipe', 'detail')]
              ])
    sheet(out/'wardrobe-repaint.jpg', 'ACADEMY  /  TWO UV REPAINTS',
          'Same pattern, UV, rig and native motion  /  Only the base-color texture changes', [
              (title, [(shot[who][version][pose], caption, detail) for version, pose, caption, detail in [
                  ('paint_stock', 'front', 'Stock colors', 'Same refined body'),
                  ('paint', 'front', 'Academy repaint', 'Same camera'),
                  ('paint', 'back', 'Back view', 'Repainted seams and hems'),
                  ('paint', 'reach' if who == 'r05' else 'knee', 'Native pose check', 'Repaint on the original rig'),
              ]]) for who, title in [('r05', 'R-05  /  Rust canvas and slate denim'),
                                     ('qingyue', 'R-10  /  Ivory stripe and ink-blue skirt')]
          ])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('receipt', type=Path)
    args = parser.parse_args()
    data = json.loads(args.receipt.read_text(encoding='utf-8-sig'))
    if data['status'] == 'MPFB_DETAIL_VIEWPORT_PASS':
        detail_sheets(data['screenshots'], args.receipt.parent)
        return
    assert data['status'] == 'MPFB_WARDROBE_VIEWPORT_PASS'
    shot = data['screenshots']
    out = args.receipt.parent
    sheet(out/'eight-mpfb-overview.jpg', 'ACADEMY  /  EIGHT MPFB CHARACTER MODELS',
          'Godot Forward+  /  Each model has its own rig and embedded pose check', [
              (title, [(shot[key][outfit]['front'], name, label)
                       for key, (name, outfit, label) in group.items()])
              for title, group in [('01  /  Existing MPFB cast', MOTION), ('02  /  New MPFB cast', NEW)]
          ])
    sheet(out/'four-new-mpfb-motion.jpg', 'NEW MPFB MODELS  /  NATIVE MOTION',
          'Stock wardrobe fitted to each character’s own MPFB recipe', [
              (f'{name}  /  {label}', [(shot[key][outfit][pose], title, detail) for pose, title, detail in (
                  ('front', 'Front', '0.00 s'), ('reach', 'Reach', '0.75 s'),
                  ('knee', 'Knee bend', '2.25 s'), ('back', 'Back', '0.00 s'),
              )]) for key, (name, outfit, label) in NEW.items()
          ])
    sheet(out/'four-new-mpfb-body.jpg', 'NEW MPFB MODELS  /  BASE TURNAROUNDS',
          'Review clothes, neutral pose and common camera scale', [
              (title, [(shot[key]['base'][pose], name, '') for key, (name, _, _) in NEW.items()])
              for pose, title in [('front', 'Front'), ('side', 'Side'), ('back', 'Back')]
          ])

    if 'faces' in data:
        portraits = data['faces']
        groups = []
        if all('before' in variation for variation in portraits.values()):
            groups.append(('Before  /  Face', [(portraits[k]['before']['portrait'], name, 'Previous recipe')
                                                for k, (name, _, _) in NEW.items()]))
        for title, angle in [('After  /  Face', 'portrait'), ('After  /  Profile', 'profile')]:
            groups.append((title, [(portraits[k]['base'][angle], name, 'Refined MPFB face')
                                   for k, (name, _, _) in NEW.items()]))
        sheet(out/'four-face-detail.jpg', 'MPFB  /  FACE SHAPE & PROFILE',
              'Equal orthographic zoom and light in Godot Forward+', groups,
              crop_width=.39, profile_center=.57)
        sheet(out/'four-silhouette-fit.jpg', 'MPFB  /  SILHOUETTE UNDER CLOTHES',
              'Same pose, camera and light  /  Same plain top and trousers in the fitted test', [
                  ('A  /  Painted review clothes (body contour)',
                   [(shot[k]['base']['front'], name, 'Body reference') for k, (name, _, _) in NEW.items()]),
                  ('B  /  Stock outfit',
                   [(shot[k][outfit]['front'], name, label) for k, (name, outfit, label) in NEW.items()]),
                  ('C  /  Plain fitted T-shirt and trousers',
                   [(shot[k]['fitted']['front'], name, 'Fitted waist and short sleeves')
                    for k, (name, _, _) in NEW.items()]),
                  ('D  /  Same fitted clothes, side view',
                   [(shot[k]['fitted']['side'], name, 'Chest and waist depth')
                    for k, (name, _, _) in NEW.items()]),
              ])
        sheet(out/'four-fitted-motion.jpg', 'FITTED T-SHIRT  /  MOTION CHECK',
              'Godot Forward+  /  Original embedded motion', [
                  (title, [(shot[k]['fitted'][pose], name, detail) for k, (name, _, _) in NEW.items()])
                  for title, pose, detail in [('Reach', 'reach', '0.75 s'), ('Knee bend', 'knee', '2.25 s')]
              ])


if __name__ == '__main__':
    main()
