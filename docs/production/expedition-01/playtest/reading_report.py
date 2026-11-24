"""Build a self-contained report from four complete, matched Human Sol batches."""
import argparse
import json
from pathlib import Path
from dialogue_atlas import catalog
from ending_audit import STEPS

ARMS = ('closed-skip', 'closed-hints', 'book-skip', 'book-hints')


def check_situational_gait(events, trace, book):
    """Replay threat/escape cues for explorers who take in the field text."""
    threat = escaped = False
    moves = {d['tick']: d['intent'] for d in trace if d['intent'].get('move')}
    for e in events:
        kind, value = e['event'], e['value']
        if kind == 'region_card' and any(k in value for k in ('源井', '井区', 'Caisson')):
            threat = True
        elif kind == 'caption':
            if any(k in value.lower() for k in ('动静', '听声', '苏醒', '回声', '脚步声', 'just woke', 'pacing')):
                threat = True
            if any(k in value.lower() for k in ('拿到了', '源核脱槽', 'got the core', 'core extracted')):
                escaped = True
        elif kind == 'decision' and e['tick'] in moves:
            quiet = moves.pop(e['tick']).get('quiet', False)
            if escaped:
                assert not quiet
            elif book and threat:
                assert quiet
    assert not moves


def extract(d, arm, lines, situational=False):
    reading = d['reading']; book = arm.startswith('book'); hints = arm.endswith('hints')
    pages = reading['pages']; events = d['events']; trace = d['decision_trace']
    values = lambda key: [e['value'] for e in events if e['event'] == key]
    assert reading['arm'] == arm and reading['careful_from_manual'] == book
    assert len(pages) == (5 if book else 0) and all(f'0{i} / 05' in t for i,t in enumerate(pages,1))
    assert ('翻开手册' in values('confirmed')) == book and ('收起手册' in values('confirmed')) == book
    assert values('manual_read') == pages and reading['read_samples'] == (reading['text_samples'] if hints else 0)
    assert trace[0]['tick'] == 835 and len(trace) == d['decisions']
    if situational and hints:
        check_situational_gait(events, trace, book)
    elif book and not situational:
        assert all(t['intent'].get('quiet') for t in trace if t['intent'].get('move'))
    if not hints:
        assert not values('read_sign')
        assert not any(t.startswith(('残页：','【井壁刻文')) for t in values('dialogue'))
        for e in values('input'):
            assert e['key']=='E' and e.get('use_ring') and not e['prompt'] and not e['orders']
    delivered = sorted(set(values('dialogue'))); lines.update(delivered)
    tried = values('input'); prompts = values('prompt'); captions = values('caption'); sampled = d['path_samples']
    return dict(arm=arm, profile=d['profile'], seed=d['seed'], pages=len(pages), exposed=reading['text_samples'], read=reading['read_samples'],
                key=any(i['key'] in ('E','Q') for i in tried), sign=bool(values('read_sign')), prompt=bool(prompts), caption=bool(captions),
                read_offer=any('阅读' in t for t in prompts), read_press=any(i['key']=='E' and '阅读' in i['prompt'] for i in tried),
                moves=sum(bool(t['intent'].get('move')) for t in trace), quiet=sum(bool(t['intent'].get('move') and t['intent'].get('quiet')) for t in trace),
                steps=[s for s in STEPS if s in values('confirmed')], regions=d['regions'], delivered=delivered, meters=round(d['distance_m'],2), outcome=d['outcome'],
                path=[[round(x,2),round(z,2)] for _,x,_,z in sampled[::5]],
                pparams=d['policy_parameters'], pages_text=pages)


def main():
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('batches',nargs=4,type=Path);parser.add_argument('--out',required=True,type=Path);parser.add_argument('--sites-log',required=True,type=Path);parser.add_argument('--prior-audit',type=Path);parser.add_argument('--prior-report', type=Path, help='matching short-run HTML for the field-notes comparison');parser.add_argument('--situational-manual', action='store_true', help='manual quiet-step applies on shaft danger, not on every move');args=parser.parse_args()
    cases=[]; lines=set(catalog()); seeds=None; sources={}; matched={}; pages=[]
    for directory in args.batches:
        manifest=json.loads((directory/'batch.json').read_text('utf8')); arm=manifest['reading']; assert arm in ARMS and arm not in sources
        sources[arm]=directory.name; assert manifest['ticks']==7800 and manifest['fixture']=='strategy-light' and len(manifest['cases'])==manifest['planned']
        keys=set()
        for row in manifest['cases']:
            assert row['status']=='ok'; d=json.loads((directory/row['directory']/'report.json').read_text('utf8')); c=extract(d,arm,lines,args.situational_manual); k=(c['profile'],c['seed']);assert k not in keys; keys.add(k)
            params=c.pop('pparams'); assert params==matched.setdefault(k,params); content=c.pop('pages_text')
            if content:
                if not pages:pages=content
                assert content==pages
            cases.append(c)
        assert keys=={(profile, seed) for profile in ("cautious","curious","direct") for seed in range(1,19)}
        if seeds is None:seeds=keys
        assert seeds==keys
    assert set(sources)==set(ARMS)
    log=args.sites_log.read_text('utf8'); sites=json.loads(next(s[14:] for s in log.splitlines() if s.startswith('READING_SITES ')))
    assert 'ERROR:' not in log and len(sites)==6 and all(r['ok'] for r in sites)
    assert {(r['site'],r['enabled']) for r in sites}=={(s,read) for s in ('note','stele1','stele2') for read in (True,False)}
    audit_path=args.out.with_name('ending-audit.json')
    audit=json.loads(audit_path.read_text('utf8')) if audit_path.exists() else None
    prior=json.loads(args.prior_audit.read_text('utf8')) if args.prior_audit else None
    if prior:
        keys=lambda a: {(r['arm'],r['seed']) for r in a['rows']}
        assert audit and keys(prior)==keys(audit) and prior['ticks']==audit['ticks'] and prior['profile']==audit['profile']
    data=dict(situational=args.situational_manual,prior=prior,audit=audit,steps=STEPS,cases=cases,lines=sorted(lines),sources=sources,pages=pages,sites=sites)
    if args.prior_report:
        source = args.prior_report.read_text('utf8').split('const data=',1)[1]
        historical = json.JSONDecoder().raw_decode(source)[0]['cases']
        key = lambda c: (c['arm'], c['profile'], c['seed'])
        assert sorted(map(key,historical)) == sorted(map(key,cases))
        data['fieldNotes'] = True
        assert all(r.get('page_reticle') for r in sites)
        data['before'] = [{k:c[k] for k in ('arm','profile','seed','delivered','steps')} for c in historical]
    template=Path(__file__).with_name('reading_template.html').read_text('utf8'); args.out.parent.mkdir(parents=True,exist_ok=True)
    args.out.write_text(template.replace('/*PAYLOAD*/',json.dumps(data,ensure_ascii=False,separators=(',',':')).replace('<','\\u003c')),encoding='utf8')
    print(len(cases),'validated runs;',len(lines),'dialogues;',sources)

if __name__=='__main__':main()
