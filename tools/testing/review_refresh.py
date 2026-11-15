"""Refresh review HTML/Markdown automatically when archived evidence changes."""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from datetime import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
STATE = ROOT / ".runtime/review-export"
EXTENSIONS = {".md", ".json", ".yaml", ".yml", ".csv", ".png", ".jpg", ".jpeg", ".wav"}


@contextmanager
def watcher_lock():
    """The OS releases the lock if the watcher exits or the computer restarts."""
    STATE.mkdir(parents=True, exist_ok=True)
    stream = (STATE / "watch.lock").open("a+b")
    if stream.tell() == 0:
        stream.write(b"0")
        stream.flush()
    stream.seek(0)
    locked = False
    try:
        try:
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            locked = True
        except OSError:
            pass
        yield locked
    finally:
        if locked:
            stream.seek(0)
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl
                fcntl.flock(stream, fcntl.LOCK_UN)
        stream.close()


def source_snapshot() -> tuple:
    paths = set()
    for folder in ("artifacts/acceptance", "artifacts/references"):
        paths.update(p for p in (ROOT / folder).rglob("*") if p.suffix.lower() in EXTENSIONS)
    paths.update(ROOT / name for name in (
        "assets/data/test_scenarios/reference_manifest.json",
        "assets/data/test_scenarios/text_exemptions.json",
        "docs/采集路径修复.md", "docs/剧情重构实施状态.md", "docs/第一章可玩版本范围.md",
        "tools/testing/export_review_site.py"))
    # Asset replacements should refresh their image hashes as well as their links.
    paths.update(p for p in (ROOT / "output/imagegen").rglob("*") if p.suffix.lower() in EXTENSIONS)
    result = []
    for path in sorted(paths):
        try:
            stat = path.stat()
            if path.is_file():
                result.append((path.relative_to(ROOT).as_posix(), stat.st_size, stat.st_mtime_ns))
        except FileNotFoundError:
            pass  # A writer may atomically replace a file during this scan.
    return tuple(result)


def write_status(**values):
    data = {"pid": os.getpid(), "updated_at": datetime.now().astimezone().isoformat(timespec="seconds"), **values}
    temporary = STATE / "status.tmp"
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(STATE / "status.json")


def watch(interval: float, debounce: float) -> int:
    with watcher_lock() as acquired:
        if not acquired:
            return 0
        previous = source_snapshot()
        exported = None
        stable_since = time.monotonic()
        retry_after = 0.0
        write_status(state="waiting_for_stable_sources", source_files=len(previous))
        while True:
            current = source_snapshot()
            now = time.monotonic()
            if current != previous:
                previous, stable_since = current, now
            if current != exported and now - stable_since >= debounce and now >= retry_after:
                write_status(state="exporting", source_files=len(current))
                try:
                    result = subprocess.run(
                        [sys.executable, str(ROOT / "tools/testing/export_review_site.py")],
                        cwd=ROOT, stdin=subprocess.DEVNULL, capture_output=True, text=True,
                        encoding="utf-8", errors="replace", timeout=120,
                        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
                    print(result.stdout, end="", flush=True)
                    if result.stderr:
                        print(result.stderr, file=sys.stderr, end="", flush=True)
                    if result.returncode == 0:
                        exported = current
                        write_status(state="watching", source_files=len(current), last_export_ok=True,
                                     html=str(ROOT / "artifacts/review/index.html"),
                                     markdown=str(ROOT / "artifacts/review/评分总览.md"))
                    else:
                        retry_after = now + 10
                        write_status(state="retry_pending", last_export_ok=False, exit_code=result.returncode)
                except (OSError, subprocess.TimeoutExpired) as error:
                    retry_after = now + 10
                    write_status(state="retry_pending", last_export_ok=False, error_type=type(error).__name__)
            time.sleep(interval)


def start_review_watcher() -> None:
    """Start at most one hidden watcher for this checkout; capture continues on failure."""
    try:
        STATE.mkdir(parents=True, exist_ok=True)
        with watcher_lock() as available:
            if not available:
                return
        with (STATE / "watch.log").open("ab") as log:
            subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "--watch"], cwd=ROOT,
                             stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                             creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0), close_fds=True)
    except OSError as error:
        print("Review watcher could not start: " + type(error).__name__, file=sys.stderr)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--watch", action="store_true")
    parser.add_argument("--interval", type=float, default=2)
    parser.add_argument("--debounce", type=float, default=3)
    options = parser.parse_args()
    if options.interval < 0.2 or options.debounce < 0:
        parser.error("interval must be >=0.2 and debounce must be >=0")
    if options.watch:
        raise SystemExit(watch(options.interval, options.debounce))
    start_review_watcher()
