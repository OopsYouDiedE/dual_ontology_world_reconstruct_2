"""Persistent personal screening queue; freeze predictions before receiving votes."""
import argparse
import hashlib
import json
import math
import sqlite3
from pathlib import Path
from evaluate import OUTCOMES, Vote, fit, log_probs

HERE = Path(__file__).resolve().parent
DEFAULT = HERE.parents[4]/'.runtime/design-review'


def connect(root):
    root.mkdir(parents=True, exist_ok=True)
    db=sqlite3.connect(root/'review-votes.sqlite3',timeout=10)
    db.row_factory=sqlite3.Row
    db.executescript('''CREATE TABLE IF NOT EXISTS trials(id TEXT PRIMARY KEY,card TEXT NOT NULL,sha TEXT NOT NULL,
        pred TEXT,baseline TEXT,novel INTEGER,choice TEXT,note TEXT,origin TEXT,voted TEXT);
        CREATE UNIQUE INDEX IF NOT EXISTS one_pending ON trials((1)) WHERE choice IS NULL;''')
    return db


def catalog(root):
    cards=json.loads((HERE/'rounds.json').read_text(encoding='utf-8-sig'))
    for f in sorted((root/'inbox').glob('*.json')):cards.extend(json.loads(f.read_text(encoding='utf-8-sig')))
    dims={};ids=set()
    for c in cards:
        if c['id'] in ids or not c['dx'] or any(type(v) not in (float,int) or not -2<=v<=2 for v in c['dx']):raise ValueError('invalid trial '+c['id'])
        if dims.setdefault(c['scope'],len(c['dx']))!=len(c['dx']):raise ValueError('changed feature dimensions')
        ids.add(c['id']);(root/c['media']).resolve().relative_to(root.resolve())
    return cards


def history(db):
    return [(r,json.loads(r['card'])) for r in db.execute('SELECT * FROM trials ORDER BY rowid')]


def predict(c,hist):
    obs=[(r,o) for r,o in hist if c['scope']==o['scope'] and r['choice'] in OUTCOMES];novel=bool(obs) and all(o['family']!=c['family'] for _,o in obs)
    votes=[Vote('local',o['family'],tuple(o['dx']),OUTCOMES.index(r['choice'])) for r,o in obs]
    def probabilities(base):
        params=fit(votes,len(c['dx']),baseline=base) if votes else [0.]*(len(c['dx'])+1)
        return [math.exp(v) for v in log_probs(params,c['dx'])]
    return probabilities(False),probabilities(True),novel


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


REWORK = ('unclear', 'rework')


def edition(card):
    return (card['scope'], card['family'], card['contrast'], card.get('edition', 'original'))


def select(db,root):
    hist=history(db); used={c['id'] for _,c in hist}
    for r,c in hist:
        if r['choice'] is None:
            if sha(root/c['media'])!=r['sha']:raise ValueError('presented evidence changed')
            return c
    held={edition(c) for r,c in hist if r['choice'] in REWORK}
    opts=[]
    for i,c in enumerate(catalog(root)):
        if edition(c) in held or c['id'] in used or not (root/c['media']).is_file():continue
        if c.get('edition') and not c.get('gate'):continue
        if c.get('gate'):
            gate=(root/c['gate']).resolve();gate.relative_to(root.resolve())
            if not gate.is_file():continue
            evidence=json.loads(gate.read_text(encoding='utf-8-sig'))
            if evidence.get('ok') is not True:continue
            if c.get('edition') and evidence.get('sha256')!=sha(root/c['media']):continue
        p,b,n=predict(c,hist); repeat=sum(o['contrast']==c['contrast'] for _,o in hist)
        opts.append(((repeat,round(sum(v*math.log(v) for v in p),6),i),c,p,b,n))
    if not opts:return None
    _,c,p,b,n=min(opts,key=lambda x:x[0]);db.execute('INSERT INTO trials(id,card,sha,pred,baseline,novel) VALUES(?,?,?,?,?,?)',(c['id'],json.dumps(c,ensure_ascii=False),sha(root/c['media']),json.dumps(p),json.dumps(b),int(n)));return c


def vote(db,root,tid,choice,note):
    if choice not in (*OUTCOMES,'skip',*REWORK) or not isinstance(note,str) or len(note)>600:raise ValueError('invalid response')
    row=db.execute('SELECT * FROM trials WHERE id=? AND choice IS NULL',(tid,)).fetchone()
    if not row:raise ValueError('trial already closed or not presented')
    if sha(root/json.loads(row['card'])['media'])!=row['sha']:raise ValueError('evidence changed')
    db.execute("UPDATE trials SET choice=?,note=?,origin='ballot',voted=datetime('now') WHERE id=?",(choice,note,tid))


def report(db):
    hist=history(db); labels=[(r,c) for r,c in hist if r['choice'] in OUTCOMES]; checked=[r for r,c in labels if r['pred']]; novel=[r for r in checked if r['novel']]
    def loss(rows,key):return round(-sum(math.log(json.loads(r[key])[OUTCOMES.index(r['choice'])]) for r in rows)/len(rows),4) if rows else None
    readiness={}
    for scope in sorted({c['scope'] for _,c in labels}):
        blind=[r for r,c in labels if c['scope']==scope and r['novel']]
        wins=sum(json.loads(r['pred'])[OUTCOMES.index(r['choice'])]>json.loads(r['baseline'])[OUTCOMES.index(r['choice'])]+1e-9 for r in blind)
        eligible=len(blind)>=6 and wins/len(blind)>=.8 and loss(blind,'pred')<loss(blind,'baseline')
        readiness[scope]=dict(first_family_votes=len(blind),beats_baseline=wins,eligible_for_shadow_review=eligible)
    return dict(quality={k:sum(r['choice']==k for r,c in hist) for k in REWORK},readiness=readiness,labels=len(labels),prospective=len(checked),transfer=len(novel),prospective_loss=loss(checked,'pred'),baseline=loss(checked,'baseline'),transfer_loss=loss(novel,'pred'),transfer_baseline=loss(novel,'baseline'),skipped=sum(r['choice']=='skip' for r,c in hist),history=[dict(id=c['id'],question=c['question'],movie=c['media'].endswith('.mp4'),choice=r['choice'],note=r['note']) for r,c in hist if r['choice']])


def import_prior(db,root,tid,choice,note):
    if choice not in OUTCOMES:raise ValueError('expected human choice')
    c=next(c for c in catalog(root) if c['id']==tid)
    db.execute("INSERT INTO trials(id,card,sha,choice,note,origin,voted) VALUES(?,?,?,?,?,'chat',datetime('now'))",(tid,json.dumps(c,ensure_ascii=False),sha(root/c['media']),choice,note))


if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--root',type=Path,default=DEFAULT);ap.add_argument('cmd',choices=['import-prior','next','vote','status']);ap.add_argument('--id');ap.add_argument('--choice');ap.add_argument('--note',default='');a=ap.parse_args()
    with connect(a.root) as db:
        db.execute('BEGIN IMMEDIATE')
        if a.cmd=='import-prior':import_prior(db,a.root,a.id,a.choice,a.note)
        if a.cmd=='vote':vote(db,a.root,a.id,a.choice,a.note)
        print(json.dumps(select(db,a.root) if a.cmd=='next' else report(db),ensure_ascii=False,indent=2))
