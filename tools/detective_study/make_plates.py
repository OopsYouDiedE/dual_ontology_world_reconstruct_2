"""Make same-height design/Forward+ comparison plates from the study captures."""
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

RUN = Path('.runtime/detective-target-study')
OUT = Path('docs/design/media/detective-6p5')
FONT = ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf', 19)
HEADING = ImageFont.truetype('C:/Windows/Fonts/segoeuib.ttf', 27)


def load(name):
    with Image.open(RUN / name) as im:
        return im.convert('RGB')


def centered(img, draw, source, x, y, w, h):
    draw.rectangle((x + 2, y, x + w - 3, y + h - 1), fill=source.getpixel((0, 0)))
    img.paste(source, (x + (w - source.width) // 2, y))


def figure_crop(image):
    bg = Image.new('RGB', image.size, image.getpixel((0, 0)))
    diff = ImageChops.difference(bg, image).convert('L').point(lambda p: 255 if p > 17 else 0)
    x0, y0, x1, y1 = diff.getbbox()
    return image.crop((max(0, x0 - 8), max(0, y0 - 3), min(image.width, x1 + 8), min(image.height, y1 + 3)))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    target = load('04-turnaround-6p5.png')
    target.save(OUT / 'target-turnaround.jpg', quality=94, subsampling=0)
    load('05-motion-6p5.png').save(OUT / 'target-motion.jpg', quality=93, subsampling=0)
    canvas = Image.new('RGB', (1500, 604), '#e8e3dc')
    draw = ImageDraw.Draw(canvas)
    draw.text((17, 11), 'Detective  /  6.5-head turnaround', fill='#2d2927', font=HEADING)
    views = {'front': (100, 16, 520, 1004), 'profile': (651, 16, 886, 1004), 'back': (1010, 16, 1430, 1004)}
    for i, (view, box) in enumerate(views.items()):
        render = figure_crop(load(f'detective-6p5_{view}_c_soft_selective.png'))
        for j, (kind, image) in enumerate([('Target', target.crop(box)), ('Forward+', render)]):
            x = (i * 2 + j) * 250
            resized = image.resize((round(image.width * 522 / image.height), 522), Image.Resampling.LANCZOS)
            centered(canvas, draw, resized, x, 43, 250, 522)
            draw.text((x + 125, 583), f'{view.title()} · {kind}', fill='#322e2b', font=FONT, anchor='mm')
    canvas.save(OUT / 'turnaround-comparison.jpg', quality=93, subsampling=0)
    canvas.save(RUN / 'turnaround-comparison.png')

    canvas = Image.new('RGB', (1440, 533), '#e8e3dc')
    draw = ImageDraw.Draw(canvas)
    draw.text((15, 8), 'Forward+  /  Skeleton stress poses', fill='#2d2927', font=HEADING)
    for i, pose in enumerate(('turn', 'reach', 'step', 'run')):
        image = load(f'detective-6p5_pose_{pose}.png')
        image.thumbnail((355, 445), Image.Resampling.LANCZOS)
        x = 360 * i
        centered(canvas, draw, image, x, 43, 360, 445)
        draw.text((x + 180, 510), pose.title(), fill='#322e2b', font=FONT, anchor='mm')
    canvas.save(OUT / 'pose-check.jpg', quality=91, subsampling=0)


if __name__ == '__main__':
    main()
