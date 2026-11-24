"""Generate comparable, self-contained logical route maps (no Godot required)."""
import argparse
import base64
from collections import defaultdict
from html import escape
import json
from pathlib import Path

from plan import PRESETS, SPINE, WINGS, choose

ROOT = Path(__file__).resolve().parents[5]
LABEL = dict(hall='大厅', archive='档案', trial='试板', switch='总闸', shaft='源井', core='取芯',
             stair='螺旋梯', gallery='检修回廊', exit='撤离', window='观察窗', store='油料间',
             loft='阁楼', north_window='北窗', south_walk='南侧步道', records='记录室')
ACTION = dict(walk='前进', self_cross='自行过桥', throw_decoy='投掷节拍器诱饵', observe='观察取证',
              take_oil='拾取灯油', take_clock='取得节拍器', post_hale='派 Hale 到北窗',
              spend_oil='消耗灯油绕行', inspect_record='查看记录')
BITS = {1: '观察知识', 2: '灯油', 4: '节拍器'}
WIDTH, HEIGHT = 1152, 350


def label(node):
    return LABEL[node] if node in LABEL else LABEL[node.split('_passage_')[0]] + '延廊'


def bits(mask):
    return '、'.join(v for k, v in BITS.items() if mask & k) or '—'


def layout():
    xy = {n: (64 + i * 128, 175) for i, n in enumerate(SPINE)}
    for i, (src, name, dst, *_rest) in enumerate(WINGS):
        left, right = xy[src][0], xy[dst][0]
        y = (55, 110, 282, 68, 282, 68)[i]
        xy[name] = (left + 7, y)
        xy[name + '_passage_1'] = (right - 7, y)
    return xy


def render_map(name, plan, xy, peak):
    edges = defaultdict(list)
    for e in plan['edges']:
        edges[e['src'], e['dst']].append(e['action'])
    peak_links = {(e['src'], e['dst']) for e in peak}
    peak_nodes = {e[key] for e in peak for key in ('src', 'dst')}
    lines, nodes = [], []
    for (a, b), actions in edges.items():
        x0,y0 = xy[a]; x1,y1 = xy[b]
        wing = a not in SPINE or b not in SPINE
        if y0 != y1:
            direction = 1 if y1 > y0 else -1
            path = f'M{x0} {y0+18*direction} C{x0} {(y0+y1)/2} {x1} {(y0+y1)/2} {x1} {y1-21*direction}'
        else:
            direction = 1 if x1 > x0 else -1
            path = f'M{x0+45*direction} {y0} L{x1-48*direction} {y1}'
        cls = 'peak' if (a,b) in peak_links else 'branch' if wing else 'spine'
        lines.append(f'<path class="{cls}" d="{path}" marker-end="url(#{name}-{cls})"><title>{label(a)} → {label(b)}：{" / ".join(ACTION[k] for k in actions)}</title></path>')
    for node in plan['rooms']:
        x,y = xy[node]
        cls = 'visited' if node in peak_nodes else 'optional' if node not in SPINE else 'fixed'
        nodes.append(f'<g class="{cls}"><title>{escape(node)}</title><rect x="{x-45}" y="{y-18}" width="90" height="36" rx="7"/><text x="{x}" y="{y}">{label(node)}</text></g>')
    defs = ''.join(f'<marker id="{name}-{k}" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="8" markerHeight="8" markerUnits="userSpaceOnUse" orient="auto"><path d="M0 0L8 4L0 8Z" fill="{v}"/></marker>' for k,v in [('peak','#ffd075'),('branch','#8196a6'),('spine','#8196a6')])
    return f'<svg viewBox="0 0 {WIDTH} {HEIGHT}" role="img" aria-label="{name} 有向节点图"><defs>{defs}</defs><text class="axis" x="24" y="24">候选分支</text><text class="axis" x="24" y="141">固定骨架 · 大厅 → 撤离</text>{"".join(lines+nodes)}</svg>'


def detail(data):
    plan = data['plan']
    edges = {(e['src'],e['dst'],e['action']): e for e in plan['edges']}
    raw = plan['metrics']['peak_route']
    state = 0
    route = []
    for item, nxt in zip(raw, raw[1:]):
        a, act = item.split(':'); b = nxt.split(':')[0]
        e = edges[a,b,act]
        assert state & e['requires'] == e['requires']
        options = sum(k[0] == a and state & d['requires'] == d['requires'] for k,d in edges.items())
        before = state
        state = (state | e['grants']) & ~e['consumes']
        route.append(dict(e, options=options, before=before, after=state))
    return route


def card(data):
    name,plan,xy,peak = (data[k] for k in ('name','plan','positions','peak'))
    m,b = plan['metrics'],plan['budgets']
    stats = (('节点',m['rooms']),('空间连线',m['links']),('独立环路',m['independent_loops']),
             ('地图预算',f"{m['map_units']} / {b['map_units']}"),('路线峰值 (bit)',f"{m['decision_bits']:.2f} / {b['decision_bits']}"),
             ('全图决策 (bit)',f"{m['global_decision_bits']:.2f}"))
    metrics = ''.join(f'<div><dt>{k}</dt><dd>{v}</dd></div>' for k,v in stats)
    progression = ' → '.join([label(e['src']) for e in peak]+[label(peak[-1]['dst'])])
    decisions = ''.join(f'<tr><td>{label(e["src"])}</td><td>{e["options"]}</td><td>{ACTION[e["action"]]}</td><td>{bits(e["before"])} → {bits(e["after"])}</td></tr>' for e in peak if e['options']>1)
    alternatives = ''.join(f'<tr><td>{label(e["src"])} → {label(e["dst"])}</td><td>{ACTION[e["action"]]}</td><td>{bits(e["requires"])}</td><td>{bits(e["grants"])}</td><td>{bits(e["consumes"])}</td></tr>' for e in plan['edges'] if e['action']!='walk')
    return f'''<section aria-labelledby="{name}"><h2 id="{name}">{name.title()}</h2><dl>{metrics}</dl>
    <div class="map">{render_map(name,plan,xy,peak)}</div><p class="route"><b>峰值路线：</b>{progression}</p>
    <details><summary>路线决策与资源条件</summary><div class="tables"><table><caption>峰值路线上的决策点</caption><tr><th>节点</th><th>可用动作数</th><th>所选动作</th><th>资源前 → 后</th></tr>{decisions}</table>
    <table><caption>所有非普通移动动作</caption><tr><th>连线</th><th>动作</th><th>前置</th><th>取得</th><th>消耗</th></tr>{alternatives}</table></div></details></section>'''


def render(data, video=None):
    a,b = (p['plan']['metrics'] for p in data['candidates'])
    movie = ''
    if video:
        uri = base64.b64encode(video).decode('ascii')
        movie = f'<section aria-labelledby="demo"><h2 id="demo">峰值路线同行演示</h2><p>拓扑演示 · 非实机。两条路线按相同步频逐边推进，先到者停在撤离终点；节拍与画面距离仅用于比较。</p><video controls playsinline preload="metadata" aria-label="Standard 与 Dense 同屏逐步抵达撤离终点" src="data:video/mp4;base64,{uri}"></video><p><a href="plans.mp4">打开独立 MP4</a></p></section>'
    return '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Expedition 01 · 路线设计对照</title><style>
:root{color-scheme:dark;--accent:#ffd075;--bg:#101921;--panel:#182630;--muted:#b9cad5}*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:#edf3f6;font:16px/1.65 system-ui,sans-serif}main{max-width:1230px;margin:auto;padding:36px 20px 56px}
h1{font-size:clamp(25px,5vw,42px);line-height:1.2;margin:.25em 0}h2{font-size:27px;margin:0}p{margin:.6em 0}.tag,.axis{color:var(--muted);font-size:13px;letter-spacing:.07em}
section{margin-top:24px;padding:18px;border:1px solid #344957;border-radius:12px;background:var(--panel)}dl{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:10px;margin:12px 0}dl div{padding:5px 10px;background:#21333f;border-radius:5px}dt{font-size:13px;color:var(--muted)}dd{margin:0;font-size:21px;font-weight:700;font-variant-numeric:tabular-nums}
.map{overflow:auto;background:#111d26;border:1px solid #344957;border-radius:8px}svg{display:block;width:100%;min-width:950px}svg path:not(marker path){fill:none;stroke:#8196a6;stroke-width:2}svg path.branch{stroke-dasharray:5 4}svg path.peak{stroke:var(--accent);stroke-width:3.3}svg rect{fill:#20323f;stroke:#8196a6}svg .optional rect{stroke-dasharray:4 3}svg .visited rect{fill:#382f20;stroke:var(--accent)}svg text{fill:#edf3f6;font-size:14px;text-anchor:middle;dominant-baseline:middle}svg .axis{fill:#b9cad5;text-anchor:start}
video{display:block;width:100%;max-width:100%;border-radius:8px;background:#0e171f}.route b,.legend b{color:var(--accent)}.tables{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,380px),1fr));gap:16px}table{width:100%;border-collapse:collapse;font-size:14px}caption{text-align:left;font-weight:700;padding:.5em 0}td,th{text-align:left;padding:6px;border-bottom:1px solid #344957}summary{cursor:pointer;color:#d1e3ef}a{color:#a9dcfa}
</style><main><header><div class="tag">EXPEDITION 01 / DESIGN REVIEW</div><h1>地图与路线设计对照</h1>''' + f'''
<p>Seed {data['seed']} · Standard / Dense · 同一套节点坐标与读图方向。两图为逻辑拓扑示意，未进入实机，位置不表示实际距离、高差或用时。</p>
<p>Dense 较 Standard 增加 <strong>{b['rooms']-a['rooms']} 个节点、{b['independent_loops']-a['independent_loops']} 个独立环路</strong>，峰值路线决策量增加 <strong>{b['decision_bits']-a['decision_bits']:.2f} bit</strong>。</p>
<p class="legend"><b>亮实线</b>：从零物资出发的一条峰值路线；灰色虚线：其余分支。箭头表示前进方向。同一空间连线可有多种动作，条件见图下表格。</p></header>
{movie}
{''.join(card(p) for p in data['candidates'])}
<footer><p>地图预算 = 节点 + 2 × 独立环路；路线决策量按通过状态的可用动作数累加 log₂。两个候选均使用预设地图及路线预算，未设全图决策上限。</p><p><a href="#{data['candidates'][0]['name']}">跳回 Standard</a></p></footer></main></html>'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seed', type=int, default=31)
    parser.add_argument('--out', type=Path, default=ROOT / '.runtime/design-review')
    args = parser.parse_args()
    data = dict(schema=1, seed=args.seed, candidates=[])
    for name in ('standard','dense'):
        p = choose(args.seed, *PRESETS[name])
        row = dict(name=name, plan=p, positions={n:xy for n,xy in layout().items() if n in p['rooms']})
        row['peak'] = detail(row)
        data['candidates'].append(row)
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out/'plans.json').write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    (args.out/'plans.html').write_text(render(data), encoding='utf-8')
    print(args.out/'plans.html')


if __name__ == '__main__':
    main()
