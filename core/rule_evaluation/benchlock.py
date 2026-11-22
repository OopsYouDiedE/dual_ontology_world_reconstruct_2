"""Freeze Sol source before drawing disjoint, unrehearsed cohorts."""
import argparse
from datetime import datetime, timezone
from hashlib import sha256
import json
from pathlib import Path
from secrets import randbits

from .physics import Rng
from .sandbox import LANE_ID, Program, SOURCE_LIMIT
from .training import TRAINING

STANDARD_DEBUG = (0, 1, 2, 3, 4, 5, 6, 7, 11, 17, 31, 42, 71, 107, 151, 991)
RETIRED_HOLDOUT = (-912032, -8856, -17, 91023, 182163, 689421, 997003, 570078119)


def new_json(path, item):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('x', encoding='utf-8', newline='\n') as f:
        json.dump(item, f, ensure_ascii=False, indent=2)
        f.write('\n')


def raw_hash(path):
    return sha256(path.read_bytes()).hexdigest()


def seal(source, meta, out):
    raw = source.read_bytes()
    if len(raw) > SOURCE_LIMIT:
        raise ValueError('source exceeds policy limit')
    policy = Program(raw.decode('utf-8-sig'))
    author = json.loads(meta.read_text(encoding='utf-8-sig'))
    if author.get('model') != 'gpt-6.2-sol' or not all(author.get(k) for k in ('revision','provenance','ability_profile')):
        raise ValueError('missing Sol policy identity or description')
    result = dict(schema=2, lane=LANE_ID, source_sha256=policy.sha256, raw_source_sha256=sha256(raw).hexdigest(),
                  frozen_at=datetime.now(timezone.utc).isoformat(),
                  training=list(TRAINING), author=author)
    new_json(out, result)
    return result


def draw(lock, out, holdout, generalization):
    frozen = json.loads(lock.read_text(encoding='utf-8-sig'))
    if frozen.get('lane') != LANE_ID or not frozen.get('source_sha256'):
        raise ValueError('expected a v2 lock before drawing')
    if not all(8 <= n <= 256 for n in (holdout,generalization)):
        raise ValueError('cohort sizes must be between 8 and 256')
    draw_key = randbits(63)
    cohorts = draw_cohorts(draw_key, holdout, generalization, frozen['source_sha256'])
    new_json(out, dict(schema=2, lock_sha256=raw_hash(lock), draw_key=draw_key, drawn_at=datetime.now(timezone.utc).isoformat(),
                      source_sha256=frozen['source_sha256'], cohorts=cohorts))
    return cohorts


def draw_cohorts(key, nh, ng, source_sha256):
    used = set(TRAINING + STANDARD_DEBUG + RETIRED_HOLDOUT)
    result = {}
    for name,n,limit in [('holdout',nh,250_000),('generalization',ng,(1<<63)-1)]:
        rng = Rng(key, f'sol-v2:{source_sha256}:{name}')
        result[name] = []
        while len(result[name]) < n:
            s = rng.randint(-limit,limit)
            if s not in used:
                result[name].append(s)
                used.add(s)
    return result


def verify(source, lock, cohorts):
    f = json.loads(lock.read_text(encoding='utf-8-sig'))
    raw = source.read_bytes()
    if f.get('schema') != 2 or f.get('lane') != LANE_ID or f.get('training') != list(TRAINING):
        raise ValueError('policy mismatches freeze lock')
    p = Program(raw.decode('utf-8-sig'))
    if p.sha256 != f.get('source_sha256') or f['author'].get('model') != 'gpt-6.2-sol':
        raise ValueError('program mismatches freeze lock')
    c = json.loads(cohorts.read_text(encoding='utf-8-sig'))
    # The first Windows cohort recorded the CRLF byte hash before Git's LF checkout.
    # Accept only the two exact line-ending encodings of the same lock contents.
    lf = lock.read_bytes().replace(b'\r\n',b'\n')
    lock_hashes = {sha256(data).hexdigest() for data in (lf,lf.replace(b'\n',b'\r\n'))}
    if c.get('schema') != 2 or c.get('lock_sha256') not in lock_hashes or c.get('source_sha256') != f['source_sha256']:
        raise ValueError('cohort manifest mismatches freeze lock')
    if datetime.fromisoformat(c['drawn_at']) < datetime.fromisoformat(f['frozen_at']):
        raise ValueError('cohort was drawn before policy freeze')
    h,g = (c['cohorts'][n] for n in ('holdout','generalization'))
    if not 8 <= len(h) <= 256 or not 8 <= len(g) <= 256 or c['cohorts'] != draw_cohorts(c['draw_key'],len(h),len(g),f['source_sha256']):
        raise ValueError('invalid or overlapping cohorts')
    return p, f, c


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='mode', required=True)
    f = sub.add_parser('freeze')
    f.add_argument('source',type=Path)
    f.add_argument('author_metadata',type=Path)
    f.add_argument('out',type=Path)
    d = sub.add_parser('draw')
    d.add_argument('lock',type=Path)
    d.add_argument('out',type=Path)
    d.add_argument('--holdout',type=int,default=16)
    d.add_argument('--generalization',type=int,default=24)
    a = p.parse_args()
    if a.mode == 'freeze':
        print(seal(a.source,a.author_metadata,a.out)['source_sha256'])
    else:
        cohorts = draw(a.lock,a.out,a.holdout,a.generalization)
        print(json.dumps({name:len(rows) for name,rows in cohorts.items()}))


if __name__ == '__main__':
    main()
