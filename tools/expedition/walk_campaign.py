"""Resumable, full-scene Expedition WalkTest campaign (Windows)."""
import argparse
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
import ctypes as ct
from ctypes import wintypes as wt
import hashlib
import itertools
import json
import msvcrt
import os
from pathlib import Path
import random
import re
import sqlite3
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / '.runtime' / 'walk-campaign-v2'
EXE = ROOT / '.runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe'
SCRIPT = 'res://scenes/expedition_01/WalkTest.gd'
APPROACH = {'witness': [], 'skip': ['--skip-window'], 'transit': ['--transit-only']}
LOADOUT = {'both': [], 'clock': ['--clock-only'], 'oil': ['--oil-only'], 'neither': ['--south']}
ISSUE = re.compile(r'^\s*(?:(?:SCRIPT |SHADER )?ERROR:|FAIL[: ])')
FLAGS = subprocess.CREATE_NO_WINDOW


def design():
    grid = []
    for a, l in itertools.product(APPROACH, LOADOUT):
        for c, r, s, t in itertools.product(
            ('north', 'self', 'south') if a != 'transit' else ('self', 'south'),
            range(8, 17), range(96, 111, 2), range(116, 161, 4) if a != 'transit' else (None,),
        ):
            grid.append((a, l, c, r, s, t))
    smoke = [('witness', 'both', 'north', 12, 102, 116),
             ('skip', 'clock', 'self', 11, 104, 128),
             ('transit', 'oil', 'south', 13, 100, None),
             ('witness', 'neither', 'south', 12, 102, 116)]
    assert len(set(grid)) == len(grid) == 21312 and set(smoke) <= set(grid)
    remaining = sorted(set(grid) - set(smoke))
    random.Random(72836).shuffle(remaining)
    return smoke + remaining


CASES = design()
PLAN = hashlib.sha256(json.dumps(CASES, separators=(',', ':')).encode()).hexdigest()


def command(case, replay=None):
    a, l, c, r, s, t = case
    cmd = [str(EXE), '--headless', '--audio-driver', 'Dummy', '--fixed-fps', '60',
           '--path', str(ROOT), '--script', SCRIPT, '--', '--walk-compact',
           *APPROACH[a], *LOADOUT[l], f'--crossing={c}', f'--arrival-radius={r/100:.2f}',
           f'--stair-radius={s/100:.2f}']
    if t is not None:
        cmd.append(f'--settle-ticks={t}')
    if replay:
        cmd += [f'--route-output={replay / "route.json"}', f'--walk-trace={replay / "archive.json"}']
    return cmd


def contain_workers(cpus):
    """Limit inherited CPU affinity; a Windows job kills owned children on supervisor exit."""
    k = ct.WinDLL('kernel32', use_last_error=True)

    def api(name, result, *args):
        f = getattr(k, name)
        f.restype, f.argtypes = result, args
        return f

    handle, dword, size = wt.HANDLE, wt.DWORD, ct.c_size_t
    proc = api('GetCurrentProcess', handle)()
    mask, system = size(), size()
    get_mask = api('GetProcessAffinityMask', wt.BOOL, handle, ct.POINTER(size), ct.POINTER(size))
    set_mask = api('SetProcessAffinityMask', wt.BOOL, handle, size)
    if not get_mask(proc, ct.byref(mask), ct.byref(system)):
        raise ct.WinError(ct.get_last_error())
    bits = [1 << i for i in range(ct.sizeof(size) * 8) if mask.value & (1 << i)]
    if not set_mask(proc, sum(bits[:cpus])):
        raise ct.WinError(ct.get_last_error())

    class Basic(ct.Structure):
        _fields_ = [('process_time', ct.c_int64), ('job_time', ct.c_int64), ('flags', dword),
                    ('min_ws', size), ('max_ws', size), ('active', dword), ('affinity', size),
                    ('priority', dword), ('scheduling', dword)]

    class Extended(ct.Structure):
        _fields_ = [('basic', Basic), ('io', ct.c_uint64 * 6), ('memory', size * 4)]

    job = api('CreateJobObjectW', handle, ct.c_void_p, wt.LPCWSTR)(None, None)
    info = Extended()
    info.basic.flags = 0x2000  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
    configure = api('SetInformationJobObject', wt.BOOL, handle, ct.c_int, ct.c_void_p, dword)
    assign = api('AssignProcessToJobObject', wt.BOOL, handle, handle)
    if not job or not configure(job, 9, ct.byref(info), ct.sizeof(info)) or not assign(job, proc):
        raise ct.WinError(ct.get_last_error())
    # Keep the non-inheritable handle open for the entire supervisor lifetime.


def source_stamp():
    """Detect persistent edits/additions/deletions in the live, Git-visible worktree."""
    files = subprocess.check_output(
        ['git', 'ls-files', '-z', '-c', '-o', '--exclude-standard'], cwd=ROOT, creationflags=FLAGS,
    ).split(b'\0')
    digest = hashlib.sha256()
    for name in sorted(set(files) - {b''}):
        if name.startswith(b'docs/') or name.lower().endswith(b'.md'):
            continue
        try:
            stat = (ROOT / os.fsdecode(name)).stat()
            stamp = f'{stat.st_size}:{stat.st_mtime_ns}:{stat.st_ino}'.encode()
        except FileNotFoundError:
            stamp = b'missing'
        digest.update(name + b'\0' + stamp + b'\0')
    exe = EXE.stat()
    digest.update(f'{exe.st_size}:{exe.st_mtime_ns}:{exe.st_ino}'.encode())
    return digest.hexdigest()


def run_case(i, case):
    start = time.monotonic()
    # Consume logs in memory; retain at most eight short actionable diagnostics.
    errors = []
    signals = {}
    script_error = False
    engine_error = False
    env = os.environ.copy()
    profile = BASE / 'profiles' / threading.current_thread().name
    profile.mkdir(parents=True, exist_ok=True)
    for key in ('APPDATA', 'LOCALAPPDATA'):
        env[key] = str(profile)
    with subprocess.Popen(command(case), cwd=ROOT, env=env, creationflags=FLAGS,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT) as proc:
        def drain():
            nonlocal script_error, engine_error
            for raw in iter(lambda: proc.stdout.readline(8192), b''):
                line = raw.decode('utf-8', 'replace').strip()
                if ISSUE.match(line):
                    script_error |= line.startswith(('SCRIPT ERROR:', 'SHADER ERROR:'))
                    engine_error |= line.startswith('ERROR:') and not (' at: ' in line)
                    if len(errors) < 8:
                        errors.append(line[:400])
                for prefix in ('WALK_POLICY ', 'WALK_WITNESS ', 'WALK_DEATH ', 'ROUTE_TICKS ', 'PASS: A1 to evacuation;'):
                    if line.startswith(prefix):
                        signals[prefix] = line[len(prefix):][:1024]

        reader = threading.Thread(target=drain)
        reader.start()
        try:
            code = proc.wait(timeout=180)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
            code = 124
            errors.append('180 s case timeout')
        finally:
            reader.join()
    a, l, c, r, s, t = case
    expected = dict(approach=a, loadout=l, crossing=c, arrival_radius_m=r/100,
                    stair_radius_m=s/100, extra_settle_ticks=t, fixture='full', seed=1)
    try:
        policy_ok = json.loads(signals.get('WALK_POLICY ', 'null')) == expected
        ticks = int(signals.get('ROUTE_TICKS ', '0'))
    except ValueError:
        policy_ok, ticks = False, 0
    if not policy_ok:
        errors.append('missing or mismatched full-scene policy receipt')
    if code == 0 and (ticks <= 0 or 'PASS: A1 to evacuation;' not in signals or
                      signals.get('WALK_WITNESS ') != str(a == 'witness').lower()):
        errors.append('missing completion or mismatched B2 witness evidence')
    reason = ''
    try:
        death = json.loads(signals.get('WALK_DEATH ', 'null'))
        if death is not None:
            if not (isinstance(death['fail_reason'], str) and death['fail_reason']
                    and type(death['tick']) is int and death['tick'] > 0):
                raise ValueError('invalid death marker payload')
            reason = death['fail_reason'][:400]
            ticks = death['tick']
    except (ValueError, TypeError, KeyError):
        errors.append('invalid WALK_DEATH receipt')
    if script_error:
        status = 'script_error'
    elif code == 124 or not policy_ok or code not in (0, 1):
        status = 'infra'
    elif reason:
        status = 'gameplay_death'
    elif code == 0:
        status = 'engine_error' if engine_error else 'assertion_failure' if errors else 'pass'
    else:
        status = 'assertion_failure'
    return (i, status, code, ticks, reason, time.monotonic() - start, time.time(),
            json.dumps(errors, ensure_ascii=False))


def connect():
    db = sqlite3.connect(BASE / 'results.sqlite3', timeout=15)
    db.execute('PRAGMA synchronous=FULL')
    db.execute('CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)')
    db.execute('''CREATE TABLE IF NOT EXISTS results (id INTEGER PRIMARY KEY, status TEXT,
               code INTEGER, ticks INTEGER, reason TEXT, seconds REAL, finished REAL, errors TEXT)''')
    old = db.execute("SELECT value FROM meta WHERE key='plan'").fetchone()
    if old and old[0] != PLAN:
        db.close()
        raise SystemExit('Campaign grid changed; use a new campaign directory/version.')
    return db


def run(args):
    with (BASE / 'owner.lock').open('a+b') as lock:
        try:
            msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError:
            raise SystemExit('Campaign already running; use report or stop.')
        contain_workers(args.workers)
        if not EXE.is_file():
            raise SystemExit(f'Godot missing: {EXE}')
        stop = BASE / 'stop'
        stop.unlink(missing_ok=True)
        with connect() as db:
            source = source_stamp()
            previous = db.execute("SELECT value FROM meta WHERE key='source'").fetchone()
            if previous and previous[0] != source:
                raise SystemExit('Worktree differs from this campaign baseline; restore it or start a new campaign version.')
            done = {r[0] for r in db.execute('SELECT id FROM results' +
                                            (" WHERE status NOT IN ('infra','script_error','engine_error')" if args.retry_infra else ''))}
            pending = (i for i in range(1, len(CASES)+1) if i not in done)
            if args.limit:
                pending = itertools.islice(pending, args.limit)
            started = time.time()
            db.executemany('INSERT OR REPLACE INTO meta VALUES (?,?)',
                           [('pid', str(os.getpid())), ('started', str(started)),
                            ('workers', str(args.workers)), ('plan', PLAN), ('source', source)])
            db.commit()
            with ThreadPoolExecutor(max_workers=args.workers, thread_name_prefix='slot') as pool:
                active = set()
                bad = 0
                drift = False

                def fill():
                    while len(active) < args.workers and not stop.exists() and bad < 4:
                        i = next(pending, None)
                        if i is None:
                            break
                        active.add(pool.submit(run_case, i, CASES[i-1]))

                fill()
                while active:
                    finished, active = wait(active, return_when=FIRST_COMPLETED)
                    if drift or source_stamp() != source:
                        drift = True
                        continue  # Discard uncommitted results and let owned children drain.
                    for future in finished:
                        row = future.result()
                        db.execute('INSERT OR REPLACE INTO results VALUES (?,?,?,?,?,?,?,?)', row)
                        db.commit()
                        bad = bad + 1 if row[1] in ('infra', 'script_error', 'engine_error') else 0
                    fill()
            db.execute("DELETE FROM meta WHERE key='pid'")
            db.commit()
            if drift:
                raise SystemExit('Source drift detected; discarded uncommitted cases. Restore the baseline or start a new campaign version.')
            if bad >= 4:
                raise SystemExit('Stopped after consecutive infrastructure failures; inspect report and resume with --retry-infra.')


def report():
    with connect() as db:
        counts = dict(db.execute('SELECT status,count(*) FROM results GROUP BY status'))
        meta = dict(db.execute('SELECT key,value FROM meta'))
        remaining = len(CASES) - sum(counts.values())
        live = False
        with (BASE / 'owner.lock').open('a+b') as lock:
            try:
                msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
            except OSError:
                live = True
        print(f'{len(CASES)-remaining}/{len(CASES)} recorded; {counts}; {remaining} pending; '
              + (f'active PID {meta.get("pid", "starting")}' if live else 'idle'))
        if live and 'started' in meta:
            elapsed = time.time() - float(meta['started'])
            n = db.execute('SELECT count(*) FROM results WHERE finished >= ?', (meta['started'],)).fetchone()[0]
            if n and elapsed > 0:
                rate = n / elapsed * 3600
                print(f'{rate:.0f} cases/hour this session; ETA {remaining/rate:.1f} h for pending cases')
        for i, status, code, ticks, reason, seconds, errors in db.execute(
                'SELECT id,status,code,ticks,reason,seconds,errors FROM results ORDER BY finished DESC LIMIT 8'):
            print(f'{i}: {status}, exit={code}, {ticks} ticks, {seconds:.2f}s {CASES[i-1]} {reason} {errors}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('run', 'launch', 'resume', 'report', 'stop', 'replay'))
    parser.add_argument('case', nargs='?', type=int)
    parser.add_argument('--workers', type=int, choices=(2, 3, 4), default=2)
    parser.add_argument('--limit', type=int, choices=range(1, 101), metavar='1..100')
    parser.add_argument('--retry-infra', action='store_true',
                        help='retry infra, script_error, and engine_error rows')
    args = parser.parse_args()
    BASE.mkdir(parents=True, exist_ok=True)
    if args.action in ('launch', 'resume'):
        cmd = [sys.executable, str(Path(__file__).resolve()), 'run', '--workers', str(args.workers)]
        if args.limit:
            cmd += ['--limit', str(args.limit)]
        if args.retry_infra:
            cmd.append('--retry-infra')
        with (BASE / 'supervisor.log').open('ab') as log:
            child = subprocess.Popen(cmd, cwd=ROOT, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                     creationflags=subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_BREAKAWAY_FROM_JOB)
        print(f'Started hidden supervisor PID {child.pid}; use report to confirm ownership.')
    elif args.action == 'run':
        run(args)
    elif args.action == 'report':
        report()
    elif args.action == 'stop':
        (BASE / 'stop').touch()
        print('Stop requested; current cases will finish and checkpoint.')
    else:
        if args.case is None or not 1 <= args.case <= len(CASES):
            parser.error(f'replay requires a case ID in 1..{len(CASES)}')
        out = BASE / f'replay-{args.case}'
        out.mkdir(exist_ok=True)
        print(subprocess.list2cmdline(command(CASES[args.case-1], out)))


if __name__ == '__main__':
    main()
