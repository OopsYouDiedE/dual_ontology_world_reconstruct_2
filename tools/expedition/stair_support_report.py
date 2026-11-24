"""Make an offline overview of the observed 24,000 east-stair support checks."""
import csv
from collections import Counter
from pathlib import Path

BASE = Path(__file__).resolve().parents[2] / '.runtime/stair-support'


def main():
    with (BASE/'cases.csv').open(encoding='utf8', newline='') as stream:
        rows = list(csv.DictReader(stream))
    counts = Counter()
    seen = set()
    for row in rows:
        low, high, bias, n, passed = (int(row[k]) for k in ('start_radius_cm', 'end_radius_cm', 'mid_bow_cm', 'segments', 'supported'))
        assert passed in (0, 1) and (low, high, bias, n) not in seen
        seen.add((low, high, bias, n))
        counts[low, high, passed] += 1
    radii = list(range(40, 221, 20))
    table = '<tr><th>起点 ↓ ／终点 →</th>'+''.join(f'<th>{h}</th>' for h in radii)+'</tr>'
    for low in radii:
        table += f'<tr><th>{low}</th>'
        for high in radii:
            hits = counts[low, high, 1]
            assert hits + counts[low, high, 0] == 240
            table += f'<td style="background:hsl({round(150*hits/240)} 45% 28%)">{hits}</td>'
        table += '</tr>'
    passed = sum(int(r['supported']) for r in rows)
    assert len(rows) == 24000
    (BASE/'index.html').write_text('''<!doctype html><html lang="zh"><meta charset="utf-8"><title>返程螺旋梯 · 支撑筛查</title><style>body{background:#12232c;color:#eef4ee;font:17px system-ui;max-width:1060px;margin:3em auto;padding:0 25px}td,th{padding:.55em .75em;text-align:center}th{color:#d1dbdb}p{line-height:1.7}a{color:#a1eddc}</style><h1>返程螺旋梯 · 支撑筛查</h1>'''
        + f'<p>共 {len(rows):,} 条候选折线，其中 {passed:,} 条在所有采样点都探到可站立面。每格列出 240 条候选中全程有支撑的条数。行、列是起步与收尾半径（厘米）；格内变化的是中段内外偏移和转向次数。</p><table>'
        + table + '</table><p>在正式场景内，沿折线每隔最多 12 厘米向下扫一次真实角色胶囊。任一点在设计高度上下 42 厘米内未探到可站立面即终止。此表检查足下支撑；速度、转身、侧面净空与猎手追击请对照整关回放。</p><a href="cases.csv">下载所有逐例参数和首个失去支撑的位置</a></html>', encoding='utf8')


if __name__ == '__main__':
    main()
