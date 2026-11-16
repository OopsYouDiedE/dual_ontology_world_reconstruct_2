"""Create anonymous, text-masked images; keep source hashes outside the blind input."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'mcp'))
import capture_provenance as provenance


def build(specification, output):
    provenance.assert_runtime_root(ROOT)
    output = provenance.project_path(output, ROOT)
    output.mkdir(parents=True, exist_ok=False)
    public, private = [], []
    for index, group in enumerate(specification, 1):
        if not group.get('images'):
            raise ValueError('A blind group requires actual captured images')
        gid = f'G{index:02d}'
        folder = output / gid
        folder.mkdir()
        rendered, sources, frame_ids = [], [], []
        for number, value in enumerate(group['images'], 1):
            source = provenance.project_path(value, ROOT)
            checked = provenance.verify_image(source, ROOT, allow_fixture=True)
            meta = json.loads(Path(checked['sidecar_path']).read_text(encoding='utf-8-sig'))
            image = Image.open(source).convert('RGB')
            draw = ImageDraw.Draw(image)
            rects = []
            for text in meta.get('visible_text', []):
                # Spatial labels are part of the live scene: keep identity and avoid
                # hiding heads/bodies with their generously sized projected AABBs.
                if text.get('class') == 'Label3D':
                    continue
                rect = [max(0, math.floor(text['x']-4)), max(0, math.floor(text['y']-4)),
                        min(image.width, math.ceil(text['x']+text['width']+4)),
                        min(image.height, math.ceil(text['y']+text['height']+4))]
                if rect[2] > rect[0] and rect[3] > rect[1]:
                    draw.rectangle(rect, fill='#25312e')
                    rects.append(rect)
            # Older receipts did not include text bounds. Hide their narrative UI strip.
            if 'visible_text' not in meta:
                rect = [0, int(image.height*.73), image.width, image.height]
                draw.rectangle(rect, fill='#25312e'); rects.append(rect)
            fid = f'{gid}-F{number:02d}'
            path = folder / f'{fid}.png'
            image.save(path)
            thumb = Image.new('RGB', (640, 424), '#25312e')
            image.thumbnail((640, 400))
            thumb.paste(image, ((640-image.width)//2, 24+(400-image.height)//2))
            ImageDraw.Draw(thumb).text((12,4), fid, fill='white')
            rendered.append(thumb); frame_ids.append(fid)
            sources.append(dict(frame_id=fid, original=source.relative_to(ROOT).as_posix(),
                original_sha256=checked['image_sha256'], masked=path.relative_to(ROOT).as_posix(),
                masked_sha256=hashlib.sha256(path.read_bytes()).hexdigest(), masks=rects))
        # Split long groups so a viewer can inspect the images at useful scale.
        sheets = []
        for offset in range(0,len(rendered),9):
            batch = rendered[offset:offset+9]
            sheet = Image.new('RGB',(1920,424*math.ceil(len(batch)/3)),'#25312e')
            for i, frame in enumerate(batch): sheet.paste(frame,((i%3)*640,(i//3)*424))
            path = folder/f'{gid}-sheet-{offset//9+1}.jpg'
            sheet.save(path,quality=92); sheets.append(path.relative_to(output).as_posix())
        public.append(dict(group_id=gid, frame_ids=frame_ids, sheets=sheets,
            images=[f'{gid}/{fid}.png' for fid in frame_ids]))
        private.append(dict(group_id=gid, segment_id=group['segment_id'], frames=sources,
            source_revision=group.get('source_revision'), source_note=group.get('source_note','')))
    (output/'input.json').write_text(json.dumps(dict(groups=public, modality='narrative-text-masked still images; spatial labels retained; no audio'),indent=2),encoding='utf-8')
    # The independent observer receives input.json only; this mapping stays with the comparison author.
    (output/'source-map.json').write_text(json.dumps(private,ensure_ascii=False,indent=2),encoding='utf-8')
    return dict(groups=len(public),frames=sum(len(g['frame_ids']) for g in public),output=str(output))


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--specification',required=True)
    parser.add_argument('--output',required=True)
    args=parser.parse_args()
    specification=json.loads(provenance.project_path(args.specification,ROOT).read_text(encoding='utf-8-sig'))
    print(json.dumps(build(specification,args.output)))
