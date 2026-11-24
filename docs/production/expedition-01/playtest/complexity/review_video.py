"""Encode a side-by-side-in-time (stacked maps) topology replay from review data."""
import argparse
import json
import math
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw, ImageFont
from review_plans import ROOT, label, ACTION

FPS, FRAMES_PER_STEP, HOLD = 24, 13, 36
WIDTH, HEIGHT = 1280, 820
BG, PANEL, INK, MUTED, GOLD, DIM = '#0e171f','#182630','#edf3f6','#a6bdcc','#ffd075','#506778'


def curve(a, b):
    x0,y0 = a; x1,y1 = b
    mid = (y0+y1)/2
    points = [a,(x0,mid),(x1,mid),b] if y0 != y1 else [a,a,b,b]
    return [tuple(sum(math.comb(3,i)*t**i*(1-t)**(3-i)*p[k] for i,p in enumerate(points))
                 for k in range(2)) for t in (j/32 for j in range(33))]


def make_frame(data, frame, fonts):
    im = Image.new('RGB', (WIDTH,HEIGHT), BG)
    d = ImageDraw.Draw(im)
    small,body,heading,title = fonts
    d.text((30,24),'EXPEDITION 01  /  PEAK ROUTE',font=title,fill=INK)
    d.text((1250,37),'拓扑演示 · 非实机 · 每一步为一条逻辑连线',font=body,fill=MUTED,anchor='ra')
    t = max(0,frame-HOLD//2)/FRAMES_PER_STEP
    for index,row in enumerate(data['candidates']):
        top = 80 + index*352
        d.rounded_rectangle((22,top,1258,top+336),radius=14,fill=PANEL,outline=DIM)
        m = row['plan']['metrics']; peak = row['peak']; n = len(peak)
        placed = {key:(60+x,top+49+y*.77) for key,(x,y) in row['positions'].items()}
        progress = min(n,t); step = int(progress); fraction = progress-step
        d.text((42,top+12),f'{row["name"].title()}   ·   {m["decision_bits"]:.2f} bit',font=heading,fill=INK)
        d.text((1235,top+18),f'{step:02d} / {n:02d} 步',font=body,fill=GOLD,anchor='ra')
        links = {(e['src'],e['dst']) for e in row['plan']['edges']}
        curves = {pair:curve(*(placed[k] for k in pair)) for pair in sorted(links)}
        route = [(e['src'],e['dst']) for e in peak]
        for pair, pts in curves.items():
            d.line(pts,fill='#8a7951' if pair in route else DIM,width=3 if pair in route else 2)
        for pair in route[:step]: d.line(curves[pair],fill=GOLD,width=5)
        spot = placed[route[-1][1] if step==n else route[step][0]]
        if step<n and fraction:
            pts = curves[route[step]]; k = min(31,int(fraction*32)); v = fraction*32-k
            spot = tuple(pts[k][j]*(1-v)+pts[k+1][j]*v for j in range(2))
            d.line(pts[:k+1]+[spot],fill=GOLD,width=5)
        visited = {route[0][0],*(b for a,b in route[:step])}
        for key,(x,y) in placed.items():
            d.rounded_rectangle((x-44,y-16,x+44,y+16),radius=6,fill='#3c3322' if key in visited else '#253a48',outline=GOLD if key in visited else DIM)
            d.text((x,y),label(key),font=small,fill=INK,anchor='mm')
        x,y = spot
        d.line((x,y-16,x,y-8),fill=GOLD,width=2)
        d.ellipse((x-6,y-26,x+6,y-14),fill=GOLD,outline=BG,width=2)
        status = '已到达撤离终点' if step==n else f'{label(peak[step]["src"])} → {label(peak[step]["dst"])}   ·   {ACTION[peak[step]["action"]]}'
        d.text((43,top+301),status,font=body,fill=GOLD)
    d.text((29,790),'亮线：已走过的峰值路线   ·   两图按同一节拍推进，先到者停在终点',font=small,fill=MUTED)
    return im


def encode(data, destination, ffmpeg='ffmpeg', font=None):
    font = font or Path('C:/Windows/Fonts/msyh.ttc')
    fonts = [ImageFont.truetype(str(font),size) for size in (16,19,25,31)]
    total = max(len(row['peak']) for row in data['candidates'])*FRAMES_PER_STEP+HOLD*2
    cmd = [ffmpeg,'-hide_banner','-loglevel','error','-y','-f','rawvideo','-pix_fmt','rgb24',
           '-s',f'{WIDTH}x{HEIGHT}','-r',str(FPS),'-i','-','-an','-c:v','libx264','-crf','21',
           '-pix_fmt','yuv420p','-movflags','+faststart',str(destination)]
    with subprocess.Popen(cmd,stdin=subprocess.PIPE) as proc:
        try:
            for k in range(total): proc.stdin.write(make_frame(data,k,fonts).tobytes())
        finally:
            proc.stdin.close()
        if proc.wait(): raise RuntimeError('ffmpeg did not encode the topology demo')


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out',type=Path,default=ROOT/'.runtime/design-review')
    p.add_argument('--ffmpeg',default='ffmpeg'); p.add_argument('--font',type=Path)
    a=p.parse_args(); data=json.loads((a.out/'plans.json').read_text(encoding='utf-8'))
    encode(data,a.out/'plans.mp4',a.ffmpeg,a.font)
    from review_plans import render
    (a.out/'plans.html').write_text(render(data,(a.out/'plans.mp4').read_bytes()),encoding='utf-8')
