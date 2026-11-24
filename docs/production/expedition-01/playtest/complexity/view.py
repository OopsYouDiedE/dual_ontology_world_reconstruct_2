"""Render a verified proposal's exact box footprints, heights and test routes offline."""
import argparse
from html import escape
import json
from pathlib import Path


def render(data):
    m=data['plan']['metrics']; cards=[]
    for row in data['clutter']['rooms']:
        layout=row['layout']; w,_,h=layout['room_size']; route=layout['route']; items=[]
        for item in sorted(layout['items'],key=lambda b:b['layer']):
            x,y,z=item['center'];dx,dy,dz=item['size']; layer=item['layer']; color=['#54747a','#a78c64','#e7c794'][(layer-1)%3]
            items.append(f'<rect x="{x-dx/2}" y="{z-dz/2}" width="{dx}" height="{dz}" fill="{color}" stroke="#131e26" stroke-width=".04"><title>{escape(item["id"])} · 第 {layer} 层 · 顶高 {y+dy/2:.2f} m</title></rect>')
        pts=' '.join(f'{p[0]},{p[2]}' for p in route); s=' / '.join(f'{t["frames"]} tick' for t in row['traversals'])
        cards.append(f'<article><h2>{escape(row["room_id"])}</h2><svg viewBox="-6.7 -4.4 13.4 8.8"><rect x="{-w/2}" y="{-h/2}" width="{w}" height="{h}" fill="#172631" stroke="#88969a" stroke-width=".04"/><polyline points="{pts}" fill="none" stroke="#324e49" stroke-width="{2*layout["route_clear_half_width"]}"/>{"".join(items)}<polyline points="{pts}" fill="none" stroke="#8aded0" stroke-width=".07"/></svg><p>{len(items)} 件 · 最高 {row["max_layer"]} 层 · 正反向 {s}</p></article>')
    return f'''<!doctype html><html lang="zh"><meta charset="utf-8"><title>地图预算 · 房间堆放验收</title><style>body{{background:#101923;color:#e4e9db;font:16px system-ui;max-width:1100px;margin:2rem auto;padding:0 1rem}}section{{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:1rem}}article{{padding:1rem;background:#202f38}}h1,h2{{color:#e7c794}}h2{{margin:0}}svg{{width:100%}}</style><h1>地图预算 · 房间堆放验收</h1><p>{m['rooms']} 个节点 · {m['independent_loops']} 个独立环路 · 地图 {m['map_units']} 单位 · 单路线峰值 {m['decision_bits']:.2f} bit · 全图决策 {m['global_decision_bits']:.2f} bit</p><p>每幅为一个候选双门房间的俯视图。青线是胶囊测试的目标折线，暗绿为预留通道。浅色方块叠在深色上方；悬停查看高度。图中房间单独验收，未拼入正式关卡。</p><section>{''.join(cards)}</section></html>'''

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('report',type=Path);p.add_argument('out',type=Path);a=p.parse_args();a.out.write_text(render(json.loads(a.report.read_text(encoding='utf8'))),encoding='utf8')
