"""Paint the inspectable print from a supplied darkroom reference. The output uses layered,
edge-following brush marks; the tilted sheet, lens and UI are separate runtime controls.
Usage: python tools/blue_prince_lab/reference/print_study.py path/to/darkroom-frame.png
"""
import argparse
from pathlib import Path
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter


def paint(source):
    rng = np.random.default_rng(901)
    w, h = 450, 626
    with Image.open(source) as src:
        # Corners of the user-supplied print in the 1522x905 frame, TL/BL/BR/TR.
        quad = [(666,130), (733,763), (1184,730), (1115,98)]
        region = tuple(v for x,y in quad for v in (x*src.width/1522, y*src.height/905))
        src = src.convert('RGB').transform((w,h), Image.Transform.QUAD, region, Image.Resampling.BICUBIC)
    a = np.asarray(src,dtype=float)
    # The rim of the reference's magnifier crosses the left margin. Repaint that strip
    # from an adjacent background column; the in-game lens can then move independently.
    for y in range(115,465):
        a[y,:33] = a[y,39:72][::-1]
    tone = (.48*a[:,:,0]+.37*a[:,:,1]+.15*a[:,:,2])
    tone = np.asarray(Image.fromarray(tone.astype('uint8')).filter(ImageFilter.GaussianBlur(.8)),dtype=float)
    gy,gx=np.gradient(tone); strength=np.hypot(gx,gy)
    palette=np.array([[31,27,31],[55,39,40],[81,54,53],[115,77,73],[151,103,96],[188,133,122],[218,166,151],[237,196,177]])
    levels=np.array([11,32,50,74,100,126,157,192])
    def ink(v):return tuple(int(np.interp(v,levels,palette[:,c])) for c in range(3))
    dst=Image.new('RGB',(w,h),(60,42,43));d=ImageDraw.Draw(dst)
    for step,length,width in [(8,18,12),(4,9,6),(2,4,3),(1,3,1)]:
        ys=np.arange(0,h,step); xs=np.arange(0,w,step)
        for yy in ys:
            for xx in xs:
                y=min(h-1,yy+int(rng.integers(step)));x=min(w-1,xx+int(rng.integers(step)))
                if step==1 and (strength[y,x]<3.1 or rng.random()>.56):continue
                angle=math.atan2(gy[y,x],gx[y,x])+math.pi/2 if strength[y,x]>1.4 else -.7+.45*math.sin(y/73.)
                angle+=rng.normal(0,.18);r=length*(.32+rng.random()*.4);dx,dy=r*math.cos(angle),r*math.sin(angle)
                d.line([(x-dx,y-dy),(x,y),(x+dx,y+dy)], fill=ink(tone[y,x]+rng.normal(0,2)),width=width)
    # Fibres and a scuffed border belong to the print rather than to the room.
    for i in range(465):
        x=int(rng.integers(w));y=int(rng.choice([rng.integers(6),h-1-rng.integers(7)]));d.line((x,y,x+int(rng.integers(1,8)),y-1),fill=(152,115,103))
    return dst

if __name__=='__main__':
    args=argparse.ArgumentParser(description=__doc__);args.add_argument('reference');opts=args.parse_args()
    paint(opts.reference).save(Path(__file__).resolve().parents[3]/'scenes/blue_prince_lab/reference/interface/ArchivePrint.png')
