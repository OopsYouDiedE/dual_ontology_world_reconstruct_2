"""Drive one kitchen seal investigation through X11, not direct game methods.

This is a project-bound, scripted development test on a restored fixture. It
is not an independent title/new-game review, not a benchmark, and never writes
scores. It owns and verifies its Xvfb and Godot PIDs and shuts them down.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import select
import selectors
import shutil
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "mcp/evaluation"))
import common as c  # noqa: E402
from server import _goal  # noqa: E402


def stop_owned(process, identity, required):
    if process is None or process.poll() is not None:
        return
    try:
        c.inspect_process(process.pid, expected_exe=identity["executable"],
                          required=required, created=identity["create_time"])
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)
    except (ProcessLookupError, ValueError):
        # Never signal an unverified or reused process ID.
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", required=True)
    parser.add_argument("--output", required=True, help="new project-local evidence directory")
    parser.add_argument("--expected-revision", required=True)
    parser.add_argument("--max-seconds", type=int, default=150)
    args = parser.parse_args()
    root = c.assert_project()
    if ROOT.resolve() != root:
        raise RuntimeError("Runner is not located in the authorized checkout")
    snapshot = c.project_path(args.snapshot)
    c.validate_snapshot(snapshot)
    output = c.project_path(args.output)
    if output.exists():
        raise ValueError("Refusing to overwrite an existing evidence directory")
    if not 20 <= args.max_seconds <= 240:
        raise ValueError("max-seconds must be between 20 and 240")
    state = c.revision_state()
    if state["working_tree_changes"] or state["revision"] != args.expected_revision:
        raise ValueError("A clean, explicitly expected committed revision is required")
    goal, remaining = _goal()
    if remaining < args.max_seconds + 10:
        raise ValueError("Insufficient remaining goal time for a bounded run")
    xvfb_path = shutil.which("Xvfb")
    xdotool_path = shutil.which("xdotool")
    if not xvfb_path or not xdotool_path:
        raise ValueError("Xvfb and xdotool are required")
    binary = c.executable()
    output.mkdir(parents=True)
    env = c.isolated_environment(c.STATE / ("x11-" + output.name))
    env["LIBGL_ALWAYS_SOFTWARE"] = "1"
    before_fingerprint = c.source_fingerprint()
    command = [str(binary), "--path", str(root), "--audio-driver", "Dummy", "--windowed",
               "--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3",
               "--resolution", "1440x900", "--position", "0,0", "--script",
               "res://tools/test/kitchen_x11_input_probe.gd", "--", "--dv-checkpoint-auto=false",
               "--dv-save-slot=x11-seal-dev", "--dv-snapshot=" + str(snapshot),
               "--dv-probe-output=" + str(output)]
    host = xvfb = None
    host_identity = xvfb_identity = None
    xvfb_required = []
    driver_actions = []
    notices = []
    ready = None
    window = None
    clicked = False
    closed = False
    wheel_count = 0
    start = time.monotonic()
    failure = None
    exit_code = None
    with c.exclusive_run_lock(), (output / "xvfb.log").open("wb") as xvfb_log, (output / "godot.log").open("wb") as godot_log:
        read_fd, write_fd = os.pipe()
        try:
            xvfb_command = [xvfb_path, "-displayfd", str(write_fd), "-screen", "0", "1440x900x24", "-nolisten", "tcp"]
            xvfb_required = ["-displayfd", str(write_fd)]
            xvfb = subprocess.Popen(xvfb_command, cwd=root, stdin=subprocess.DEVNULL,
                                    stdout=xvfb_log, stderr=subprocess.STDOUT,
                                    pass_fds=(write_fd,), start_new_session=True)
            os.close(write_fd)
            write_fd = -1
            available, _, _ = select.select([read_fd], [], [], 10)
            if not available:
                raise RuntimeError("Xvfb failed to announce a display")
            display = os.read(read_fd, 128).decode("ascii").strip()
            if not display.isdecimal():
                raise RuntimeError("Xvfb returned an invalid display")
            xvfb_identity = c.inspect_process(xvfb.pid, expected_exe=xvfb_path, required=xvfb_required)
            env["DISPLAY"] = ":" + display
            host = subprocess.Popen(command, cwd=root, env=env, stdin=subprocess.DEVNULL,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    start_new_session=True, bufsize=0)
            host_identity = c.inspect_process(host.pid, expected_exe=binary,
                                              required=["--path", str(root), "--script", command[command.index("--script") + 1]])

            def xdo(*arguments):
                cmd = [xdotool_path, *map(str, arguments)]
                child = subprocess.Popen(cmd, cwd=root, env=env, stdin=subprocess.DEVNULL,
                                         stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                stdout, stderr = child.communicate(timeout=8)
                record = {"pid": child.pid, "command": cmd, "exit_code": child.returncode,
                          "stdout": stdout.decode("utf-8", "replace").strip(),
                          "stderr": stderr.decode("utf-8", "replace").strip(),
                          "elapsed_seconds": round(time.monotonic() - start, 3)}
                driver_actions.append(record)
                if child.returncode:
                    raise RuntimeError("xdotool command failed: " + repr(record))
                return record["stdout"]

            def maybe_click(view):
                nonlocal window, clicked, wheel_count
                if clicked:
                    return
                if window is None:
                    matches = [line for line in xdo("search", "--onlyvisible", "--pid", host.pid).splitlines() if line.isdecimal()]
                    if len(matches) != 1:
                        raise RuntimeError("Expected exactly one visible window owned by the verified Godot PID: " + repr(matches))
                    window = matches[0]
                    owner = xdo("getwindowpid", window)
                    if owner != str(host.pid):
                        raise RuntimeError("X11 window PID does not match verified Godot host")
                    geometry = xdo("getwindowgeometry", "--shell", window)
                    dimensions = dict(line.split("=", 1) for line in geometry.splitlines() if "=" in line)
                    if dimensions.get("WIDTH") != "1440" or dimensions.get("HEIGHT") != "900":
                        raise RuntimeError("Unexpected window dimensions: " + geometry)
                    xdo("windowfocus", "--sync", window)
                if view.get("in_window") and view.get("pick_at_projection") == view.get("target_index"):
                    point = view["window_point"]
                    xdo("mousemove", "--window", window, round(point[0]), round(point[1]), "click", "--delay", "80", "1")
                    clicked = True
                    print("X11 clicked seal marker at", point, flush=True)
                elif wheel_count < 15:
                    # Ordinary player zoom-out input, only if the target marker is off-screen.
                    xdo("mousemove", "--window", window, "720", "450", "click", "5")
                    wheel_count += 1
                    print("X11 zoom-out", wheel_count, "marker", view.get("window_point"), flush=True)
                else:
                    raise RuntimeError("Seal marker remained outside the window after player zoom input")

            selector = selectors.DefaultSelector()
            os.set_blocking(host.stdout.fileno(), False)
            selector.register(host.stdout, selectors.EVENT_READ)
            buffer = b""
            deadline = start + args.max_seconds
            while time.monotonic() < deadline:
                for key, _ in selector.select(timeout=1):
                    data = os.read(key.fileobj.fileno(), 65536)
                    if not data:
                        selector.unregister(key.fileobj)
                        continue
                    godot_log.write(data)
                    godot_log.flush()
                    buffer += data
                    while b"\n" in buffer:
                        line, buffer = buffer.split(b"\n", 1)
                        text = line.decode("utf-8", "replace").strip()
                        if text.startswith("PROBE_"):
                            print(text[:1000], flush=True)
                        if text.startswith("PROBE_READY "):
                            ready = json.loads(text.removeprefix("PROBE_READY "))
                            if ready.get("pid") != host.pid or not ready.get("guards_pass") or ready.get("time_scale") != 1.0:
                                raise RuntimeError("Host identity, input guards, or unscaled time check failed")
                            c.provenance.validate_source(ready["source_identity"], c.provenance.project_identity(root),
                                                         pid=host.pid, executable=binary,
                                                         launch_scene="res://scenes/dual_world/DualWorldMain.tscn")
                            maybe_click(ready["view"])
                        elif text.startswith("PROBE_VIEW ") and ready is not None:
                            maybe_click(json.loads(text.removeprefix("PROBE_VIEW ")))
                        elif text.startswith("PROBE_READY_CLOSE "):
                            info = json.loads(text.removeprefix("PROBE_READY_CLOSE "))
                            if not clicked or not info.get("sampled") or info.get("camera_id") != info.get("closeup_camera_id"):
                                raise RuntimeError("Closeup does not use the original camera or has not sampled")
                            point = info["window_point"]
                            if not (0 <= point[0] < 1440 and 0 <= point[1] < 900):
                                raise RuntimeError("Close button is outside the window")
                            xdo("mousemove", "--window", window, round(point[0]), round(point[1]), "click", "--delay", "80", "1")
                            closed = True
                            print("X11 clicked close button at", point, flush=True)
                if host.poll() is not None and not selector.get_map():
                    break
            if buffer:
                godot_log.write(buffer)
            if host.poll() is None:
                raise TimeoutError("Rendered test exceeded its wall-clock deadline")
            exit_code = host.returncode
            selector.close()
        except Exception as exc:
            failure = type(exc).__name__ + ": " + str(exc)
            print("RUNNER ERROR", failure, flush=True)
        finally:
            if read_fd >= 0:
                os.close(read_fd)
            if write_fd >= 0:
                os.close(write_fd)
            if host is not None and host_identity is not None:
                stop_owned(host, host_identity, ["--path", str(root)])
            if xvfb is not None and xvfb_identity is not None:
                stop_owned(xvfb, xvfb_identity, xvfb_required)

    result_path = output / "result.json"
    result = json.loads(result_path.read_text(encoding="utf-8")) if result_path.is_file() else None
    images = []
    if result and host_identity:
        for item in result.get("captures", []):
            try:
                path = c.project_path(item["path"])
                metadata = json.loads(Path(str(path) + ".json").read_text(encoding="utf-8"))
                c.provenance.validate_source(metadata["source_identity"], c.provenance.project_identity(root),
                                             pid=host_identity["pid"], executable=binary,
                                             launch_scene="res://scenes/dual_world/DualWorldMain.tscn")
                ok = metadata.get("encoding_error") == 0 and metadata.get("image_sha256") == c.sha256(path)
                images.append({"path": str(path), "sha256": c.sha256(path), "verified": ok})
            except Exception as exc:
                images.append({"path": item.get("path"), "verified": False, "error": str(exc)})
    after = c.revision_state()
    after_fingerprint = c.source_fingerprint()
    gui = result.get("gui_mouse_events", []) if result else []
    target_index = ready.get("view", {}).get("target_index") if ready else None
    real_target_event = target_index is not None and any(
        x.get("button") == 1 and x.get("picked_index") == target_index
        and x.get("busy_item_after_handler") == target_index for x in gui)
    passed = bool(not failure and exit_code == 0 and clicked and closed and real_target_event and result
                  and result.get("status") == "evidence_recorded_after_window_input"
                  and result.get("evidence_recorded") and len(images) == 3 and all(x["verified"] for x in images)
                  and after == state and after_fingerprint == before_fingerprint)
    receipt = {"project": c.provenance.project_identity(root), "revision": state["revision"],
               "working_tree_changes": state["working_tree_changes"], "snapshot": str(snapshot),
               "snapshot_sha256": c.sha256(snapshot), "godot": host_identity, "godot_sha256": c.sha256(binary),
               "xvfb": xvfb_identity, "driver_actions": driver_actions, "window_id": window,
               "marker_click_sent": clicked, "close_click_sent": closed, "zoom_inputs": wheel_count,
               "gui_target_event_observed": real_target_event, "images": images,
               "exit_code": exit_code, "failure": failure, "elapsed_seconds": round(time.monotonic() - start, 3),
               "source_unchanged": after == state and after_fingerprint == before_fingerprint,
               "fingerprint_before": before_fingerprint, "fingerprint_after": after_fingerprint,
               "goal_deadline": goal["deadline_at"], "software_rendering": True,
               "input_method": "xdotool XTEST events on private Xvfb; no direct game interaction calls",
               "scope": "scripted restored-fixture developer regression; not natural play or independent acceptance",
               "acceptance_eligible": False, "acceptance_scored": False, "pass": passed}
    c.write_json(output / "driver-receipt.json", receipt)
    print(json.dumps({"pass": passed, "failure": failure, "exit_code": exit_code,
                      "host_pid": host_identity["pid"] if host_identity else None,
                      "evidence": result.get("evidence_recorded") if result else None,
                      "images_verified": sum(x["verified"] for x in images),
                      "receipt": str(output / "driver-receipt.json")}, ensure_ascii=False))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
