"""Compact a four-arm, ten-minute ending check into a shareable audit record."""
import argparse
import json
from pathlib import Path

ARMS = {'closed-skip', 'closed-hints', 'book-skip', 'book-hints'}
STEPS = ['确认铁闸推不开', '检修升闸升起', '试板已稳定', '开始稳定通过试板', '独自走过试板', '总闸已合上', '已拔出备用源核', '已进入返回廊', '已开启气密门', '已触发撤离结局']


def build(dirs, revision, ticks=36000):
    rows = []
    for folder in dirs:
        batch = json.loads((folder/'batch.json').read_text('utf8'))
        assert batch['ticks'] == ticks and batch['fixture'] == 'strategy-light'
        for case in batch['cases']:
            assert case['status'] == 'ok'
            d = json.loads((folder/case['directory']/'report.json').read_text('utf8'))
            assert d['profile'] == 'curious' and d['reading']['arm'] == batch['reading']
            confirmed = {e['value'] for e in d['events'] if e['event'] == 'confirmed'}
            route_steps = STEPS.copy()
            route_steps.insert(route_steps.index('已进入返回廊'), '已推开应急门')
            route_steps.insert(route_steps.index('已进入返回廊'), '回廊升闸已开')
            route_steps.insert(route_steps.index('已开启气密门'), '已与 Hale 会合')
            rows.append(dict(arm=batch['reading'], seed=d['seed'], outcome=d['outcome'], reason=d['reason'], tick=d['tick'], regions=d['regions'], path=[[round(x,2),round(z,2)] for _,x,_,z in d['path_samples'][::2]],
                             delivered=sorted({e['value'] for e in d['events'] if e['event']=='dialogue'}),
                             checkpoints={s:min(e['tick'] for e in d['events'] if e['event']=='confirmed' and e['value']==s) for s in route_steps if s in confirmed}, steps=[s for s in route_steps if s in confirmed], batch=folder.name))
    assert len(rows) == 8 and {(r['arm'],r['seed']) for r in rows} == {(a,s) for a in ARMS for s in (8,12)}
    return dict(revision=revision, ticks=ticks, profile='curious', rows=rows)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('batches', type=Path, nargs=4)
    p.add_argument('--revision', required=True)
    p.add_argument('--out', required=True, type=Path)
    p.add_argument('--ticks', type=int, default=36000)
    a = p.parse_args()
    a.out.write_text(json.dumps(build(a.batches,a.revision,a.ticks), ensure_ascii=False, indent=2)+'\n',encoding='utf8')
