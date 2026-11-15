"""Run bounded headless Godot regressions concurrently, with isolated evidence paths."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "mcp"))
import capture_provenance as provenance
from review_refresh import start_review_watcher


def source_fingerprint() -> str:
    digest = hashlib.sha256()
    paths = [ROOT / "project.godot"]
    for folder in ("scenes", "mcp", "tools", "assets/data/test_scenarios"):
        paths.extend(path for path in (ROOT / folder).rglob("*")
                     if path.is_file() and path.suffix in {".gd", ".gdshader", ".tscn", ".json", ".yaml"})
    for path in sorted(paths):
        digest.update(path.relative_to(ROOT).as_posix().encode("utf-8"))
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def validate_jobs(manifest: dict) -> list[dict]:
    jobs = manifest.get("jobs")
    if not isinstance(jobs, list) or not jobs:
        raise ValueError("Manifest needs a nonempty jobs list")
    names: set[str] = set()
    for job in jobs:
        name = job.get("id", "")
        if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,63}", name) or name in names:
            raise ValueError("Job IDs must be unique lowercase path-safe names")
        names.add(name)
        path = provenance.project_path(job["script"], ROOT)
        if not path.is_file() or path.suffix != ".gd":
            raise ValueError("Job script must be an existing project GDScript")
        if not 1 <= float(job.get("timeout_s", 90)) <= 300:
            raise ValueError("Job timeout must be between 1 and 300 seconds")
        arguments = job.get("arguments", [])
        if not isinstance(arguments, list) or any(not isinstance(arg, str) for arg in arguments):
            raise ValueError("Job arguments must be a list of strings")
        if any(arg.startswith("--test-output") for arg in arguments):
            raise ValueError("The batch runner owns the unique job output path")
    return jobs


def run_job(job: dict, output: Path, executable: str, fixed_fps: int) -> dict:
    directory = output / job["id"]
    directory.mkdir(exist_ok=False)
    script = provenance.project_path(job["script"], ROOT)
    script_hash = hashlib.sha256(script.read_bytes()).hexdigest()
    source_before = source_fingerprint()
    command = [executable, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT),
               "--fixed-fps", str(fixed_fps), "--script", str(script), "--",
               "--test-output=" + str(directory), "--fixed-step-label=" + str(fixed_fps),
               *job.get("arguments", [])]
    started = datetime.now().astimezone().isoformat()
    before = time.monotonic()
    timed_out = False
    aborted_on_error = False
    with (directory / "stdout.log").open("w", encoding="utf-8") as log:
        process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                   creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        deadline = before + float(job.get("timeout_s", 90))
        while process.poll() is None:
            current_log = (directory / "stdout.log").read_text(encoding="utf-8-sig", errors="replace")
            if "SCRIPT ERROR" in current_log or "ERROR:" in current_log:
                aborted_on_error = True
                break
            if time.monotonic() >= deadline:
                timed_out = True
                break
            time.sleep(0.1)
        if timed_out or aborted_on_error:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
            exit_code = 124 if timed_out else 1
        else:
            exit_code = process.wait()
    wall = time.monotonic() - before
    lines = (directory / "stdout.log").read_text(encoding="utf-8-sig", errors="replace").splitlines()
    errors = [line for line in lines if "ERROR:" in line or "SCRIPT ERROR" in line]
    source_changed = hashlib.sha256(script.read_bytes()).hexdigest() != script_hash
    source_after = source_fingerprint()
    dependencies_changed = source_before != source_after
    result = {"id": job["id"], "command": command, "host_pid": process.pid,
              "started_at": started, "wall_seconds": round(wall, 4), "exit_code": exit_code,
              "timed_out": timed_out, "aborted_on_error": aborted_on_error,
              "host_errors": errors, "script_sha256": script_hash,
              "script_changed_during_run": source_changed,
              "source_scripts_sha256_before": source_before, "source_scripts_sha256_after": source_after,
              "dependencies_changed_during_run": dependencies_changed,
              "regression_ok": exit_code == 0 and not errors and not source_changed and not dependencies_changed,
              "measurement_context": "headless_fixed_step_development",
              "fixed_fps": fixed_fps, "acceptance_scored": False,
              "source_identity": provenance.project_identity(ROOT)}
    (directory / "launch-receipt.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", default="tools/testing/fast_checks.json")
    parser.add_argument("--workers", type=int, choices=range(1, 5), default=2)
    parser.add_argument("--fixed-fps", type=int, choices=range(1, 241), default=60)
    parser.add_argument("--output")
    args = parser.parse_args()
    start_review_watcher()
    manifest_path = provenance.project_path(args.manifest, ROOT)
    jobs = validate_jobs(json.loads(manifest_path.read_text(encoding="utf-8-sig")))
    output = provenance.project_path(args.output or ".runtime/parallel-checks/" + datetime.now().strftime("%Y%m%d-%H%M%S-%f"), ROOT)
    if output.exists() and any(output.iterdir()):
        parser.error("Batch output must be new or empty; existing evidence is preserved")
    output.mkdir(parents=True, exist_ok=True)
    executable = provenance.host_executable(ROOT / ".runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64.exe")
    started = time.monotonic()
    results = []
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(run_job, job, output, executable, args.fixed_fps): job["id"] for job in jobs}
        for future in as_completed(futures):
            try:
                result = future.result()
            except Exception as exc:
                result = {"id": futures[future], "regression_ok": False, "runner_error": str(exc)}
            results.append(result)
            print(json.dumps({"id": result["id"], "regression_ok": result["regression_ok"],
                              "wall_seconds": result.get("wall_seconds")}), flush=True)
    total = time.monotonic() - started
    ordered = sorted(results, key=lambda result: [job["id"] for job in jobs].index(result["id"]))
    summary = {"workers": args.workers, "fixed_fps": args.fixed_fps, "wall_seconds": round(total, 4),
               "sum_job_wall_seconds": round(sum(result.get("wall_seconds", 0) for result in results), 4),
               "manifest_sha256": hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
               "source_identity": provenance.project_identity(ROOT), "jobs": ordered,
               "measurement_context": "headless_fixed_step_development", "acceptance_scored": False,
               "regression_ok": all(result["regression_ok"] for result in results)}
    (output / "batch-result.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"output": str(output), "wall_seconds": summary["wall_seconds"],
                      "regression_ok": summary["regression_ok"]}), flush=True)
    return 0 if summary["regression_ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
