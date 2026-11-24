"""Plot the autonomous atlas and audit player/companion proximity by matching sample tick."""
import argparse
import csv
import json
import math
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.collections import LineCollection

DOOR = (21.43, 0, 8.46)
PROFILES = [('cautious', '谨慎', '#168882'), ('curious', '好奇', '#ba621f'), ('direct', '直行', '#516dab')]
LABELS = {'start': '出发交代', 'hale_gate': 'Hale 查明插销', 'collapse': '塌拱与档案翼', 'niche': '壁龛', 'sealed_well': '铁闸死锁提示', 'window': '窗前双人注视', 'ward_unseen': '门边警告（未见证）', 'ward_paired': '门边警告（已见证）'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--human', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path, help='completed autonomous atlas directory')
    parser.add_argument('--font', default='Microsoft YaHei')
    args = parser.parse_args()
    with (args.out/'rates.csv').open(encoding='utf-8-sig') as f:
        rates = [r for r in csv.DictReader(f) if r['cohort']=='类人策略' and r['profile']=='全部']
    paths = {key: [] for key, _, _ in PROFILES}
    audit = []
    for file in sorted(args.human.glob('*/report.json')):
        replay = json.loads(file.read_text('utf8'))
        profile = replay['profile']; player = replay['path_samples']; hale = {t:p for t,*p in replay['hale_path_samples']}
        paths[profile].append([(x,z) for _,x,_,z in player])
        near = [(t,hale[t]) for t,*p in player if math.dist(p,DOOR)<3.25]
        audit.append((profile,replay['seed'],len(near),sum(math.dist(h,DOOR)<1.25 for _,h in near)))
    assert rates and all(int(r['runs'])==len(audit) for r in rates)
    with (args.out/'door-samples.csv').open('w',newline='',encoding='utf-8-sig') as f:
        writer = csv.writer(f); writer.writerow(('profile','seed','player_within_3.25m_samples','both_within_3.25m_and_1.25m_samples')); writer.writerows(audit)
    plt.rcParams.update({'font.family':args.font, 'axes.unicode_minus':False,'axes.spines.right':False,'axes.spines.top':False})
    fig = plt.figure(figsize=(11,7),layout='constrained'); grid=fig.add_gridspec(2,3,height_ratios=[1,1.65]); axes=[]
    fig.suptitle(f'首征 AI 自主探索  /  {len(audit)} 局', fontsize=19, fontweight='bold')
    for i,(key,title,color) in enumerate(PROFILES):
        ax=fig.add_subplot(grid[0,i],sharex=axes[0] if axes else None,sharey=axes[0] if axes else None); axes.append(ax)
        ax.add_collection(LineCollection(paths[key],colors=color,alpha=.22,linewidths=.75)); ax.update_datalim([(1,0),(35,0),(DOOR[0],DOOR[2])]); ax.autoscale(); ax.set_aspect('equal', adjustable='box'); ax.grid(alpha=.15)
        for x,z,label in [(1,0,'入口'),(35,0,'铁闸'),(DOOR[0],DOOR[2],'档案门')]:
            ax.plot(x,z,'.',color='#263b48'); ax.annotate(label,(x,z),xytext=(0,-11 if label=='档案门' else 4),textcoords='offset points',ha='center',fontsize=8)
        ax.set_title(f'{title} · {len(paths[key])} 局',color=color); ax.set_xlabel('X（米）')
    axes[0].set_ylabel('Z（米）')
    ax=fig.add_subplot(grid[1,:]); shown=[r for r in rates if int(r['heard']) or r['keys'] in LABELS]; shown.sort(key=lambda r:(-int(r['heard']),r['keys']))
    for i,r in enumerate(shown):
        pct=float(r['pct']); ax.barh(i,pct,color='#168882'); ax.text(pct+1,i,f"{r['heard']}/{r['runs']}  ·  {pct:g}%",va='center',fontsize=9)
    ax.set_yticks(range(len(shown)),[LABELS.get(r['keys'],r['line'][:18]) for r in shown]); ax.invert_yaxis(); ax.set_xlim(0,119); ax.set_xticks(range(0,101,20)); ax.grid(axis='x',alpha=.15); ax.set_xlabel('至少收到一次该句的局数 / 全部自主局（%）'); ax.set_title('实际送达的台词与重点零命中节点',loc='left',fontweight='bold')
    fig.savefig(args.out/'autonomous.png',dpi=140); plt.close(fig)


if __name__=='__main__': main()
