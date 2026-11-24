"""Build an offline, synchronized route review from a completed structure trial."""
import argparse
import json
from pathlib import Path


def load(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def build(trial, geometry, out):
    data = {}
    for case in sorted(trial.glob('*/case.json')):
        meta, r = load(case), load(case.with_name('report.json'))
        key = f"{r['profile']}-{r['seed']}"
        assert r['physics_hz'] == 60
        def points(name):
            return [[t, round(x, 3), round(z, 3)] for t, x, _, z in r[name]]
        data.setdefault(key, {})[r['layout']] = dict(p=points('path_samples'), h=points('hale_path_samples'),
            events=[[e['tick'], e['event'], e['value'], round(e['feet'][0], 2), round(e['feet'][2], 2)] for e in r['events']],
            cross=meta['first_beyond'][0], distance=round(r['distance_m'], 2), outcome=r['outcome'])
    assert data and all(set(pair) == {'A','B'} for pair in data.values())
    walls=[]
    for shape in load(geometry)['shapes']:
        if shape['body_type'] != 'StaticBody3D' or shape['disabled'] or not shape['y_range'][0] <= 1 <= shape['y_range'][1]: continue
        for poly in shape['footprints_xz']:
            if any(-8 <= x <= 44 and -12 <= z <= 12 for x,z in poly):
                walls.append([[round(x,3),round(z,3)] for x,z in poly])
    assert walls
    out.mkdir(parents=True,exist_ok=True)
    text=Path(__file__).with_name('review.html').read_text(encoding='utf-8-sig')
    (out/'index.html').write_text(text.replace('/*DATA*/',json.dumps([data,walls],ensure_ascii=False,separators=(',',':')).replace('</','<\\/')),encoding='utf-8')


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('trial',type=Path); p.add_argument('geometry',type=Path); p.add_argument('out',type=Path)
    a=p.parse_args(); build(a.trial,a.geometry,a.out)
