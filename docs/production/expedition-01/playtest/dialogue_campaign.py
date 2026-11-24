"""Foreground, resumable dialogue sampling on the original WalkTest campaign grid."""
import argparse
from contextlib import closing
import json
import math
import msvcrt
import os
from pathlib import Path
import runpy
import sqlite3
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[4]
CAM = runpy.run_path(str(ROOT / 'tools/expedition/walk_campaign.py'))
CASES = CAM['CASES']
RUNTIME = ROOT / '.runtime'
PREFIX = 'dialogue-campaign'
SCHEMA = '''
CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS attempts(
    attempt_id INTEGER PRIMARY KEY, case_id INTEGER NOT NULL, parameters TEXT NOT NULL,
    command TEXT NOT NULL, started REAL NOT NULL, seconds REAL NOT NULL, exit_code INTEGER,
    status TEXT NOT NULL, policy TEXT, witness TEXT, terminal_signal_tick INTEGER,
    death_receipt TEXT, failure_reason TEXT, route_state TEXT NOT NULL,
    route_header TEXT, route_ticks INTEGER, physics_hz INTEGER,
    event_count INTEGER, dialogue_count INTEGER, diagnostics TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS by_case ON attempts(case_id, attempt_id);
CREATE TABLE IF NOT EXISTS events(
    attempt_id INTEGER NOT NULL REFERENCES attempts(attempt_id), ordinal INTEGER NOT NULL,
    tick INTEGER NOT NULL, kind TEXT NOT NULL, value TEXT NOT NULL,
    x REAL NOT NULL, y REAL NOT NULL, z REAL NOT NULL, percent REAL, payload TEXT NOT NULL,
    PRIMARY KEY(attempt_id, ordinal));
CREATE VIEW IF NOT EXISTS runs AS
  SELECT a.* FROM attempts a JOIN
  (SELECT case_id,max(attempt_id) AS id FROM attempts GROUP BY case_id) b ON a.attempt_id=b.id;
CREATE VIEW IF NOT EXISTS dialogue AS
  SELECT a.case_id,a.status,a.route_ticks,a.physics_hz,e.* FROM events e
  JOIN attempts a USING(attempt_id) WHERE e.kind='dialogue';
'''


def dump(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':'))


def validate_route(path, expected):
    with path.open(encoding='utf-8-sig') as f:
        route = json.load(f)
    if route['policy_parameters'] != expected or route['seed'] != expected['seed']:
        raise ValueError('route policy mismatch')
    ticks, hz = route['tick'], route['physics_hz']
    if type(ticks) is not int or ticks < 0 or hz != 60:
        raise ValueError('invalid route timebase')
    if route['outcome'] not in ('completed', 'failed', 'interrupted') or not isinstance(route['failure_reason'], str):
        raise ValueError('invalid route outcome')
    rows = []
    events = route.pop('events')
    if not isinstance(events, list):
        raise ValueError('invalid event stream')
    previous = -1
    for i, event in enumerate(events):
        tick, kind, value, feet = (event[k] for k in ('tick', 'event', 'value', 'feet'))
        if (type(tick) is not int or not previous <= tick <= ticks or tick < 0 or
                not isinstance(kind, str) or not isinstance(value, str) or
                not isinstance(feet, list) or len(feet) != 3 or
                not all(type(x) in (int, float) and math.isfinite(x) for x in feet)):
            raise ValueError(f'invalid event at ordinal {i}')
        rows.append((i, tick, kind, value, *feet, 100 * tick / ticks if ticks else None, dump(event)))
        previous = tick
    for k in ('path_samples', 'hale_path_samples'):
        route.pop(k, None)
    return route, rows


def sample(case_id, scratch, timeout):
    case = CASES[case_id - 1]
    a, l, c, r, s, t = case
    expected = dict(approach=a, loadout=l, crossing=c, arrival_radius_m=r / 100,
                    stair_radius_m=s / 100, extra_settle_ticks=t, fixture='full', seed=1)
    cmd = CAM['command'](case, scratch)
    profile = scratch / 'profile'
    profile.mkdir()
    env = dict(os.environ, APPDATA=str(profile), LOCALAPPDATA=str(profile), XDG_DATA_HOME=str(profile))
    started, clock = time.time(), time.monotonic()
    errors, signals, status = [], {}, None
    log = scratch / 'godot.log'
    with log.open('wb') as out:
        try:
            proc = subprocess.run(cmd, cwd=ROOT, env=env, creationflags=CAM['FLAGS'],
                                  stdin=subprocess.DEVNULL, stdout=out, stderr=subprocess.STDOUT,
                                  timeout=timeout)
            code = proc.returncode
        except subprocess.TimeoutExpired:
            code, status = 124, 'infra'
            errors.append(f'{timeout:g}s timeout')
        except OSError as e:
            code, status = None, 'infra'
            errors.append(str(e))
    script_error = engine_error = False
    for line in log.open(encoding='utf-8', errors='replace'):
        line = line.strip()
        if CAM['ISSUE'].match(line):
            script_error |= line.startswith(('SCRIPT ERROR:', 'SHADER ERROR:'))
            engine_error |= line.startswith('ERROR:')
            if len(errors) < 12:
                errors.append(line[:500])
        for key in ('WALK_POLICY ', 'WALK_WITNESS ', 'WALK_DEATH ', 'ROUTE_TICKS ', 'PASS: A1 to evacuation;'):
            if line.startswith(key):
                signals[key] = line[len(key):]
    policy, death, terminal = None, None, None
    try:
        policy = json.loads(signals.get('WALK_POLICY ', 'null'))
        if 'WALK_DEATH ' in signals:
            d = json.loads(signals['WALK_DEATH '])
            if type(d['tick']) is not int or d['tick'] <= 0 or not isinstance(d['fail_reason'], str) or not d['fail_reason']:
                raise ValueError('invalid death signal')
            death, terminal = d, d['tick']
        elif 'ROUTE_TICKS ' in signals:
            terminal = int(signals['ROUTE_TICKS '])
    except (ValueError, KeyError, TypeError) as e:
        errors.append(f'invalid stdout receipt: {e}')
    header, rows, route_state = None, [], 'missing'
    try:
        header, rows = validate_route(scratch / 'route.json', expected)
        route_state = 'valid'
    except FileNotFoundError:
        errors.append('route.json missing')
    except (OSError, ValueError, KeyError, TypeError, OverflowError) as e:
        route_state = 'invalid'
        errors.append(f'route.json invalid: {e}')
    outcome = header['outcome'] if header else None
    witness = signals.get('WALK_WITNESS ')
    reason = death['fail_reason'] if death else (header['failure_reason'] if header else '')
    if policy != expected:
        errors.append('missing or mismatched stdout policy receipt')
    if death and header and (outcome != 'failed' or reason != header['failure_reason']):
        errors.append('route and stdout death receipts differ; retaining both')
    if death or (outcome == 'failed' and reason):
        status = 'gameplay_death'
    elif status or policy != expected or code not in (0, 1):
        status = 'infra'
    elif script_error:
        status = 'script_error'
    elif code == 0 and engine_error:
        status = 'engine_error'
    elif (code == 0 and outcome == 'completed' and terminal and terminal > 0
          and witness == str(a == 'witness').lower() and 'PASS: A1 to evacuation;' in signals):
        status = 'pass'
    else:
        status = 'assertion_failure' if code == 1 else 'incomplete'
    receipt = (case_id, dump(case), dump(cmd), started, time.monotonic() - clock, code, status,
               dump(policy), witness, terminal, dump(death), reason, route_state,
               dump(header), header['tick'] if header else None, header['physics_hz'] if header else None,
               len(rows) if header else None, sum(x[2] == 'dialogue' for x in rows) if header else None, dump(errors))
    return receipt, rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('run', 'report'))
    parser.add_argument('--name', default=PREFIX, help='isolated .runtime directory, e.g. dialogue-campaign-smoke')
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--limit', type=int, default=4, help='maximum new attempts (default 4)')
    group.add_argument('--all', action='store_true', help='run all outstanding cases in foreground')
    parser.add_argument('--retry-incomplete', action='store_true', help='append retries for missing/invalid traces and infrastructure errors')
    parser.add_argument('--timeout', type=float, default=180)
    args = parser.parse_args()
    if not (args.name == PREFIX or args.name.startswith(PREFIX + '-')) or not all(c.isascii() and (c.isalnum() or c == '-') for c in args.name):
        parser.error('--name must be dialogue-campaign or dialogue-campaign-<suffix>')
    if not 1 <= args.limit <= len(CASES) or not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error('invalid limit or timeout')
    base = RUNTIME / args.name
    if base.resolve() != RUNTIME.resolve() / args.name:
        parser.error('output directory must not resolve outside its own isolated path')
    path = base / 'dialogue.sqlite3'
    if args.action == 'report':
        with closing(sqlite3.connect(path.as_uri() + '?mode=ro', uri=True)) as db:
            for row in db.execute('SELECT status,route_state,count(*),sum(event_count),sum(dialogue_count) FROM runs GROUP BY 1,2'):
                print(row)
            print(f"{db.execute('SELECT count(*) FROM runs').fetchone()[0]}/{len(CASES)} cases; "
                  f"{db.execute('SELECT count(*) FROM attempts').fetchone()[0]} total attempts; {path}")
        return
    base.mkdir(parents=True, exist_ok=True)
    with (base / 'owner.lock').open('a+b') as lock:
        try:
            msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError:
            raise SystemExit(f'Another sampler owns {base}') from None
        with closing(sqlite3.connect(path)) as db:
            db.execute('PRAGMA foreign_keys=ON')
            db.execute('PRAGMA synchronous=FULL')
            db.executescript(SCHEMA)
            stamp = CAM['source_stamp']()
            with db:
                for k, v in dict(plan=CAM['PLAN'], source=stamp, schema='1').items():
                    db.execute('INSERT OR IGNORE INTO meta VALUES (?,?)', (k, v))
                    if db.execute('SELECT value FROM meta WHERE key=?', (k,)).fetchone()[0] != v:
                        raise SystemExit(f'{k} changed; use a fresh --name or restore the original baseline')
            seen = {i: (s, r) for i, s, r in db.execute('SELECT case_id,status,route_state FROM runs')}
            pending = [i for i in range(1, len(CASES) + 1) if i not in seen or
                       (args.retry_incomplete and (seen[i][1] != 'valid' or seen[i][0] in
                                                   ('infra', 'engine_error', 'script_error', 'incomplete')))]
            failures = 0
            for i in pending[:len(CASES) if args.all else args.limit]:
                with tempfile.TemporaryDirectory(prefix=f'case-{i}-', dir=base) as tmp:
                    receipt, rows = sample(i, Path(tmp), args.timeout)
                    if CAM['source_stamp']() != stamp:
                        raise SystemExit('Source drift detected; current attempt not recorded; earlier receipts intact')
                    with db:
                        attempt = db.execute('INSERT INTO attempts VALUES (NULL,' + ','.join('?' * len(receipt)) + ')', receipt).lastrowid
                        db.executemany('INSERT INTO events VALUES (?,?,?,?,?,?,?,?,?,?)', ((attempt, *row) for row in rows))
                    print(f'{i}/{len(CASES)} {receipt[6]} route={receipt[12]} events={receipt[16]} dialogue={receipt[17]} reason={receipt[11]}', flush=True)
                    failures = failures + 1 if receipt[12] != 'valid' or receipt[6] in ('infra', 'script_error', 'engine_error', 'incomplete') else 0
                    if failures >= 4:
                        raise SystemExit('Four consecutive incomplete/infrastructure attempts; inspect receipts before retrying')
            print(path)


if __name__ == '__main__':
    main()
