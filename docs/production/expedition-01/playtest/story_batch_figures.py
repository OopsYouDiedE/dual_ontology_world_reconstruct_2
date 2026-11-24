"""Render shareable cohort summaries alongside dialogue_atlas.py outputs."""
import argparse
import csv
import gzip
import io
import json
from collections import Counter
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.collections import LineCollection
from matplotlib.lines import Line2D
from dialogue_atlas import load

BLUE, ORANGE, INK = '#147e86', '#c16a25', '#203746'


def csv_text(headers, rows):
    buf = io.StringIO(newline='')
    writer = csv.writer(buf, lineterminator='\n')
    writer.writerow(headers)
    writer.writerows(rows)
    return buf.getvalue()


def first_figure(data, out):
    fig, (ax, bars) = plt.subplots(2, 1, figsize=(10, 8), gridspec_kw={'height_ratios':[1, 1.25]}, layout='constrained')
    colors = {'类人策略': BLUE, '固定路线': ORANGE}
    cohorts = list(colors)
    for cohort in reversed(cohorts):
        paths = [c['path'] for c in data['cases'] if c['cohort']==cohort]
        ax.add_collection(LineCollection(paths, colors=colors[cohort], linewidths=.8, alpha=.24 if cohort==cohorts[0] else .6))
    ax.autoscale(); ax.set_aspect('equal', adjustable='datalim'); ax.invert_yaxis()
    ax.set_xlabel('X（米）'); ax.set_ylabel('Z（米）'); ax.grid(alpha=.15)
    for name,x,z,dy in [('出发',1,0,-9),('铁闸',35,0,-10),('试板',23.85,12,10),('井区入口',49,10,12)]:
        ax.plot(x,z,'.',color=INK); ax.annotate(name,(x,z),xytext=(0,dy),textcoords='offset points',ha='center',va='center',fontsize=9)
    ax.legend([Line2D([0],[0],color=c) for c in colors.values()], [f'{cohort} · {sum(c["cohort"]==cohort for c in data["cases"])} 局' for cohort in cohorts], loc='upper right',frameon=False,ncol=2,fontsize=9)
    ax.set_title('首征实走轨迹  /  每条线是一局，按世界 XZ 坐标投影', loc='left',fontweight='bold')
    milestones=[('start','Hale 交代试闸任务'),('hale_gate','Hale 查明机械插销'),('collapse','发现塌拱，改走档案翼'),('window','双人注视令试板翻红'),('ward_unseen','未见双视实证时的门边警告'),('ward_paired','见过双视实证后的门边警告'),('release','拉起配重链，隔离闸打开'),('core','源核脱槽，井壁警铃响起')]
    rates={(r['cohort'],r['keys']):r for r in data['rates'] if r['profile']=='全部'}
    for i,cohort in enumerate(cohorts):
        for j,(key,_) in enumerate(milestones):
            r=rates[cohort,key]; y=j+(i-.5)*.34
            bars.barh(y,r['pct'],.28,color=colors[cohort]); bars.text(r['pct']+1,y,f"{r['heard']}/{r['runs']}",va='center',fontsize=8,color=INK)
    bars.set_yticks(range(len(milestones)),[s for _,s in milestones]); bars.invert_yaxis(); bars.set_xlim(0,118); bars.set_xticks(range(0,101,20)); bars.set_xlabel('本组至少听到一次的局数占比（%）'); bars.grid(axis='x',alpha=.15)
    bars.set_title('八句剧情节点  /  自主探索与定向穿越分别统计',loc='left',fontweight='bold')
    fig.savefig(out/'first-expedition.png',dpi=155); plt.close(fig)


def campaign(rows, out):
    n=len(rows); edges=Counter(); nodes=Counter(); lines=Counter(); outcomes=Counter(); actions=[]
    for r in rows:
        route=r['route']; edges.update(set(zip(route,route[1:]))); nodes.update(set(route)); outcomes[r['outcome']]+=1
        lines.update({a[3] for a in r['actions']}); actions.extend((r['seed'],i,*a) for i,a in enumerate(r['actions'],1))
    for name,headers,records in [
        ('campaign-runs',['seed','outcome','room_sequence'],[(r['seed'],r['outcome'],' > '.join(r['route'])) for r in rows]),
        ('campaign-edges',['from','to','runs','denominator','percent'],[(a,b,k,n,round(k*100/n,2)) for (a,b),k in sorted(edges.items())]),
        ('campaign-lines',['apparatus_receipt','runs','denominator','percent'],[(line,k,n,round(k*100/n,2)) for line,k in sorted(lines.items(),key=lambda kv:(-kv[1],kv[0]))])]:
        (out/(name+'.csv')).write_text(csv_text(headers,records),encoding='utf-8-sig')
    (out/'campaign-actions.csv.gz').write_bytes(gzip.compress(csv_text(['seed','ordinal','room','stage','option','receipt'],actions).encode('utf-8-sig'),mtime=0))
    pos={'camp':(0,0),'turntable':(3,0),'observatory':(5,0)}
    names={'camp':'公共大厅','turntable':'折返闸','observatory':'天文台'}
    for i,x in enumerate([1,2,4],1):
        for side,y,label in [('west',1,'西'),('east',-1,'东')]:
            node=f'{side}_{i}'; pos[node]=(x,y); names[node]=f'{label}翼 {i}'
    fig,ax=plt.subplots(figsize=(11,4),layout='constrained'); ax.axis('off')
    for (a,b),k in sorted(edges.items()):
        recall={a,b}=={'camp','turntable'}
        ax.annotate('',xy=pos[b],xytext=pos[a],arrowprops=dict(arrowstyle='-|>',color=ORANGE if recall else BLUE,alpha=.7,lw=.8+3*k/n,shrinkA=24,shrinkB=24,connectionstyle=f'arc3,rad={.21 if recall else 0}'))
    for node,(x,y) in pos.items():
        ax.text(x,y,f'{names[node]}\n{nodes[node]}/{n}',ha='center',va='center',color=INK,fontsize=11,bbox=dict(boxstyle='round,pad=.38',fc='#edf5f4',ec='none'))
    ax.set(xlim=(-.6,5.6),ylim=(-1.55,1.55)); ax.set_title(f'返营后的独行战役  /  {n} 个地图种子',loc='left',fontweight='bold',fontsize=16)
    ax.text(.01,.02,f"节点：至少到访一次的局数　·　箭头越粗，经过的局越多　·　橙色：{edges['turntable','camp']} 局乘车折返\n敲响晨钟 {outcomes['won']} 局，途中失败 {outcomes['lost']} 局。抵达天文台后仍须解开最后一道机关。",transform=ax.transAxes,color=INK,fontsize=10)
    fig.savefig(out/'campaign-routes.png',dpi=150); plt.close(fig)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for k in ('matrix','human','campaign-log','out'): p.add_argument('--'+k,type=Path,required=True)
    p.add_argument('--font',default='Microsoft YaHei'); a=p.parse_args()
    plt.rcParams.update({'font.family':a.font,'axes.unicode_minus':False,'axes.spines.top':False,'axes.spines.right':False,'text.color':INK})
    manifest=json.loads((a.human/'batch.json').read_text('utf8')); cases=manifest['cases']
    if len(cases)!=manifest['planned'] or any(c['status']!='ok' for c in cases): raise ValueError('incomplete or invalid Human Sol matrix')
    matrix=json.loads((a.matrix/'report.json').read_text('utf8'))['cases']
    for r in matrix:
        if not r['ok'] and not (r['outcome']=='failed' and r['reason'] and r['errors'] and all(e.strip().startswith('ERROR: Gameplay failure at ') for e in r['errors'])):
            raise ValueError(f'unclassified fixed-path failure: {r}')
    if {p.parent.name for p in a.matrix.glob('*/route.json')}!={r['case'] for r in matrix}: raise ValueError('fixed-path manifest mismatch')
    if {p.parent.name for p in a.human.glob('*/report.json')}!={r['directory'] for r in cases}: raise ValueError('agent manifest mismatch')
    log=a.campaign_log.read_text('utf8'); rows=json.loads(next(s.removeprefix('CAMPAIGN_AUDIT ') for s in log.splitlines() if s.startswith('CAMPAIGN_AUDIT ')))
    if 'ERROR:' in log or [r['seed'] for r in rows]!=list(range(1,257)) or any(not r['actions'] or r['outcome'] not in ('won','lost') for r in rows): raise ValueError('invalid campaign matrix')
    a.out.mkdir(exist_ok=True,parents=True); first_figure(load(a.matrix,a.human),a.out); campaign(rows,a.out)


if __name__=='__main__': main()
