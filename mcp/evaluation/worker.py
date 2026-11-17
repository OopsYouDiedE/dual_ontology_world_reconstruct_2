"""Owned, bounded Godot evaluation runs with seven-dimension reports."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import math
import os
import re
from pathlib import Path
import select
import shutil
import signal
import subprocess
import sys
import threading
import time

import psutil

import common as c

sys.path.insert(0, str(c.ROOT / "tools/testing"))
import test_results  # noqa: E402

sys.path.insert(0, str(c.ROOT / "mcp/game"))
from concurrency_observer import ConcurrencyObserver  # noqa: E402

sys.path.insert(0, str(c.ROOT / "mcp/review"))
from core import Store  # noqa: E402


def survey_cases(root, segments=None):
    cases = c.read_json(root / "assets/data/test_scenarios/mainline_survey.json")
    if not isinstance(cases, list) or not cases:
        raise ValueError("Scene survey plan must contain cases")
    seen = set()
    for row in cases:
        if not isinstance(row, dict) or not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,63}", str(row.get("id", ""))):
            raise ValueError("Invalid scene survey case id")
        if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,63}", str(row.get("segment_id", ""))):
            raise ValueError("Invalid scene survey segment id")
        if row["id"] in seen or not isinstance(row.get("fixture"), dict):
            raise ValueError("Duplicate or malformed scene survey case")
        seen.add(row["id"])
    if segments is not None:
        if not isinstance(segments, list) or not segments or any(not isinstance(value, str) for value in segments):
            raise ValueError("Scene survey segments must be a nonempty list of IDs")
        known = {row["segment_id"] for row in cases}
        unknown = sorted(set(segments) - known)
        if unknown:
            raise ValueError("Unknown scene survey segment: " + ", ".join(unknown))
        cases = [row for row in cases if row["segment_id"] in set(segments)]
    return cases


def newest_fixture(root, name):
    """Select the newest valid project fixture and keep its run path in the job plan."""
    if name != "corridor-free.json":
        raise ValueError("Unsupported survey fixture")
    runs = root / "artifacts/evaluation/runs"
    candidates = sorted(runs.glob("eval-*/fixtures/fixtures/" + name), reverse=True)
    for path in candidates:
        try:
            c.validate_snapshot(path)
            return path
        except (OSError, ValueError, TypeError):
            continue
    raise ValueError("No valid generated corridor fixture exists; run the fixture generation profile first")


def planned_jobs(profile, rendered, segments=None):
    """Enumerate only lanes scheduled by this profile."""
    singles = {"room_fast": ("room-fast", "project"),
               "kitchen_click": ("kitchen-click", "kitchen_evidence"),
               "scenario": ("scenario", "project"),
               "chapter1_flow": ("chapter1-flow", "project")}
    if profile == "scene_survey":
        if not rendered:
            raise ValueError("Scene survey requires a rendered display")
        return [("survey-" + row["id"], row["segment_id"]) for row in survey_cases(c.ROOT, segments)]
    if profile in singles:
        return [singles[profile]]
    if profile != "chapter1_ui":
        raise ValueError("Unknown profile")
    lanes = [("chapter1-flow", "project"), ("fixtures", "project")]
    if rendered:
        lanes.append(("story-visual", "wake"))
    return lanes + [("special-ui", "project"), ("bedroom-fast", "wake"),
                    ("corridor-fast", "corridor"), ("kitchen-fast", "kitchen_evidence")]


def observe_concurrency(observed, processes):
    """Snapshot concurrently alive owned hosts, not queued executor tasks."""
    live = sorted((name, host.pid) for name, host in processes.items() if host.poll() is None)
    if len(live) > observed["peak_live_hosts"]:
        observed.update(peak_live_hosts=len(live),
                        witness=[{"job": name, "pid": pid} for name, pid in live],
                        observed_at=c.now())


def mark_unstarted(jobs):
    for row in jobs.values():
        if row.get("state") == "planned":
            row.update(state="blocked", detail={"reason": "lane was not started"})


def display_available(driver, env):
    """Probe a display connection in a bounded child, using the job environment."""
    variable = "WAYLAND_DISPLAY" if driver == "wayland" else "DISPLAY"
    if not env.get(variable):
        return False
    # A separate process keeps a broken display server from blocking the worker.
    probe = """import ctypes, ctypes.util, os, sys
name = sys.argv[1]
lib = ctypes.CDLL(ctypes.util.find_library('wayland-client' if name == 'wayland' else 'X11'))
open_name, close_name = (('wl_display_connect', 'wl_display_disconnect') if name == 'wayland' else ('XOpenDisplay', 'XCloseDisplay'))
connect = getattr(lib, open_name)
connect.argtypes = [ctypes.c_char_p]
connect.restype = ctypes.c_void_p
close = getattr(lib, close_name)
close.argtypes = [ctypes.c_void_p]
address = os.environ['WAYLAND_DISPLAY' if name == 'wayland' else 'DISPLAY'].encode()
handle = connect(address)
if not handle:
    sys.exit(1)
close(handle)
"""
    try:
        return subprocess.run([sys.executable, "-c", probe, driver], env=env,
                              stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, timeout=5, check=False).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


SCORE_REASONS = {
    "fluidity": "No steady-state frame-time samples were collected for this segment.",
    "text_density": "Visible dialogue and prompts were not counted and checked for English.",
    "action_sfx_integrity": "A complete animation, decal, sound and occlusion assessment was not collected.",
    "audio_loudness": "Integrated loudness and true peak were not measured for this segment.",
    "blind_narrative_match": "A blind player narrative comparison was not collected.",
    "aesthetic_similarity": "A reference image similarity assessment was not collected.",
    "narrative_flow": "An end-to-end player pacing assessment was not collected.",
}


def segment_for_job(job, row):
    segment = {"bedroom-fast": "wake", "story-visual": "wake", "corridor-fast": "corridor",
               "kitchen-fast": "kitchen_evidence", "kitchen-click": "kitchen_evidence"}.get(job)
    if job.startswith("survey-"):
        return row.get("segment_id")
    if job == "room-fast":
        detail = row.get("detail") or {}
        room = detail.get("room")
        if detail.get("controller") == "gathering":
            return "corridor"
        segment = {"R05": "wake", "B-P": "kitchen_evidence", "bedroom": "wake",
                   "corridor": "corridor", "kitchen": "kitchen_evidence"}.get(room)
    return segment


def build_test_results(state, directory, root):
    """Group observations from this run; absent measurements remain pending."""
    results = {}
    for job, row in state.get("jobs", {}).items():
        segment = segment_for_job(job, row)
        if not segment or row.get("state") in ("planned", "running") or not row.get("host_pid"):
            continue
        result = results.setdefault(segment, {"test_id": state["run_id"] + "-" + segment,
            "scores": {key: None for key in SCORE_REASONS}, "reasons": dict(SCORE_REASONS),
            "jobs": [], "evidence": []})
        result["jobs"].append(job)
        for name in ("godot.log", "launch.json", "result.json", "survey.json", "timeline.yaml"):
            path = directory / job / name
            if path.is_file() and path.resolve().is_relative_to(root.resolve()):
                result["evidence"].append(path.resolve().relative_to(root.resolve()).as_posix())
    return results


class EvaluationBlocked(Exception):
    """The test lacks prerequisites/coverage; never misreport this as a game failure."""


class Evaluation:
    def __init__(self, run_id):
        self.root = c.assert_project()
        self.directory = c.run_dir(run_id)
        self.run_id = run_id
        self.launch = self._wait_for_launch()
        if self.launch["run_id"] != run_id or self.launch["worker_pid"] != os.getpid():
            raise ValueError("Worker PID/run does not match launch receipt")
        c.inspect_process(os.getpid(), expected_exe=self.launch["worker_executable"],
                          required=[str(Path(__file__).resolve()), run_id],
                          created=self.launch["worker_create_time"], process_token=self.launch.get("worker_process_token"))
        self.godot = c.executable(self.launch["godot"])
        self.env = c.isolated_environment(self.directory)
        self.stop = threading.Event()
        self.lock = threading.Lock()
        self.procs = {}
        self.xvfb = None
        self.started = time.monotonic()
        self.goal_deadline_epoch = float(self.launch["goal_deadline_epoch"])
        remaining = max(0.0, self.goal_deadline_epoch - time.time())
        self.deadline = self.started + min(float(self.launch["deadline_seconds"]), remaining, 28800.0)
        self.store = Store(self.root, server_script=__file__)
        state = c.revision_state()
        self.survey_cases = {"survey-" + row["id"]: row for row in survey_cases(self.root, self.launch.get("segments"))} if self.launch["profile"] == "scene_survey" else {}
        self.state = {"schema_version": 1, "run_id": run_id, "state": "running",
                      "profile": self.launch["profile"], "rendered": self.launch["rendered"],
                      "resource_policy": self.launch["resource_policy"],
                      "started_at": c.now(), "worker_pid": os.getpid(),
                      "source_identity": c.provenance.project_identity(self.root),
                      "revision": state["revision"],
                      "working_tree_changes": state["working_tree_changes"],
                      "source_fingerprint_before": c.source_fingerprint(),
                      "godot": str(self.godot), "godot_sha256": c.sha256(self.godot),
                      "acceptance_eligible": False, "acceptance_scored": False,
                      "notice": "测试结果记录测量范围、证据与七项评分。",
                      "jobs": {job: {"state": "planned", "segment_id": segment}
                               for job, segment in planned_jobs(self.launch["profile"], self.launch["rendered"], self.launch.get("segments"))},
                      "observed_concurrency": {"peak_live_hosts": 0, "witness": []}, "errors": []}
        self._publish()

    def _wait_for_launch(self):
        path = self.directory / "launch.json"
        end = time.monotonic() + 10
        while time.monotonic() < end:
            if path.is_file():
                return c.read_json(path)
            time.sleep(0.05)
        raise RuntimeError("Worker launch receipt was not published")

    def _publish(self):
        c.write_json(self.directory / "status.json", self.state)
        c.write_yaml(self.directory / "report.yaml", self.state)
        if self.state.get("profile") == "scene_survey":
            survey = test_results.latest_scene_survey(self.root)
            if survey and survey["id"] == self.run_id:
                payload = test_results.scene_survey_payload(self.root, survey)
                encoded = json.dumps(payload, ensure_ascii=False).replace("<", "\\u003c").replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")
                c.atomic_text(self.root / "artifacts/review/scene-survey.js", "window.SCENE_SURVEY=" + encoded + ";\n")

    def update(self, job, **values):
        with self.lock:
            self.state["jobs"].setdefault(job, {}).update(values)
            self._publish()

    def progress(self, job, segment, phase, result, evidence=()):
        work = self.run_id + "-" + job
        event = work + "-" + phase
        return self.store.progress_append(event_id=event, work_id=work, segment_id=segment,
            kind="check", summary=("启动" if phase == "start" else "完成") + "测试：" + job,
            result=result, revision=self.state["revision"], evidence=list(evidence))

    def confirm(self, job, segment):
        work = self.run_id + "-" + job
        self.store.progress_append(event_id=work + "-complete", work_id=work, segment_id=segment,
            kind="complete", summary="完成测试记录：" + job,
            result="测试已结束；结果和证据已记录。",
            revision=self.state["revision"], evidence=[],
            related_event_ids=[work + "-start", work + "-end"])

    def cancelled(self):
        return (self.stop.is_set() or (self.directory / "cancel.request").exists()
                or time.monotonic() >= self.deadline or time.time() >= self.goal_deadline_epoch)

    def display(self):
        if not self.launch["rendered"]:
            return
        if os.name == "nt":
            self.state["display"] = {"driver": "Windows", "owned": False,
                                     "software_rendering": self.env.get("LIBGL_ALWAYS_SOFTWARE") == "1"}
            self._publish()
            return
        if sys.platform != "linux":
            raise RuntimeError("Rendered evaluation supports Windows and Linux")
        for driver, variable in (("wayland", "WAYLAND_DISPLAY"), ("x11", "DISPLAY")):
            if display_available(driver, self.env):
                self.state["display"] = {"driver": driver, "display": self.env[variable],
                                         "owned": False, "probe": "display connection",
                                         "software_rendering": self.env.get("LIBGL_ALWAYS_SOFTWARE") == "1"}
                self._publish()
                return
            # A stale Wayland address must not override a working X11 display.
            if driver == "wayland":
                self.env.pop("WAYLAND_DISPLAY", None)
        executable = shutil.which("Xvfb")
        if not executable:
            raise RuntimeError("Rendered evaluation requires a working display or Xvfb")
        read_fd, write_fd = os.pipe()
        log = (self.directory / "xvfb.log").open("wb")
        try:
            command = [executable, "-displayfd", str(write_fd), "-screen", "0", "1440x900x24", "-nolisten", "tcp"]
            self.xvfb = subprocess.Popen(command, cwd=self.root, stdin=subprocess.DEVNULL, stdout=log,
                                         stderr=subprocess.STDOUT, pass_fds=(write_fd,), start_new_session=True)
            self.state["display_process"] = c.inspect_process(self.xvfb.pid, expected_exe=executable,
                                                               required=["-displayfd", str(write_fd)])
            os.close(write_fd)
            write_fd = -1
            ready, _, _ = select.select([read_fd], [], [], 10)
            if not ready:
                raise RuntimeError("Xvfb did not provide a display")
            display = os.read(read_fd, 128).decode("ascii").strip()
            if not display.isdecimal():
                raise RuntimeError("Xvfb returned an invalid display")
            self.env["DISPLAY"] = ":" + display
            # Software rendering is a development fallback, never a real-GPU benchmark.
            self.env.setdefault("LIBGL_ALWAYS_SOFTWARE", "1")
            self.state["display"] = {"driver": "Xvfb", "display": self.env["DISPLAY"], "owned": True,
                                     "software_rendering": self.env.get("LIBGL_ALWAYS_SOFTWARE") == "1"}
            self._publish()
        finally:
            if write_fd >= 0:
                os.close(write_fd)
            os.close(read_fd)
            log.close()

    def _job_spec(self, job):
        directory = self.directory / job
        fixture = self.directory / "fixtures" / "fixtures"
        user = ["--dv-checkpoint-auto=false", "--dv-save-slot=" + self.run_id + "-" + job]
        # Rendered batches must keep every Godot job on the real display driver,
        # including fixture and flow jobs; a mixed batch silently used Dummy.
        headless = not self.launch.get("rendered", False)
        timeout = 180
        output = None
        if job == "chapter1-flow":
            script = "res://tools/test/chapter1_flow.gd"
            target = self.launch.get("pretransit_to", c.FLOW_PRETRANSIT_TARGETS[0])
            if target not in c.FLOW_PRETRANSIT_TARGETS:
                raise ValueError("Unsupported pretransit diagnostic destination")
            user += ["--dv-stall-snapshot=" + str(directory / "stall-snapshot.json"),
                     "--dv-pretransit-snapshot=" + str(directory / "pretransit-snapshot.json"),
                     "--dv-pretransit-from=" + c.FLOW_PRETRANSIT_FROM, "--dv-pretransit-to=" + target]
            if self.launch.get("motion_time_scale") is not None:
                user.append("--dv-motion-scale=" + str(self.launch["motion_time_scale"]))
            timeout = 210
        elif job == "fixtures":
            script = "res://tools/test/checkpoint_roundtrip.gd"
            user.append("--dv-fixture-root=" + str(self.directory / "fixtures"))
        elif job in ("bedroom-fast", "corridor-fast", "kitchen-fast", "room-fast"):
            script = "res://tools/test/room_fast_check.gd"
            name = {"bedroom-fast": "opening-free.json", "corridor-fast": "corridor-free.json",
                    "kitchen-fast": "kitchen-free.json"}.get(job)
            snapshot = fixture / name if name else c.project_path(self.launch["snapshot_path"])
            c.validate_snapshot(snapshot)
            output = directory / "result.json"
            user += ["--dv-snapshot=" + str(snapshot), "--dv-fast-output=" + str(output)]
            timeout = 60
        elif job == "kitchen-click":
            script = "res://tools/test/kitchen_click_diagnostic.gd"
            snapshot = c.project_path(self.launch["snapshot_path"])
            c.validate_snapshot(snapshot)
            output = directory / "result.json"
            user += ["--dv-snapshot=" + str(snapshot), "--dv-kitchen-click-output=" + str(output),
                     "--dv-interaction-id=" + (self.launch.get("interaction_id") or "e_b_seal")]
            timeout = 60
        elif job == "special-ui":
            script = "res://tools/test/exploration_ui_contract.gd"
            snapshot = fixture / "opening-free.json"
            c.validate_snapshot(snapshot)
            output = directory / "result.json"
            headless = not self.launch["rendered"]
            user += ["--dv-snapshot=" + str(snapshot), "--dv-ui-output=" + str(output),
                     "--dv-ui-capture=" + ("true" if not headless else "false")]
            timeout = 150
        elif job.startswith("survey-"):
            script = "res://tools/test/mainline_survey.gd"
            headless = False
            case = dict(self.survey_cases[job])
            if case.get("controller") == "corridor" and case.get("snapshot"):
                snapshot = newest_fixture(self.root, "corridor-free.json")
                case["snapshot"] = str(snapshot)
            plan = directory / "plan.json"
            c.write_json(plan, [case])
            user += ["--survey-plan=" + str(plan), "--survey-output=" + str(directory)]
            output = directory / "survey.json"
            timeout = 150
        elif job == "story-visual":
            script = "res://tools/test/mainline_survey.gd"
            headless = False
            cases = c.read_json(self.root / "assets/data/test_scenarios/mainline_survey.json")
            cases = [row for row in cases if row.get("segment_id") == "wake"][:1]
            if not cases:
                raise ValueError("Wake scenario missing from survey plan")
            plan = directory / "plan.json"
            c.write_json(plan, cases)
            user += ["--survey-plan=" + str(plan), "--survey-output=" + str(directory)]
            output = directory / "survey.json"
            timeout = 150
        elif job == "scenario":
            script = None
            headless = not self.launch["rendered"]
            scenario = c.project_path(self.launch["scenario_path"])
            if not scenario.is_file() or scenario.suffix.lower() not in (".yaml", ".yml", ".json"):
                raise ValueError("Scenario must be an existing project-local YAML/JSON file")
            user += ["--scenario=" + str(scenario), "--test-output=" + str(directory),
                     "--test-duration=4", "--test-auto-quit=true",
                     "--monitor-visible=" + ("true" if self.launch.get("monitor_visible", False) else "false")]
            output = directory / "timeline.yaml"
            timeout = 90
        else:
            raise ValueError("Unknown evaluation job")
        command = [str(self.godot), "--path", str(self.root), "--language", "en", "--audio-driver", "Dummy"]
        if job.startswith("survey-"):
            command += ["--max-fps", "60"]
        if headless:
            command += ["--headless", "--fixed-fps", "60"]
        if script:
            command += ["--script", script]
        else:
            command += ["res://tools/testing/StoryTest.tscn"]
        command += ["--", *user]
        return command, headless, timeout, output

    def _terminate(self, process, children):
        """Only terminate subprocess objects/descendants created by this worker."""
        owned = []
        for pid, (child, created) in list(children.items()):
            try:
                if abs(psutil.Process(pid).create_time() - created) < .1:
                    child.terminate()
                    owned.append(child)
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
        if process.poll() is None:
            process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
        _, alive = psutil.wait_procs(owned, timeout=3)
        for child in alive:
            try:
                child.kill()
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
        psutil.wait_procs(alive, timeout=3)

    def _validate_output(self, job, output, pid, rendered):
        detail = {}
        if job == "chapter1-flow":
            text = (self.directory / job / "godot.log").read_text(encoding="utf-8", errors="replace")
            if "RESULT fails=0" not in text:
                raise ValueError("Chapter diagnostic did not emit its successful terminal marker")
            detail["scope"] = "加速流程，使用直接补证和答案提交"
            detail.update(self._chapter_snapshot_evidence(pid))
        elif job == "fixtures":
            for name in ("opening-free.json", "corridor-free.json", "kitchen-free.json"):
                snapshot = self.directory / "fixtures/fixtures" / name
                meta = c.validate_snapshot(snapshot)
                if meta["host_pid"] != pid:
                    raise ValueError("Fixture checkpoint PID differs from its actual host")
            detail["snapshot_count"] = 3
        elif job.endswith("-fast"):
            data = c.read_json(output)
            c.provenance.validate_source(data.get("project"), c.provenance.project_identity(self.root),
                                         pid=pid, executable=self.godot)
            detail = {"room": data.get("room"), "controller": data.get("controller"), "total_elapsed_ms": data.get("total_elapsed_ms"),
                      "under_5_seconds": data.get("under_5_seconds"), "path_pass": data.get("path_pass"),
                      "ray_pass": data.get("ray_pass"), "interaction_count": len(data.get("interactions", [])),
                      "reported_pass": data.get("pass"), "errors": data.get("errors", [])}
            if not data.get("pass") or not data.get("under_5_seconds"):
                raise ValueError("Room fast-check reported a failed path/ray/actor/time condition: " + json.dumps(detail, ensure_ascii=False))
        elif job == "kitchen-click":
            data = c.read_json(output)
            c.provenance.validate_source(data.get("source_identity"), c.provenance.project_identity(self.root),
                                         pid=pid, executable=self.godot)
            if data.get("format") != "kitchen-click-diagnostic-v1" or data.get("acceptance_eligible") is not False:
                raise ValueError("Kitchen diagnostic is not explicitly identified as development-only")
            approach = data.get("approach", {})
            if not isinstance(approach, dict) or not all(isinstance(v, bool) for v in
                    (data.get("guards_pass"), data.get("handler_accepted"), approach.get("ok"))):
                raise ValueError("Kitchen diagnostic omitted its boolean observations")
            detail = {"interaction_id": data.get("interaction_id"), "guards_pass": data["guards_pass"],
                      "approach_ok": approach["ok"], "handler_accepted": data["handler_accepted"],
                      "reason": data.get("reason"), "scope": "direct handler decision, not a mouse click or completed interaction"}
            if not all((data["guards_pass"], approach["ok"], data["handler_accepted"])):
                raise EvaluationBlocked("Kitchen direct-handler diagnostic did not start: " + str(data.get("reason", "unknown")))
        elif job == "special-ui":
            data = c.read_json(output)
            c.provenance.validate_source(data.get("source_identity"), c.provenance.project_identity(self.root),
                                         pid=pid, executable=self.godot)
            detail = {"reported_pass": data.get("pass"), "check_count": len(data.get("checks", [])),
                      "failures": data.get("failures", []), "book_waits": data.get("book_waits", []),
                      "blocked_at": data.get("blocked_at", "")}
            if not data.get("pass"):
                raise ValueError("UI contract failed: " + json.dumps(detail, ensure_ascii=False))
        elif job.startswith("survey-"):
            data = c.read_json(output)
            c.provenance.validate_source(data.get("source_identity"), c.provenance.project_identity(self.root),
                                         pid=pid, executable=self.godot)
            cases = data.get("cases", [])
            expected = self.survey_cases[job]
            if len(cases) != 1 or cases[0].get("id") != expected["id"]:
                raise ValueError("Scene result does not match requested case")
            row = cases[0]
            detail = {"case_id": row["id"], "segment_id": row["segment_id"],
                      "room": row.get("initial", {}).get("room"), "reached_phase": "completed",
                      "issues": row.get("issues", []), "actions": row.get("actions", []),
                      "initial": row.get("initial"), "final": row.get("final"),
                      "snapshot_restored": row.get("snapshot_restored")}
        elif job == "story-visual":
            data = c.read_json(output)
            c.provenance.validate_source(data.get("source_identity"), c.provenance.project_identity(self.root),
                                         pid=pid, executable=self.godot)
            cases = data.get("cases", [])
            detail = {"cases": len(cases), "issues": [v for row in cases for v in row.get("issues", [])]}
            if not cases or detail["issues"]:
                raise ValueError("Story survey incomplete or reported issues: " + json.dumps(detail, ensure_ascii=False))
        elif job == "scenario":
            import yaml
            data = yaml.safe_load(output.read_text(encoding="utf-8"))
            meta = data.get("metadata", {})
            c.provenance.validate_source(meta.get("source_identity"), c.provenance.project_identity(self.root),
                                         pid=pid, executable=self.godot)
            if meta.get("mock") is not True:
                raise ValueError("Scenario recording is not explicitly identified as mock")
            detail = {"mock": True, "monitor_visible": meta.get("monitor_visible"),
                      "audio_capture_buffer_s": meta.get("audio_capture_buffer_s"),
                      "samples": len(data.get("timeline", []))}
        images = []
        for image in sorted((self.directory / job).rglob("*.png")):
            verified = c.provenance.verify_image(image, self.root, allow_fixture=True)
            c.provenance.validate_source(verified["source_identity"], c.provenance.project_identity(self.root),
                                         pid=pid, executable=self.godot)
            images.append(str(image.relative_to(self.root)))
        if rendered and (job in ("story-visual", "special-ui") or job.startswith("survey-")) and not images:
            raise ValueError("Rendered capture produced no provenance-verified images")
        detail["images"] = images
        return detail

    def _chapter_snapshot_evidence(self, pid):
        """Check development snapshots against their host, payload and capture marker.

        The envelope is not a substitute for restoring and checking the embedded
        Godot state. In particular, a pre-transit capture is explicitly caused
        by the diagnostic calling the production watcher before the next frame.
        """
        directory = self.directory / "chapter1-flow"
        detail = {}
        stall = directory / "stall-snapshot.json"
        if stall.is_file():
            checkpoint = c.validate_snapshot(stall)
            if checkpoint.get("host_pid") != pid or checkpoint.get("acceptance_eligible") is not False:
                raise ValueError("Stall checkpoint PID or development-only flag mismatch")
            detail["stall_snapshot"] = str(stall.relative_to(self.root))
            detail["stall_snapshot_sha256"] = c.sha256(stall)
        log = directory / "godot.log"
        prefix = "[DEV DIAGNOSTIC] PRETRANSIT_SNAPSHOT "
        markers = [line[len(prefix):] for line in log.read_text(encoding="utf-8", errors="replace").splitlines()
                   if line.startswith(prefix)] if log.is_file() else []
        pretransit = directory / "pretransit-snapshot.json"
        if len(markers) > 1:
            raise ValueError("Multiple pretransit capture markers")
        if not markers:
            if pretransit.is_file():
                raise ValueError("Pretransit checkpoint lacks its capture marker")
            return detail
        observation = json.loads(markers[0])
        if not isinstance(observation, dict) or observation.get("acceptance_eligible") is not False:
            raise ValueError("Invalid development-only pretransit capture marker")
        if observation.get("saved") is False and not pretransit.is_file():
            detail["pretransit_observation"] = observation
            return detail
        coordinates = observation.get("detective")
        path_points = observation.get("path_points")
        target = getattr(self, "launch", {}).get("pretransit_to", c.FLOW_PRETRANSIT_TARGETS[0])
        if target not in c.FLOW_PRETRANSIT_TARGETS:
            raise ValueError("Unsupported pretransit diagnostic destination")
        if (observation.get("saved") is not True or observation.get("planned") is not True
                or observation.get("detective_camera_rules_unchanged") is not True
                or observation.get("explicit_watcher_before_next_frame") is not True
                or observation.get("from") != c.FLOW_PRETRANSIT_FROM or observation.get("to") != target
                or not isinstance(observation.get("path"), str)
                or c.project_path(observation["path"]) != c.project_path(pretransit)
                or not isinstance(path_points, int) or isinstance(path_points, bool) or path_points < 2
                or not isinstance(coordinates, list) or len(coordinates) != 2
                or any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) for v in coordinates)):
            raise ValueError("Pretransit capture marker is inconsistent")
        if not pretransit.is_file():
            raise ValueError("Pretransit capture marker names a missing checkpoint")
        checkpoint = c.validate_snapshot(pretransit)
        if (checkpoint.get("host_pid") != pid or checkpoint.get("acceptance_eligible") is not False
                or checkpoint.get("room") != target or checkpoint.get("stage") != "room"):
            raise ValueError("Pretransit checkpoint PID, room, stage or development-only flag mismatch")
        detail["pretransit_snapshot"] = str(pretransit.relative_to(self.root))
        detail["pretransit_snapshot_sha256"] = c.sha256(pretransit)
        detail["pretransit_observation"] = observation
        return detail

    def _failure_evidence(self, job, pid):
        """Expose real failing checks, but never promote unverified files."""
        directory = self.directory / job
        detail = {}
        log = directory / "godot.log"
        if log.is_file():
            lines = log.read_text(encoding="utf-8", errors="replace").splitlines()
            detail["failure_lines"] = [line for line in lines if line.startswith(("FAIL ", "FAIL  ", "RESULT fails=", "[DEV DIAGNOSTIC] STALLED_NO_PROGRESS", "[DEV DIAGNOSTIC] PRETRANSIT_SNAPSHOT"))][-20:]
        if job == "chapter1-flow":
            detail.update(self._chapter_snapshot_evidence(pid))
        result = directory / "result.json"
        if result.is_file():
            data = c.read_json(result)
            source = data.get("project") if job.endswith("-fast") else data.get("source_identity")
            c.provenance.validate_source(source, c.provenance.project_identity(self.root), pid=pid, executable=self.godot)
            detail.update({k: data[k] for k in ("pass", "status", "room", "controller", "total_elapsed_ms", "under_5_seconds", "path_pass", "ray_pass", "navigation_agent_pass", "blocking_reasons", "errors", "failures", "book_waits", "blocked_at", "interaction_id", "guards_pass", "approach", "handler_accepted", "reason", "input_method", "before", "after_immediate") if k in data})
            if "checks" in data:
                detail["check_count"] = len(data["checks"])
            if "interactions" in data:
                def failed(row):
                    ray = row.get("ray", {})
                    snapshot_ray = row.get("snapshot_interaction", {}).get("ray", {})
                    return (row.get("path_pass") is False or (ray.get("applicable") and ray.get("pass") is False)
                            or (snapshot_ray.get("applicable") and snapshot_ray.get("pass") is False))
                detail["interaction_count"] = len(data["interactions"])
                detail["failed_interactions"] = [{"id": row.get("id"), "path_pass": row.get("path_pass"),
                    "ray_pass": row.get("ray", {}).get("pass"),
                    "snapshot_ray_pass": row.get("snapshot_interaction", {}).get("ray", {}).get("pass")}
                    for row in data["interactions"] if failed(row)]
        images = []
        for image in sorted(directory.rglob("*.png")):
            verified = c.provenance.verify_image(image, self.root, allow_fixture=True)
            c.provenance.validate_source(verified["source_identity"], c.provenance.project_identity(self.root),
                                         pid=pid, executable=self.godot)
            images.append(str(image.relative_to(self.root)))
        detail["images"] = images
        return detail

    def run_job(self, job, segment="project"):
        directory = self.directory / job
        directory.mkdir(parents=True, exist_ok=True)
        start_event = False
        process = None
        observer = None
        children = {}
        tick = time.monotonic()
        self.update(job, state="starting", segment_id=segment, started_at=c.now())
        try:
            self.progress(job, segment, "start", "测试进行中。")
            start_event = True
            if self.cancelled():
                raise InterruptedError("Evaluation cancelled or eight-hour deadline reached")
            command, headless, timeout, output = self._job_spec(job)
            with (directory / "godot.log").open("w", encoding="utf-8") as log:
                process = subprocess.Popen(command, cwd=self.root, env=self.env, stdin=subprocess.DEVNULL,
                                           stdout=log, stderr=subprocess.STDOUT, start_new_session=(os.name != "nt"))
                observer = ConcurrencyObserver(process.pid)
                observer.start()
                identity = c.inspect_process(process.pid, expected_exe=self.godot,
                                             required=["--path", str(self.root)])
                with self.lock:
                    self.procs[job] = process
                    observe_concurrency(self.state["observed_concurrency"], self.procs)
                self.update(job, state="running", host_pid=process.pid, process=identity,
                            command=command, headless=headless, timeout_seconds=timeout)
                c.write_json(directory / "launch.json", {"source_identity": c.provenance.project_identity(self.root),
                    "host_pid": process.pid, "process": identity, "command": command,
                    "revision": self.state["revision"], "acceptance_eligible": False})
                timeout_at = min(self.deadline, time.monotonic() + timeout)
                while process.poll() is None:
                    try:
                        for child in psutil.Process(process.pid).children(recursive=True):
                            if child.pid not in children:
                                children[child.pid] = (child, child.create_time())
                    except psutil.NoSuchProcess:
                        pass
                    if self.cancelled() or time.monotonic() >= timeout_at:
                        self._terminate(process, children)
                        raise TimeoutError("cancelled/deadline" if self.cancelled() else "job timeout")
                    time.sleep(.12)
                code = process.wait()
            # Child audio workers get a short normal finalization window.
            _, remaining = psutil.wait_procs([child for child, _ in children.values()], timeout=8)
            if remaining:
                for child in remaining:
                    try: child.terminate()
                    except (psutil.NoSuchProcess, psutil.AccessDenied): pass
                psutil.wait_procs(remaining, timeout=3)
            text = (directory / "godot.log").read_text(encoding="utf-8", errors="replace")
            errors = [line for line in text.splitlines() if line.startswith(("ERROR:", "SCRIPT ERROR:"))]
            if output is not None and output.is_file() and job.endswith("-fast"):
                blocked = c.read_json(output)
                if blocked.get("status") == "blocked":
                    c.provenance.validate_source(blocked.get("project"), c.provenance.project_identity(self.root),
                                                 pid=process.pid, executable=self.godot)
                    raise EvaluationBlocked("; ".join(blocked.get("blocking_reasons", ["Room check coverage incomplete"])))
            if code != 0 or errors:
                raise RuntimeError("Godot exit=%s, errors=%s" % (code, errors[:12]))
            detail = self._validate_output(job, output, process.pid, not headless)
            if job.startswith("survey-") and detail.get("issues"):
                verdict = "failed"
                message = "Scene survey reported incomplete interactions."
            else:
                verdict = "passed"
                message = "测试通过。"
        except (Exception, KeyboardInterrupt) as error:
            if process is not None and process.poll() is None:
                self._terminate(process, children)
            verdict = "cancelled" if self.cancelled() else ("blocked" if isinstance(error, EvaluationBlocked) else "failed")
            message = type(error).__name__ + ": " + str(error)
            detail = {"error": message}
            if job.startswith("survey-"):
                case = self.survey_cases[job]
                detail.update(case_id=case["id"], segment_id=case["segment_id"],
                              room=case["fixture"].get("room"), reached_phase="startup",
                              stalled=isinstance(error, TimeoutError))
                # The incremental marker survives a killed host and identifies
                # the precise last observed operation when the script provides it.
                marker = directory / case["id"] / "progress.json"
                if marker.is_file():
                    try:
                        progress = c.read_json(marker)
                        if isinstance(progress, dict):
                            detail["progress"] = progress
                            detail["reached_phase"] = progress.get("phase", "unknown")
                    except (OSError, ValueError):
                        detail["progress_error"] = "Unreadable incremental progress marker"
            if process is not None:
                try:
                    detail.update(self._failure_evidence(job, process.pid))
                except Exception as validation_error:
                    detail["evidence_validation_error"] = type(validation_error).__name__ + ": " + str(validation_error)
        finally:
            if observer is not None:
                try:
                    detail["concurrency_observation_path"] = str(observer.stop(directory))
                except (OSError, RuntimeError) as observation_error:
                    detail["concurrency_observation_error"] = str(observation_error)
            with self.lock:
                self.procs.pop(job, None)
        elapsed = round(time.monotonic() - tick, 3)
        self.update(job, state=verdict, ended_at=c.now(), wall_seconds=elapsed, detail=detail,
                    exit_code=process.returncode if process else None)
        evidence = []
        for path in (directory / "godot.log", directory / "launch.json", directory / "result.json", directory / "survey.json", directory / "timeline.yaml"):
            if path.is_file(): evidence.append(str(path.relative_to(self.root)))
        # Only validated snapshots and image files enter the immutable ledger.
        for name in ("stall_snapshot", "pretransit_snapshot"):
            if detail.get(name):
                evidence.append(detail[name])
        evidence += detail.get("images", [])
        if start_event:
            try:
                self.progress(job, segment, "end", message, evidence)
                self.confirm(job, segment)
            except Exception as error:
                self.update(job, ledger_error=str(error))
        return verdict == "passed"

    def publish_test_results(self):
        source_changed = self.state["source_changed_during_run"]
        current = c.revision_state()
        source_changed = source_changed or current["revision"] != self.state["revision"] or c.source_fingerprint() != self.state["source_fingerprint_after"]
        results = {}
        if source_changed:
            with self.lock:
                self.state["test_results_publication_error"] = "Source changed during or after the run; scores retain their original run provenance."
                self._publish()
        else:
            try:
                if self.state.get("profile") == "scene_survey":
                    # The collector reads this already-finalized status and uses only
                    # this run's validated frame/audio data and source identities.
                    testing_dir = str(self.root / "tools/testing")
                    if testing_dir not in sys.path:
                        sys.path.insert(0, testing_dir)
                    from scene_survey_scores import collect
                    collected = collect(self.directory)
                    if collected["source_revision"] != self.state["revision"] or collected["run_id"] != self.state["run_id"]:
                        raise ValueError("Scene score source revision or run does not match evaluation")
                    score_file = self.directory / "scene-scores.json"
                    c.write_json(score_file, collected)
                    score_evidence = score_file.relative_to(self.root).as_posix()
                    mutable_status = (self.directory / "status.json").relative_to(self.root).as_posix()
                    for segment, group in collected["segments"].items():
                        # Status is rewritten while publishing; hash immutable scene
                        # scores and source evidence instead of the mutable status.
                        evidence = [item for item in group["evidence"] if item != mutable_status]
                        evidence = list(dict.fromkeys([score_evidence, *evidence]))
                        results[segment] = {"test_id": self.state["run_id"] + "-" + segment,
                                            "scores": group["scores"], "reasons": group["reasons"],
                                            "status": group.get("status", "complete"), "jobs": ["survey-" + item for item in group["case_ids"]],
                                            "evidence": evidence}
                else:
                    results = build_test_results(self.state, self.directory, self.root)
                with self.lock:
                    self.state["test_results"] = results
                    self._publish()
                for segment, result in results.items():
                    try:
                        self.store.add_scores(trajectory_id=segment, test_id=result["test_id"],
                                              scores=result["scores"], reasons=result["reasons"], evidence=result["evidence"],
                                              status=result.get("status", "complete"))
                    except Exception as error:
                        with self.lock:
                            result["publication_error"] = type(error).__name__ + ": " + str(error)
                            self._publish()
            except Exception as error:
                with self.lock:
                    self.state["test_results_publication_error"] = type(error).__name__ + ": " + str(error)
                    self._publish()
        try:
            self.store.flush(full_render=True)
        except Exception as error:
            with self.lock:
                self.state["report_error"] = type(error).__name__ + ": " + str(error)
                self._publish()

    def run(self):
        with c.exclusive_run_lock():
            try:
                self.display()
                profile = self.launch["profile"]
                if profile == "room_fast":
                    self.run_job("room-fast", "project")
                elif profile == "kitchen_click":
                    self.run_job("kitchen-click", "kitchen_evidence")
                elif profile == "scenario":
                    self.run_job("scenario", "project")
                elif profile == "chapter1_flow":
                    # This focused lane is never sufficient for the slow-run gate.
                    self.run_job("chapter1-flow", "project")
                elif profile == "scene_survey":
                    with ThreadPoolExecutor(max_workers=min(3, self.launch["resource_policy"]["workers"]), thread_name_prefix="scene-survey") as pool:
                        futures = [pool.submit(self.run_job, job, segment) for job, segment in planned_jobs(profile, True, self.launch.get("segments"))]
                        for future in as_completed(futures):
                            future.result()
                elif profile == "chapter1_ui":
                    # Mainline starts first. Queue UI in parallel on capable hosts;
                    # serialize the same lanes on a low-memory host to avoid swap.
                    with ThreadPoolExecutor(max_workers=self.launch["resource_policy"]["workers"], thread_name_prefix="evaluation") as pool:
                        story = pool.submit(self.run_job, "chapter1-flow", "project")
                        fixture = pool.submit(self.run_job, "fixtures", "project")
                        fixture_ok = fixture.result()
                        if fixture_ok and not self.cancelled():
                            work = []
                            if self.launch["rendered"]:
                                work.append(pool.submit(self.run_job, "story-visual", "wake"))
                            work.append(pool.submit(self.run_job, "special-ui", "project"))
                            for job, segment in (("bedroom-fast", "wake"), ("corridor-fast", "corridor"),
                                                 ("kitchen-fast", "kitchen_evidence")):
                                work.append(pool.submit(self.run_job, job, segment))
                            for future in as_completed(work):
                                future.result()
                        else:
                            for job, _ in planned_jobs("chapter1_ui", self.launch["rendered"])[2:]:
                                self.update(job, state="blocked", detail={"reason": "fixture generation failed or was cancelled"})
                        story.result()
                else:
                    raise ValueError("Unknown profile")
            finally:
                self.stop.set()
                if self.xvfb and self.xvfb.poll() is None:
                    self.xvfb.terminate()
                    try: self.xvfb.wait(timeout=5)
                    except subprocess.TimeoutExpired: self.xvfb.kill(); self.xvfb.wait(timeout=5)
                after = c.source_fingerprint()
                git_after = c.revision_state()
                with self.lock:
                    self.state["source_fingerprint_after"] = after
                    self.state["revision_after"] = git_after["revision"]
                    self.state["working_tree_changes_after"] = git_after["working_tree_changes"]
                    # Live reports are tracked generated outputs and change during
                    # every run. The source fingerprint covers executable inputs;
                    # retain full git status separately for audit.
                    self.state["source_changed_during_run"] = (after != self.state["source_fingerprint_before"]
                        or git_after["revision"] != self.state["revision"])
                    self.state["ended_at"] = c.now()
                    self.state["wall_seconds"] = round(time.monotonic() - self.started, 3)
                    mark_unstarted(self.state["jobs"])
                    states = [row.get("state") for row in self.state["jobs"].values()]
                    self.state["state"] = "completed" if states and all(x == "passed" for x in states) and not self.state["source_changed_during_run"] else "blocked"
                    self.state["acceptance_eligible"] = False
                    self.state["acceptance_scored"] = False
                    self._publish()
                try:
                    self.publish_test_results()
                except Exception as error:
                    with self.lock:
                        self.state["report_error"] = type(error).__name__ + ": " + str(error)
                        self._publish()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_id")
    args = parser.parse_args()
    evaluation = Evaluation(args.run_id)
    def stop_handler(*_): evaluation.stop.set()
    signal.signal(signal.SIGTERM, stop_handler)
    signal.signal(signal.SIGINT, stop_handler)
    try:
        evaluation.run()
    except Exception as error:
        with evaluation.lock:
            evaluation.state["state"] = "blocked"
            evaluation.state["errors"].append(type(error).__name__ + ": " + str(error))
            evaluation.state["ended_at"] = c.now()
            evaluation._publish()
        return 1
    return 0 if evaluation.state["state"] == "completed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
