"""Shared project, process and immutable-run safeguards for evaluation tools."""
from __future__ import annotations

from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

import psutil
import yaml

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "mcp"))
import capture_provenance as provenance  # noqa: E402

RUNS = ROOT / "artifacts/evaluation/runs"
STATE = ROOT / ".runtime/evaluation"
VERSION = "4.7.2"
# Only explicitly investigated chapter-one transitions may be captured here.
FLOW_PRETRANSIT_FROM = "2F-cross-M"
FLOW_PRETRANSIT_TARGETS = ("1F-Shaft-Monitor", "T01")
RUN_ID = re.compile(r"eval-[0-9]{8}t[0-9]{6}-[a-f0-9]{8}")


def assert_project(expected=None):
    return provenance.assert_runtime_root(ROOT, expected)


def project_path(path):
    assert_project()
    return provenance.project_path(path, ROOT)


def run_dir(run_id):
    if not isinstance(run_id, str) or not RUN_ID.fullmatch(run_id):
        raise ValueError("Invalid evaluation run id")
    return project_path(RUNS / run_id)


def now():
    return datetime.now().astimezone().isoformat(timespec="seconds")


def parse_goal_window(text):
    """Read the already-declared, timezone-aware goal; never start a new budget."""
    pattern = r"(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\s+[+-]\d{2}:\d{2})"
    start_match = re.search(r"本\s*Goal\s*创建时间\s*[：:]\s*" + pattern, text)
    end_match = re.search(r"既定熔断检查时间为\s*" + pattern, text)
    if not start_match or not end_match:
        raise ValueError("goal.md must explicitly declare the existing goal start and cutoff, including timezone")
    started = datetime.fromisoformat(start_match.group(1))
    deadline = datetime.fromisoformat(end_match.group(1))
    seconds = deadline.timestamp() - started.timestamp()
    if started.tzinfo is None or deadline.tzinfo is None or not 0 < seconds <= 8 * 3600:
        raise ValueError("Goal window must be positive, timezone-aware and at most eight hours")
    return {"started_at": started.isoformat(), "started_epoch": started.timestamp(),
            "deadline_at": deadline.isoformat(), "deadline_epoch": deadline.timestamp()}


def documented_goal():
    assert_project()
    return parse_goal_window(project_path(ROOT / "goal.md").read_text(encoding="utf-8-sig"))


def atomic_text(path, text):
    path = project_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=".evaluation-", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        for attempt in range(20):
            try:
                os.replace(temp, path)
                break
            except PermissionError:
                if attempt == 19: raise
                time.sleep(0.025)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def write_json(path, value):
    atomic_text(path, json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n")


def write_yaml(path, value):
    atomic_text(path, yaml.safe_dump(value, allow_unicode=True, sort_keys=False))


def read_json(path):
    target = project_path(path)
    for attempt in range(20):
        try:
            return json.loads(target.read_text(encoding="utf-8-sig"))
        except PermissionError:
            if attempt == 19: raise
            time.sleep(0.025)


def sha256(path):
    digest = hashlib.sha256()
    with project_path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def git(*arguments):
    assert_project()
    return subprocess.check_output(["git", *arguments], cwd=ROOT, stdin=subprocess.DEVNULL,
                                   text=True, encoding="utf-8", errors="replace").strip()


def revision_state():
    return {"revision": git("rev-parse", "HEAD"),
            "working_tree_changes": git("status", "--porcelain", "--untracked-files=all")}


def recommended_workers():
    """Do not run two large Godot hosts together in a memory-starved container."""
    total = psutil.virtual_memory().total
    # Respect a cgroup limit when it is lower than the host's physical memory.
    for name in ("/sys/fs/cgroup/memory.max", "/sys/fs/cgroup/memory/memory.limit_in_bytes"):
        try:
            text = Path(name).read_text().strip()
            if text.isdecimal() and 0 < int(text) < total:
                total = int(text)
        except OSError:
            pass
    return {"workers": 1 if total < 3500 * 1024 * 1024 else 2,
            "memory_limit_mb": round(total / (1024 * 1024)),
            "reason": "serialize large hosts below 3500 MiB to prevent swap/OOM"}


def source_fingerprint():
    """Detect relevant source/state changes during a run, including new tool files."""
    assert_project()
    digest = hashlib.sha256()
    paths = [ROOT / "project.godot", ROOT / "goal.md"]
    for name in ("scenes", "assets", "localization", "tools/test", "tools/testing", "mcp"):
        directory = ROOT / name
        paths.extend(p for p in directory.rglob("*") if p.is_file() and
                     (name in ("assets", "localization") or p.suffix.lower() in
                      {".gd", ".gdshader", ".tscn", ".tres", ".cs", ".py", ".json", ".yaml", ".yml", ".uid"})
                     and "__pycache__" not in p.parts and "examples" not in p.parts)
    for path in sorted(paths):
        digest.update(path.relative_to(ROOT).as_posix().encode("utf-8"))
        digest.update(bytes.fromhex(sha256(path)))
    return digest.hexdigest()


def executable(value=None):
    assert_project()
    candidates = [value] if value else [
        ".runtime/godot/4.7.2/Godot_v4.7.2-stable_linux.x86_64",
        ".runtime/godot/4.7.2/Godot_v4.7.2-stable_win64.exe",
        ".runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64.exe",
    ]
    for candidate in candidates:
        path = project_path(candidate)
        if path.is_file() and os.access(path, os.X_OK):
            return path
    raise ValueError("Godot 4.7.2 executable must be installed inside this project; see mcp/evaluation/README.md")


def linux_process_token(pid):
    """Kernel boot ID and process start tick avoid WSL wall-clock drift."""
    if os.name == "nt":
        return None
    try:
        stat = Path(f"/proc/{pid}/stat").read_text(encoding="ascii")
        fields = stat[stat.rfind(")") + 2:].split()
        return {"boot_id": Path("/proc/sys/kernel/random/boot_id").read_text(encoding="ascii").strip(),
                "start_ticks": int(fields[19])}
    except (OSError, ValueError, IndexError):
        return None


def inspect_process(pid, *, expected_exe, required=(), created=None, process_token=None):
    """Check the actual live PID, executable, command line and cwd; reject PID reuse."""
    if isinstance(pid, bool) or not isinstance(pid, int) or pid <= 0:
        raise ValueError("A positive owned PID is required")
    try:
        process = psutil.Process(pid)
        token = linux_process_token(pid)
        if process_token is not None:
            if token is None or token != process_token:
                raise ValueError("PID kernel start identity differs from the launch receipt")
        elif created is not None and abs(process.create_time() - float(created)) > 0.1:
            raise ValueError("PID creation time differs from the launch receipt")
        actual_exe = Path(process.exe()).resolve()
        if actual_exe != Path(expected_exe).resolve():
            raise ValueError("PID executable differs from the launch receipt")
        # Linux may briefly expose an empty /proc cmdline immediately after exec.
        # Retry only that transient state; a nonempty mismatch is always rejected.
        command = process.cmdline()
        retry_until = time.monotonic() + 1.0
        while not command and process.is_running() and time.monotonic() < retry_until:
            time.sleep(0.01)
            command = process.cmdline()
        missing = [str(item) for item in required if str(item) not in command]
        if missing:
            raise ValueError("PID command does not match this project/run; missing=" + repr(missing) + "; observed=" + repr(command))
        if Path(process.cwd()).resolve() != ROOT:
            raise ValueError("PID working directory differs from this project")
        return {"pid": pid, "executable": str(actual_exe), "command": command,
                "cwd": str(ROOT), "create_time": process.create_time(), "process_token": token}
    except (psutil.NoSuchProcess, psutil.ZombieProcess) as error:
        raise ValueError("Owned process has already exited") from error


def validate_snapshot(path):
    import base64
    path = project_path(path)
    data = read_json(path)
    if data.get("format") != "story-checkpoint-v1" or data.get("project") != ROOT.name:
        raise ValueError("Snapshot is not a checkpoint for this project")
    payload = base64.b64decode(data.get("payload", ""), validate=True)
    if hashlib.sha256(payload).hexdigest() != data.get("sha256"):
        raise ValueError("Snapshot payload checksum mismatch")
    if not isinstance(data.get("host_pid"), int) or data["host_pid"] <= 0:
        raise ValueError("Snapshot has no originating host PID")
    return data


@contextmanager
def exclusive_run_lock():
    """Only one evaluation batch per checkout, including across MCP processes."""
    assert_project()
    STATE.mkdir(parents=True, exist_ok=True)
    with (STATE / "run.lock").open("a+b") as lock:
        if lock.tell() == 0:
            lock.write(b"0")
            lock.flush()
        lock.seek(0)
        try:
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as exc:
            raise RuntimeError("Another project evaluation is already running") from exc
        try:
            yield
        finally:
            lock.seek(0)
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(lock.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl
                fcntl.flock(lock.fileno(), fcntl.LOCK_UN)


def isolated_environment(run):
    run = project_path(run)
    env = os.environ.copy()
    for name, directory in (("XDG_DATA_HOME", "data"), ("XDG_CACHE_HOME", "cache"),
                            ("XDG_CONFIG_HOME", "config")):
        # Saves/config stay unique to the run; disposable shader cache is shared
        # inside the project to avoid duplicating tens of megabytes per run.
        target = STATE / "cache" if name == "XDG_CACHE_HOME" else run / "xdg" / directory
        target.mkdir(parents=True, exist_ok=True)
        env[name] = str(target)
    return env
