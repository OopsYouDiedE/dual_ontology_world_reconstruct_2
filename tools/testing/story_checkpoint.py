"""Launch or resume the production story with a project/PID bound interrupt checkpoint."""
from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time
import psutil

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "mcp"))
import capture_provenance as provenance


def validate_snapshot(path: Path) -> dict:
    import base64
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if value.get("format") != "story-checkpoint-v1" or value.get("project") != ROOT.name:
        raise ValueError("Snapshot project or format mismatch")
    payload = base64.b64decode(value["payload"], validate=True)
    if hashlib.sha256(payload).hexdigest() != value.get("sha256"):
        raise ValueError("Snapshot checksum mismatch")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", help="Existing checkpoint JSON inside this project")
    parser.add_argument("--output", help="New session directory, containing latest.json and launch receipt")
    parser.add_argument("--duration", type=float, default=0, help="Seconds after launch, then save and close")
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--stop", help="Request checkpoint and graceful exit for a session directory")
    args = parser.parse_args()
    provenance.assert_runtime_root(ROOT)
    if args.stop:
        directory = provenance.project_path(args.stop, ROOT)
        receipt = json.loads((directory / "launch.json").read_text(encoding="utf-8"))
        provenance.validate_source(receipt["source_identity"], provenance.project_identity(ROOT))
        if receipt.get("pid", 0) <= 0 or receipt.get("finished_at"):
            parser.error("Session is already closed or its owned PID is missing")
        process = psutil.Process(receipt["pid"])
        actual = process.cmdline()
        if Path(process.exe()).resolve() != Path(receipt["command"][0]).resolve() or "--dv-checkpoint-stop=" + str(directory / "interrupt.request") not in actual:
            parser.error("Owned host PID/executable/session identity mismatch")
        (directory / "interrupt.request").write_text(str(receipt["pid"]), encoding="ascii")
        print(json.dumps({"stop_requested": True, "pid": receipt["pid"], "directory": str(directory)}))
        return 0
    if args.duration < 0:
        parser.error("Duration must be nonnegative")
    snapshot = provenance.project_path(args.snapshot, ROOT) if args.snapshot else None
    if snapshot:
        try:
            validate_snapshot(snapshot)
        except (OSError, ValueError, KeyError):
            validate_snapshot(Path(str(snapshot) + ".previous"))
    directory = provenance.project_path(args.output or ".runtime/checkpoints/" + datetime.now().strftime("%Y%m%d-%H%M%S-%f"), ROOT)
    directory.mkdir(parents=True, exist_ok=False)
    executable = provenance.host_executable(ROOT / ".runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64.exe")
    command = [executable, "--path", str(ROOT)]
    if args.headless:
        command += ["--headless"]
    command += ["res://scenes/dual_world/DualWorldMain.tscn", "--",
                "--dv-checkpoint-output=" + str(directory / "latest.json"),
                "--dv-checkpoint-stop=" + str(directory / "interrupt.request"),
                "--dv-save-slot=checkpoint-" + directory.name]
    if snapshot:
        command.append("--dv-snapshot=" + str(snapshot))
    identity = provenance.project_identity(ROOT)
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    receipt = {"source_identity": identity, "revision": revision, "command": command,
               "snapshot": str(snapshot) if snapshot else None, "acceptance_eligible": False,
               "started_at": datetime.now().astimezone().isoformat()}
    started = time.monotonic()
    with (directory / "godot.log").open("w", encoding="utf-8") as log:
        process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                   creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        receipt["pid"] = process.pid
        (directory / "launch.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps({"started": True, "pid": process.pid, "directory": str(directory), "checkpoint": str(directory / "latest.json")}), flush=True)
        try:
            while process.poll() is None:
                if args.duration and time.monotonic() - started >= args.duration:
                    break
                time.sleep(0.05)
        except KeyboardInterrupt:
            pass
        finally:
            if process.poll() is None:
                (directory / "interrupt.request").write_text(str(process.pid), encoding="ascii")
                try:
                    process.wait(timeout=20)
                except subprocess.TimeoutExpired:
                    process.terminate()
                    process.wait(timeout=5)
                    receipt["forced_stop"] = True
    receipt.update(finished_at=datetime.now().astimezone().isoformat(), exit_code=process.returncode)
    checkpoint = directory / "latest.json"
    if checkpoint.is_file():
        metadata = validate_snapshot(checkpoint)
        if metadata["host_pid"] != process.pid:
            raise ValueError("Checkpoint PID differs from the actual owned host")
        receipt["checkpoint"] = {key: metadata[key] for key in ("host_pid", "room", "stage", "created_at", "sha256")}
    errors = [line for line in (directory / "godot.log").read_text(encoding="utf-8-sig", errors="replace").splitlines()
              if "SCRIPT ERROR" in line or "ERROR:" in line]
    receipt["errors"] = errors
    (directory / "launch.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(receipt, ensure_ascii=False), flush=True)
    return process.returncode or (1 if errors or not checkpoint.is_file() else 0)


if __name__ == "__main__":
    raise SystemExit(main())
