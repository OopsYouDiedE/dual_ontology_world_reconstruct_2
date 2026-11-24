"""Generate and draw the acceptance-tested workshop comparison (requires Pillow)."""
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from run import REVIEW, evaluate_rooms

ROOM = 'prototype/workshop-dispatch'
SEED = 31
S = 2
INK = '#e5ecec'
MUTED = '#a8b9bd'
AQUA = '#72e4db'
GOLD = '#ffc472'
COLORS = {
    'pedestal': '#397d81', 'worktop': '#d5a16a', 'tool_cabinet': '#549499',
    'stool_base': '#54898b', 'stool_seat': '#d5a16a', 'drawers': '#ad7154',
    'countertop': '#e8b87c', 'stock_cabinet': '#b37e5a', 'tray': '#e6b95d',
    'parcel': '#d4a368', 'crate': '#927859',
}


def tint(color, factor):
    return tuple(min(255, round(int(color[i:i+2], 16)*factor)) for i in (1, 3, 5))


def render(before, after, destination, *, round_two=False):
    image = Image.new('RGB', (1600*S, 960*S), '#111c23')
    draw = ImageDraw.Draw(image)
    font_dir = Path('C:/Windows/Fonts')

    def label(x, y, text, size=20, color=INK, bold=False):
        name = 'segoeuib.ttf' if bold else 'segoeui.ttf'
        font = ImageFont.truetype(str(font_dir / name), size*S) if (font_dir / name).is_file() else ImageFont.load_default(size*S)
        draw.text((x*S, y*S), text, fill=color, font=font)

    def points(coords):
        return [(round(x*S), round(y*S)) for x, y in coords]

    def polygon(coords, fill, outline=None):
        draw.polygon(points(coords), fill=fill, outline=outline, width=S)

    def line(coords, fill, width=2):
        draw.line(points(coords), fill=fill, width=width*S, joint='curve')

    def rectangle(x, y, w, h, color, outline=None):
        draw.rectangle(points([(x, y), (x+w, y+h)]), fill=color, outline=outline, width=S)

    def color_for(item):
        return COLORS.get(item.get('kind'), ('#81796f', '#9b8b78', '#b0997d', '#b9a284', '#c6ac87')[item['layer']-1])

    def panel(row, left, furnished):
        layout = row['layout']
        stations = layout.get('stations', [])
        if round_two:
            title = 'B  /  SHARED APRON' if furnished else 'A  /  OPPOSING BAYS'
            subtitle = 'Same wall, one entry into a shared work apron' if furnished else 'Opposite walls, two independent approaches'
        else:
            title = '02  /  FURNISHED' if furnished else '01  /  STRESS'
            subtitle = 'Wall stations + direct through aisle' if furnished else 'Jittered stacks + reserved dogleg'
        label(left+28, 164, title, 26, INK, True)
        label(left+28, 205, subtitle, 19, MUTED)
        rectangle(left+1, 247, 746, 1, '#394d56')

        def iso(x, y, z):
            return left+373+32*(x-z), 443+14*(x+z)-56*y

        def plan(x, y, z):
            return left+255+35*x, 730+24*z

        def shape(project, coords, fill, border=None):
            polygon([project(*p) for p in coords], fill, border)

        def route(project, path, color, width):
            line([project(*p) for p in path], color, width)
            for x, y, z in [path[0], path[-1]]:
                px, py = project(x, y, z)
                draw.ellipse(points([(px-4, py-4), (px+4, py+4)]), fill=color)

        def furniture(item):
            x, y, z = item['center']
            w, h, d = item['size']
            xl, xh, yl, yh, zl, zh = x-w/2, x+w/2, y-h/2, y+h/2, z-d/2, z+d/2
            a, b, c, e = (xl,yh,zl), (xh,yh,zl), (xh,yh,zh), (xl,yh,zh)
            color = color_for(item)
            shape(iso, [e,c,(xh,yl,zh),(xl,yl,zh)], tint(color,.79), '#233035')
            shape(iso, [b,c,(xh,yl,zh),(xh,yl,zl)], tint(color,.57), '#233035')
            shape(iso, [a,b,c,e], tint(color,1.13), '#233035')
            kind = item.get('kind')
            # Drawer/door markings are descriptive graphics on the exported box faces.
            if kind in ('tool_cabinet', 'stock_cabinet', 'drawers', 'pedestal') and z < 0:
                levels = 3 if kind == 'drawers' else 2
                for n in range(levels):
                    bottom = yl+(n+.12)*h/levels
                    top = yl+(n+.90)*h/levels
                    shape(iso, [(xl+.05,bottom,zh),(xh-.05,bottom,zh),(xh-.05,top,zh),(xl+.05,top,zh)], tint(color,.86), tint(color,.58))
                    line([iso(x-.09,top-.06,zh),iso(x+.09,top-.06,zh)], '#ded1ae', 1)
            if kind in ('parcel', 'crate'):
                line([iso(x,yh,zl),iso(x,yh,zh)], tint(color,.66), 2)

        for project in (iso, plan):
            shape(project, [(-5,0,-4),(5,0,-4),(5,0,4),(-5,0,4)], '#2c434c', '#80979d')
            for x in range(-4, 5):
                line([project(x,0,-4), project(x,0,4)], '#354f58', 1)
            for z in range(-3, 4):
                line([project(-5,0,z),project(5,0,z)], '#354f58', 1)
            for wall in (-5, 5):
                for start, stop in ((-4,-.7), (.7,4)):
                    line([project(wall,0,start),project(wall,0,stop)], '#a7b5b4', 3)
                shape(project, [(wall-.19,0,-.7),(wall+.19,0,-.7),(wall+.19,0,.7),(wall-.19,0,.7)], '#72a9a2')
            line([project(-5,0,-4),project(5,0,-4)], '#a7b5b4', 3)
            line([project(-5,0,4),project(5,0,4)], '#a7b5b4', 3)
            for station in stations:
                route(project, station['route'], GOLD, 3)
            route(project, layout['route'], AQUA, 4)

        by_id = {item['id']: item for item in layout['items']}

        def depth(item):
            base = item
            while base['support']:
                base = by_id[base['support']]
            return (base['center'][0]+base['center'][2], base['id'], item['layer'])

        for item in sorted(layout['items'], key=depth):
            furniture(item)
        for item in sorted(layout['items'], key=lambda it: it['layer']):
            x, _, z = item['center']
            w, _, d = item['size']
            x0, y0 = plan(x-w/2, 0, z-d/2)
            rectangle(x0, y0, w*35, d*24, color_for(item), '#29363b')
        label(left+28, 598, 'TOP VIEW', 15, MUTED, True)
        label(left+28, 829, 'W  /  ENTRY', 14, MUTED)
        label(left+370, 829, 'E  /  EXIT', 14, MUTED)
        label(left+491, 650, 'CAPSULE CHECK', 15, MUTED, True)
        count = len(row['traversals']) + len(row.get('station_traversals', [])) + len(row.get('handoff_traversals', []))
        label(left+491, 678, f'{count}/{count} traversals passed', 20, AQUA, True)
        if round_two:
            from math import dist
            path = row['handoff_route']
            distance = sum(dist(a, b) for a, b in zip(path, path[1:]))
            label(left+491, 710, f'{distance:.2f} m station-to-station', 17, INK)
        else:
            label(left+491, 710, f"{len(layout['items'])} collider parts", 17, INK)
        if stations:
            for i, station in enumerate(stations, 1):
                px, py = plan(*station['route'][-1])
                draw.ellipse(points([(px-10,py-10),(px+10,py+10)]), fill=GOLD)
                label(px-4,py-9,str(i),13,'#19292a',True)
            label(left+491, 766, '1   Workshop bench', 17, GOLD)
            label(left+491, 794, '2   Dispatch counter', 17, GOLD)
        else:
            label(left+491, 766, 'Loose stacks fill', 17, MUTED)
            label(left+491, 792, 'eligible floor sites.', 17, MUTED)

    label(58, 37, 'WORKSHOP / DISPATCH' + ('  /  ROUND 02' if round_two else ''), 44, INK, True)
    seed = before['layout']['seed']
    subtitle = f'Same 10 x 8 m room  /  1.16 m reserved main aisle  /  1.40 m doors  /  Seed {seed}' if round_two else f'Same 10 x 8 m prototype  /  Same opposing doors  /  Seed {seed}'
    label(60, 99, subtitle, 22, MUTED)
    line([(52,138),(1548,138)], '#415961', 1)
    line([(800,161),(800,853)], '#415961', 1)
    panel(before, 51, False)
    panel(after, 802, True)
    line([(52,873),(1548,873)], '#415961', 1)
    line([(61,910),(92,910)], AQUA, 4)
    label(104, 897, 'Through route', 17, INK)
    line([(266,910),(297,910)], GOLD, 3)
    label(309, 897, 'Station approach', 17, INK)
    label(938, 897, 'Cutaway diagram from Godot-tested collider export', 17, MUTED)
    image.resize((1600,960), Image.Resampling.LANCZOS).save(destination)


def review():
    key = {'room_id': ROOM, 'seed': SEED}
    requests = [key, dict(key, mode='furnished')]
    requests += [dict(key, seed=seed, mode='furnished', density=density, max_layers=cap)
                 for seed in range(16) for density, cap in [(0, 1), (0.45, 2), (1, 5)]]
    result = evaluate_rooms(requests, furnished_control=True)
    REVIEW.mkdir(parents=True, exist_ok=True)
    (REVIEW / 'acceptance.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    if not result['ok']:
        raise SystemExit(f'Acceptance failed: {REVIEW / "acceptance.json"}')
    render(*result['rooms'][:2], REVIEW / 'before-after.png')
    print(REVIEW / 'before-after.png')


if __name__ == '__main__':
    review()
