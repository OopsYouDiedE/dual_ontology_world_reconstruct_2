"""Paint two stock MPFB UV atlases and swap only their GLB albedo payloads.

Run with the workspace Python (Pillow). The PNGs are also standalone paint sources
for Blender Texture Paint; the original CC0 atlas and its UVs are unchanged.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import struct

from PIL import Image, ImageDraw, ImageFilter, ImageOps


def palette(luma, colors, points):
    return ImageOps.colorize(luma, colors[0], colors[2], colors[1],
                             blackpoint=points[0], midpoint=points[1], whitepoint=points[2])


def atlas_mask(size, outlines):
    mask = Image.new('L', size)
    draw = ImageDraw.Draw(mask)
    for poly in outlines:
        draw.polygon([(x * size[0] / 680, y * size[1] / 680) for x, y in poly], fill=255)
    return mask


def box(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def jacket(source):
    luma = ImageOps.grayscale(source)
    broad = luma.filter(ImageFilter.GaussianBlur(4))
    coat = palette(broad, ('#55352a', '#a75f45', '#c48760'), (18, 59, 99))
    trouser = palette(broad, ('#272d3d', '#4d5c6f', '#6c7885'), (31, 98, 204))
    lining = palette(luma.filter(ImageFilter.GaussianBlur(1.2)),
                     ('#a79c83', '#d0c19d', '#766956'), (7, 30, 99))
    coat.paste(trouser, mask=atlas_mask(source.size, [box(0, 378, 407, 679)]))
    coat.paste(lining, mask=atlas_mask(source.size, [
        box(0, 74, 108, 114), box(0, 120, 147, 154),
        [(389, 0), (448, 0), (474, 189), (413, 213), (388, 152)],
        [(594, 172), (658, 172), (641, 381), (565, 381), (567, 337)],
        [(407, 402), (465, 373), (504, 375), (546, 394), (541, 432), (406, 438)],
    ]))
    # A short double seam across the upper back panel of this specific atlas.
    draw = ImageDraw.Draw(coat)
    def seam(points, color):
        w, h = source.size
        draw.line([(x * w / 680, y * h / 680) for x, y in points], fill=color,
                  width=max(1, round(w / 600)), joint='curve')
    seam([(35, 224), (58, 227), (82, 228), (105, 226), (128, 222)], '#664031')
    seam([(35, 227), (58, 230), (82, 231), (105, 229), (128, 225)], '#bf8763')
    return coat


def skirt(source):
    luma = ImageOps.grayscale(source).filter(ImageFilter.GaussianBlur(1.2))
    silk = palette(luma, ('#b4aa89', '#e6d6b0', '#5b7376'), (5, 32, 105))
    wool = palette(luma.filter(ImageFilter.GaussianBlur(3)),
                   ('#263541', '#405768', '#627b83'), (36, 66, 112))
    # Curved skirt panel: the hem is bottommost near the middle of the UV island.
    border = [(x, 340 + 28 * (1 - ((x - 275) / 265) ** 2)) for x in range(10, 542)]
    hem = ImageDraw.Draw(wool)
    for offset, color, width in [(9, '#858e7e', 5), (16, '#af9c73', 2)]:
        hem.line([(x * source.width / 680, (y - offset) * source.height / 680) for x, y in border],
                 fill=color, width=max(1, round(width * source.height / 680)))
    silk.paste(wool, mask=atlas_mask(source.size, [[
        (0, 0), (527, 0), (525, 130), (534, 214), (540, 308), (539, 373),
        (78, 374), (41, 338), (0, 341),
    ]]))
    return silk


PILOTS = {'r05_jacket': ('male_casualsuit05', jacket), 'qingyue_skirt': ('female_elegantsuit01', skirt)}


def read_glb(path):
    raw = path.read_bytes()
    assert struct.unpack_from('<4sII', raw) == (b'glTF', 2, len(raw)), path
    n, kind = struct.unpack_from('<I4s', raw, 12)
    size, bin_kind = struct.unpack_from('<I4s', raw, 20 + n)
    assert kind == b'JSON' and bin_kind == b'BIN\x00' and len(raw) == 28 + n + size, path
    return json.loads(raw[20:20+n]), raw[28+n:]


def albedo_view(doc, slug):
    mesh, = (m for m in doc['meshes'] if m['name'] == 'Wardrobe_Outfit')
    material_id, = {p['material'] for p in mesh['primitives']}
    pbr = doc['materials'][material_id]['pbrMetallicRoughness']
    image = doc['images'][doc['textures'][pbr['baseColorTexture']['index']]['source']]
    assert image['mimeType'] == 'image/png' and image['name'] == slug + '_diffuse', image
    index = image['bufferView']
    assert sum(img.get('bufferView') == index for img in doc['images']) == 1
    for acc in doc['accessors']:
        assert acc.get('bufferView') != index
        for part in acc.get('sparse', {}).values():
            assert not isinstance(part, dict) or part.get('bufferView') != index
    return index


def view_payload(blob, view):
    start = view.get('byteOffset', 0)
    return blob[start:start + view['byteLength']]


def write_paint_variant(stock, dest, png, changed_view):
    doc, blob = read_glb(stock)
    after = bytearray()
    assert len(doc['buffers']) == 1
    for i, view in enumerate(doc['bufferViews']):
        assert view['buffer'] == 0
        payload = png if i == changed_view else view_payload(blob, view)
        view['byteOffset'], view['byteLength'] = len(after), len(payload)
        after.extend(payload)
        after.extend(b'\x00' * (-len(after) % 4))
    doc['buffers'][0]['byteLength'] = len(after)
    chunk = json.dumps(doc, separators=(',', ':'), ensure_ascii=False).encode('utf-8')
    chunk += b' ' * (-len(chunk) % 4)
    dest.write_bytes(struct.pack('<4sIII4s', b'glTF', 2, 28 + len(chunk) + len(after), len(chunk), b'JSON')
                     + chunk + struct.pack('<I4s', len(after), b'BIN\x00') + after)
    before_doc, before_bin = read_glb(stock)
    after_doc, after_bin = read_glb(dest)
    assert {k: v for k, v in before_doc.items() if k not in ('buffers', 'bufferViews')} == {
        k: v for k, v in after_doc.items() if k not in ('buffers', 'bufferViews')}
    changed = [i for i, (a, b) in enumerate(zip(before_doc['bufferViews'], after_doc['bufferViews'], strict=True))
               if view_payload(before_bin, a) != view_payload(after_bin, b)]
    assert changed == [changed_view], changed
    untouched_hash = hashlib.sha256()
    for i, view in enumerate(before_doc['bufferViews']):
        if i != changed_view:
            untouched_hash.update(view_payload(before_bin, view))
    return {'changed_buffer_view': changed_view, 'unchanged_buffer_views': len(before_doc['bufferViews']) - 1,
            'unchanged_payload_sha256': untouched_hash.hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path, help='Detail build directory containing both stock GLBs')
    args = parser.parse_args()
    root = args.output
    receipt = {}
    for stem, (slug, paint) in PILOTS.items():
        stock = root/f'{stem}.glb'
        doc, blob = read_glb(stock)
        index = albedo_view(doc, slug)
        with Image.open(io.BytesIO(view_payload(blob, doc['bufferViews'][index]))) as src:
            assert src.size == (2048, 2048), src.size  # the painted UV layout is authored for these atlases
            color = paint(src).convert('RGBA')
            color.putalpha(src.convert('RGBA').getchannel('A'))
            # Retain the atlas credit marks outside the UV islands.
            mark = (1700, 0, 2048, 67) if stem == 'r05_jacket' else (1348, 1984, 1695, 2048)
            color.paste(src.crop(mark), mark[:2])
            texture = root/f'{stem}_paint.png'
            color.save(texture, optimize=True)
        receipt[stem] = write_paint_variant(stock, root/f'{stem}_paint.glb', texture.read_bytes(), index)
    (root/'repaint-receipt.json').write_text(json.dumps(receipt, indent=2)+'\n', encoding='utf-8')
    print('WARDROBE_REPAINT_PASS', json.dumps(receipt))


if __name__ == '__main__':
    main()
