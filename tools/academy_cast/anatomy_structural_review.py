"""Review the final audited cages: aligned photo, solid forms, and real edge loops."""
from argparse import ArgumentParser
from pathlib import Path
import json

from PIL import Image, ImageDraw
import numpy as np
from anatomy_geometry import CAST, FACE, PROFILES, body_measurement
from anatomy_photo_compare import load, projector, target_crop
from anatomy_projection import iou, mesh_mask, reference_mask
from tripo_surface_preview import NAMES, font, raster


def plain(parts):
    return [(name, v, f, np.tile([196, 168, 147], (len(f), 1)) if name == 'Body' else color)
            for name, v, f, color in parts]


def make_comparison(image, baseline, current, out, slugs):
    out.mkdir(parents=True, exist_ok=True)
    n = len(slugs)
    full = (222, 390); ear = (222, 208); pad = 12
    layers = [
        ('形体前后对照', '上：上一版正面　中：本轮正面　下：本轮斜侧。三个视图使用相同尺度。', full),
        ('参考图与模型对位', '上：参考裁切　中：投到实际低模　下：同机位纯色低模。', full),
        ('耳廓：真实网格', '上：上一版侧面　中：本轮低模侧面　下：本轮低模耳廓线框（正后斜侧）。', ear),
    ]
    grids = []
    for title, sub, (w, h) in layers:
        p = Image.new('RGB', (n*(w+4)+2*pad, 111+3*(h+4)), '#171d25')
        g = ImageDraw.Draw(p)
        g.text((pad, 10), title, font=font(26, True), fill='#f1e7d0')
        g.text((pad, 52), sub, font=font(15), fill='#bdc8d4')
        grids.append((p, g))
    nw, nh = 240, 300
    nose = Image.new('RGB', (n*(nw+2), 52+2*nh), '#171d25')
    ng = ImageDraw.Draw(nose)
    ng.text((6,6), '鼻区检查  /  上：侧面　下：斜侧　｜　当前低模，无投影', font=font(17, True), fill='#f1e7d0')
    metrics = []
    for j, slug in enumerate(slugs):
        idx = CAST.index(slug); prof = PROFILES[idx]; name = NAMES[idx]
        old = plain(load(baseline/f'{slug}-low.json'))
        new_raw = load(current/f'{slug}-low.json'); new = plain(new_raw)
        high = plain(load(current/f'{slug}-sculpt.json'))
        skin = [part for part in new if part[0]=='Body']
        nx = j*(nw+2); nz = prof.z(FACE[idx][-1])+.015
        ng.text((nx+5, 29), name, font=font(16, True), fill='#e0e8f0')
        for k, a in enumerate((90,37)):
            frame = ((-.032*np.sin(np.radians(a)),nz),.133)
            nose.paste(raster(new, a, (nw,nh), frame=frame), (nx,52+nh*k))
        p0 = raster(old, 0, full)
        p1 = raster(new, 0, full)
        p2 = raster(new, 38, full)
        imgset = [
            [p0, p1, p2],
            [target_crop(image, prof, full, 'full'), raster(new_raw, 0, full, shader=projector(image, prof)),p1],
            [raster(old, 90, ear, 'head', level=idx), raster(new, 90, ear, 'head', level=idx),
             raster(skin, 109, ear, 'head', True, idx)],
        ]
        for (p, g), imgs in zip(grids, imgset):
            x = pad+j*(imgs[0].width+4)
            g.text((x+3, 83), name, font=font(17, True), fill='#e0e8f0')
            for k, im in enumerate(imgs):
                p.paste(im, (x, 107+k*(im.height+4)))
        # Each character has separately lit silhouette views and enlarged local wire views.
        w, h = 245, 428
        sheet = Image.new('RGB', (4*(w+4)+24, 98+h+2*254+16), '#171d25'); g = ImageDraw.Draw(sheet)
        g.text((pad, 9), name+'  /  低模纯色与布线', font=font(24, True), fill='#f1e7d0')
        g.text((pad, 48), '胸肩与腰髋看明暗转折；小腿看前后厚度；耳部高低模并列。', font=font(15), fill='#bdc8d4')
        for k, (a, label) in enumerate(zip((0, 38, 90, 180), ('正面','斜侧','侧面','背面'))):
            x = pad+k*(w+4)
            g.text((x, 75), label, font=font(15, True), fill='#e0e8f0')
            sheet.paste(raster(new, a, (w,h)), (x,98))
        views = ((36, .705, .37, '胸肩 / 腰髋'), (22, .255, .51, '大腿 / 小腿'),
                 (90, .924, .19, '耳廓低模'), (90, .924, .19, '耳廓高模'))
        for k, (a,z,h0,label) in enumerate(views):
            x=pad+k*(w+4); y=98+h+5
            g.text((x, y), label, font=font(15, True), fill='#e0e8f0')
            for l, wire in enumerate((False, True)):
                sheet.paste(raster(high if k==3 else new, a, (w,227), wire=wire, frame=((0,z),h0)), (x,y+25+l*233))
        sheet.save(out/f'{slug}-solid-wire.jpg', quality=94)
        o, v, f, col = new[0]; old_stats = body_measurement(old[0][1], old[0][2]); new_stats = body_measurement(v, f)
        drift={k:float(100*np.linalg.norm(np.subtract(new_stats[k], old_stats[k]))) for k in ('surface_centroid', 'volume_centroid')}
        ref = reference_mask(image, prof)
        metrics.append(dict(character=slug, before_front_iou=iou(mesh_mask(old[0][1], old[0][2]), ref),
                            after_front_iou=iou(mesh_mask(v,f), ref), centroid_drift_pct_height=drift))
        print('REVIEW',slug, metrics[-1], flush=True)
    for (p,_), filename in zip(grids, ('cast-solid-before-after.jpg','cast-front-projection.jpg','cast-auricle.jpg')):
        p.save(out/filename, quality=94)
    nose.save(out/'cast-nose-diagnostic.jpg', quality=94)
    (out/'final-measurements.json').write_text(json.dumps(metrics, indent=2), encoding='utf-8')


if __name__=='__main__':
    parser=ArgumentParser(description=__doc__)
    for name in ('reference','baseline','current','out'):
        parser.add_argument(name,type=Path)
    parser.add_argument('--cast',nargs='+',choices=CAST,default=CAST)
    args=parser.parse_args()
    make_comparison(Image.open(args.reference).convert('RGB'),args.baseline,args.current,args.out,args.cast)
