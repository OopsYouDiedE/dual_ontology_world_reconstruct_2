"""Build an offline atlas of delivered captions from explicitly selected replay batches."""
import argparse, csv, json, math, re
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCENE = HERE.parents[3] / 'scenes/expedition_01'


def catalog():
    result = {}
    def add(key, who, line):
        if line:
            result.setdefault((who or '心声') + '：' + line, set()).add(key)
    exp = (SCENE/'Expedition.gd').read_text(encoding='utf8')
    src = exp + '\n' + (SCENE/'ArchiveWitness.gd').read_text(encoding='utf8')
    for m in re.finditer(r'(line_once|show_line|thought|captions\.post)\("(\w+)",(.*)', src):
        kind, key, args = m.groups()
        who = '心声' if kind == 'thought' else 'Hale'
        if kind == 'captions.post':
            match = re.match(r'"([^"]*)",(.*)',args)
            if not match: continue
            who,args = match.groups()
        if not args.startswith('"'): continue
        add(key,who,args.split('"')[1]); alt = re.search(r' else "([^"]+)"',args)
        if key == 'north_order': alt = re.search(r' else "([^"]+)"',src[m.end():].splitlines()[1])
        if alt: add(key,who,alt[1])
    for table,who in [('STELE_TEXT','心声'),('HALE_TALK','Hale')]:
        block = exp.split('const '+table,1)[1].split('}',1)[0]
        for k,v in re.findall(r'"(\w+)":"([^"]+)"',block): add(k,who,v)
    for line in re.findall(r'return "([^"]+)"', exp.split('func hale_hears_well()',1)[1].split('\nfunc ',1)[0]):
        for k in ('advise','hale_read'): add(k,'Hale',line)
    for line in ('我还盯着那块板。你那边怎么样？','等一下，让我听听。'): add('advise','Hale',line)
    contracts = (SCENE/'ExpeditionContracts.gd').read_text(encoding='utf8')
    for line in re.findall(r'return "([^"]+)"', contracts.split('func b_line',1)[1].split('\n##',1)[0]): add('call_b','Hale',line)
    return result


def zones(x,y,z):
    if .3<=x<7 and abs(z)<1.9: yield 'start'
    if 30<x<36 and abs(z)<2.3: yield 'sealed_well'
    if 28.2<x<33.8 and 4.4<z<7.1: yield 'collapse'
    if math.dist((x,y,z),(21.43,0,8.46))<2.60: yield from ('ward_paired','ward_unseen')
    if 47.2<x<51.9: yield 'shaft_doubt'


def load(matrix,human):
    lines=catalog(); cases=[]; hits=[]; audited={'start','sealed_well','collapse','ward_paired','ward_unseen','shaft_doubt'}
    for cohort,root,name in [('固定路线',matrix,'route.json'),('类人策略',human,'report.json')]:
        files=sorted(root.glob('*/'+name))
        if not files: raise ValueError(f'No {name}: {root}')
        for f in files:
            d=json.loads(f.read_text(encoding='utf8')); case=f'{cohort}/{f.parent.name}'; events=d['events']; path=d['path_samples']; reached=set()
            for p in [row[1:] for row in path]+[e['feet'] for e in events if e['event']=='dialogue']: reached.update(zones(*p))
            outcome=d['outcome']; pp=d['policy_parameters']; profile=pp.get('approach',d['profile'])
            if outcome=='interrupted' and any('本次失败' in str(e.get('value','')) for e in events): outcome='gameplay_death'
            cases.append(dict(case=case,cohort=cohort,profile=profile,seed=d['seed'],outcome=outcome,params=pp,zones=sorted(reached),path=[[round(p[1],2),round(p[3],2)] for p in path[::5]]))
            for e in events:
                if e['event']!='dialogue': continue
                x,y,z=e['feet']; line=e['value']; keys=lines.setdefault(line,{'observed_only'})
                hits.append(dict(case=case,cohort=cohort,profile=profile,line=line,tick=e['tick'],x=x,y=y,z=z,local=bool(keys.intersection(zones(x,y,z)))))
    rates=[]
    for cohort in sorted({c['cohort'] for c in cases}):
        for profile in ['全部']+sorted({c['profile'] for c in cases if c['cohort']==cohort}):
            group=[c for c in cases if c['cohort']==cohort and profile in ('全部',c['profile'])]; ids={c['case'] for c in group}
            for line,keys in sorted(lines.items()):
                ev=[h for h in hits if h['line']==line and h['case'] in ids]; n=len({h['case'] for h in ev}); geo=bool(keys & audited)
                reached=sum(bool(keys.intersection(c['zones'])) for c in group) if geo else None
                local=len({h['case'] for h in ev if h['local']}) if geo else None
                rates.append(dict(cohort=cohort,profile=profile,line=line,keys='/'.join(sorted(keys)),heard=n,runs=len(group),pct=round(100*n/len(group),2),events=len(ev),local=local,reached=reached,local_pct=round(100*local/reached,2) if reached else None))
    order=[]
    for c in cases:
        ticks={}
        for h in hits:
            if h['case']==c['case']:
                for key in lines[h['line']]: ticks[key]=min(ticks.get(key,h['tick']),h['tick'])
        paired='ward_paired' in ticks; unseen='ward_unseen' in ticks
        order.append(dict(case=c['case'], passed_door_region='ward_paired' in c['zones'],
                          door_line='both' if paired and unseen else 'paired' if paired else 'unseen' if unseen else 'none',
                          both=paired and unseen, paired_without_prior_window_caption=paired and ('window' not in ticks or ticks['window']>=ticks['ward_paired'])))
    return dict(cases=cases,hits=hits,rates=rates,order=order)


def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--matrix',type=Path,required=True); ap.add_argument('--human',type=Path,required=True); ap.add_argument('--out',type=Path,required=True); a=ap.parse_args(); a.out.mkdir(parents=True,exist_ok=True); data=load(a.matrix,a.human)
    for name in ['hits','rates','order']:
        rows=data[name]
        if rows:
            with (a.out/(name+'.csv')).open('w',encoding='utf-8-sig',newline='') as f:
                w=csv.DictWriter(f,fieldnames=rows[0]); w.writeheader(); w.writerows(rows)
    js=json.dumps(data,ensure_ascii=False,separators=(',',':')).replace('<','\\u003c'); (a.out/'index.html').write_text((HERE/'dialogue_atlas.html').read_text(encoding='utf8').replace('/*DATA*/',js),encoding='utf8'); print(len(data['cases']),'cases;',len(data['hits']),'deliveries;',Counter(c['outcome'] for c in data['cases']))

if __name__=='__main__': main()
