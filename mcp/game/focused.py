"""Single-tester, scoped, real-render development checks (separate from blind acceptance)."""
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import threading

import runtime
from review.core import Store, atomic_write

ROOT = runtime.ROOT
SCENARIOS = ROOT / "assets/data/test_scenarios"
RUNS = {}
ROOMS = {"R05": "wake-bedroom", "B-P": "kitchen-evidence", "A-P": "service-maintenance",
         "C-P": "cross-c-window", "D-P": "cross-d-pressure", "2F-cross-M": "cross-central",
         "F01": "service-hall", "service_stair_M": "service-stair", "2F-North-Stair": "shaft-north-stair"}
WORKBENCH = {"wardrobe": "interaction", "expressions": "expressions", "building": "building",
             "lighting": "lighting", "mocap": "mocap"}
INTERACTIONS = {"kitchen-props": "kitchen-evidence", "corridor-characters": "corridor-meeting"}
DAY_ONE_TARGET = "day-one-live"
DAY_ONE_RUBRIC = {
    "completion": "Play from the production title to the Chapter 1 completion screen, then explicitly continue to Day 2 in the same host.",
    "agency": "Verify feedback and recovery when choosing the order of accessible investigations, leaving, or revisiting.",
    "state_continuity": "Track time, room, clues and unresolved gates across transitions; verify state carries over on the route taken.",
    "presentation": "Review whether dialogue, camera, actor actions and important sound cues communicate each observed transition.",
}
RUBRICS = {
    "room": {"layout": "Actors and props have usable spacing; no obstructing overlap or clipping.",
             "navigation": "Walk the intended local route and verify collisions and reachability.",
             "sightline": "Main camera exposes the relevant evidence and interaction prompt."},
    "interaction": {"input_response": "Use the visible prompt or hit target and verify the intended response.",
                    "state_change": "Verify the resulting item, dialogue or evidence state; check cancel/retry when applicable.",
                    "presentation": "Verify contact, intermediate poses and end state; review perceived sound cues when relevant."},
    "ui": {"controls": "Verify control activation and navigation, including return/cancel.",
           "layout": "Verify legibility, clipping and visual hierarchy in the rendered viewport.",
           "language": "Verify player-facing English labels, prompts and feedback on the tested path."},
    "design": {"tool_controls": "Verify the named tool controls work (toggle, frame/pose/case selection or reload as applicable).",
               "preview": "Verify the rendered preview matches the selected fixture, pose, lighting or matrix case.",
               "diagnostics": "Verify that state and diagnostic feedback match the visible result."},
    "story": {"entry": "Verify expected room, actor placement, starting beat and restored scene state.",
              "progression": "Verify the subsequent expected beat can be reached with ordinary play input.",
              "continuity": "Verify dialogue, actions and camera transitions through the observed beats."},
}


def directory():
    return runtime.provenance.project_path("artifacts/review/focused", ROOT)


def resolve_file(path):
    path = runtime.provenance.project_path(path, ROOT)
    if not path.is_file():
        raise ValueError(f"Fixture prerequisite missing: {path}")
    return path


def target_spec(scope, target):
    workbench = scenario = expected_room = None
    if (scope, target) in (("ui", "title"), ("story", DAY_ONE_TARGET)):
        pass
    elif scope == "room" and target in ROOMS:
        scenario, expected_room = ROOMS[target], target
    elif scope == "interaction" and target in INTERACTIONS:
        scenario = INTERACTIONS[target]
    elif scope == "interaction" and target == "wardrobe":
        workbench = WORKBENCH[target]
    elif scope == "design" and target in WORKBENCH and target != "wardrobe":
        workbench = WORKBENCH[target]
    elif scope == "story" and re.fullmatch(r"[a-z0-9-]+", target) and target in story_targets():
        scenario = target
    else:
        raise ValueError("Unknown target for this scope; call focus_catalog")
    if workbench:
        workbench = resolve_file(SCENARIOS / (workbench + ".yaml"))
        if target == "mocap":
            # This developer-owned reference is an explicit prerequisite, not a fallback preview.
            import yaml
            resolve_file(yaml.safe_load(workbench.read_text(encoding="utf-8"))["motion"])
    if scenario:
        scenario = resolve_file(SCENARIOS / "segments" / (scenario + ".json"))
        config = json.loads(scenario.read_text(encoding="utf-8"))
        if config.get("presentation_snapshot"):
            resolve_file(config["presentation_snapshot"])
        expected_room = expected_room or config["room"]
    return {"scenario": scenario, "workbench": workbench, "expected_room": expected_room}


def story_targets():
    return sorted(p.stem for p in (SCENARIOS / "segments").glob("*.json"))


def named_targets():
    return {"room": list(ROOMS), "interaction": [*INTERACTIONS, "wardrobe"], "ui": ["title"],
            "design": [key for key in WORKBENCH if key != "wardrobe"], "story": [DAY_ONE_TARGET, *story_targets()]}


def catalog():
    targets = named_targets()
    for scope, names in targets.items():
        targets[scope] = {}
        for name in names:
            try:
                spec = target_spec(scope, name)
                targets[scope][name] = {"ready": True, "room": spec["expected_room"]}
            except ValueError as error:
                targets[scope][name] = {"ready": False, "reason": str(error)}
    return {"targets": targets, "rubrics": RUBRICS,
            "target_rubrics": {DAY_ONE_TARGET: DAY_ONE_RUBRIC}, "report": str(directory().with_suffix(".html"))}


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def publish(run):
    """One JSON record per run; merge under the project's cross-process review lock."""
    base = directory()
    safe = {key: value for key, value in run.items() if not key.startswith("_")}
    with Store(server_script=Path(__file__)).locked():
        atomic_write(base / "runs" / run["test_id"] / "result.json", json.dumps(safe, ensure_ascii=False, indent=2))
        records = [json.loads(p.read_text(encoding="utf-8")) for p in (base / "runs").glob("*/result.json")]
        records.sort(key=lambda item: (item["started_at"], item["test_id"]), reverse=True)
        data = json.dumps(records, ensure_ascii=True).replace("<", "\\u003c")
        atomic_write(base / "live.js", "window.FOCUSED_TESTS=" + data + ";\n")


def open_run(arguments):
    scope, target = arguments["scope"], arguments["target"]
    if target not in named_targets().get(scope, ()):
        raise ValueError("Unknown target for this scope; call focus_catalog")
    tester = arguments["tester"].strip()
    if not tester or len(tester) > 100:
        raise ValueError("Provide one tester name (1–100 characters)")
    test_id, session_id = secrets.token_hex(8), secrets.token_hex(16)
    def git(*args):
        return subprocess.run(["git", *args], cwd=ROOT, stdin=subprocess.DEVNULL,
                              capture_output=True, check=True, encoding="utf-8", timeout=10,
                              creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0).stdout.strip()

    revision, dirty = git("rev-parse", "HEAD"), bool(git("status", "--porcelain"))
    run = {"test_id": test_id, "tester": tester, "scope": scope, "target": target,
           "revision": revision, "dirty": dirty, "status": "starting", "started_at": now(),
           "checks": DAY_ONE_RUBRIC if target == DAY_ONE_TARGET else RUBRICS[scope],
           "steps": [], "acceptance_eligible": False,
           "_lock": threading.Lock(), "_session": None}
    publish(run)
    try:
        spec = target_spec(scope, target)
        audio = arguments.get("audio", target == DAY_ONE_TARGET)
        if audio and spec["workbench"]:
            raise ValueError("MCP audio preview is available for direct game entries, not the workbench")
        observation = runtime.start({"mode": "godot_manual", "background_capture": True}, focused={
            **spec, "audio": audio, "output": directory() / "runs" / test_id / "frames",
            "workbench_output": ROOT / ".runtime/focused" / test_id})
        run["_session"] = observation.pop("session_id")
        if observation.get("renderer") != "forward_plus":
            raise RuntimeError("Focused visual checks require real Forward+ rendering")
        if spec["expected_room"] and observation.get("room") != spec["expected_room"]:
            raise RuntimeError(f"Expected {spec['expected_room']}, got {observation.get('room')}")
        run.update(status="running", entry={"scene": observation["scene"], "room": observation.get("room"),
                   "renderer": observation["renderer"], "host_pid": observation["source_identity"]["process_id"]},
                   _audio=audio)
        RUNS[session_id] = run
        publish(run)
        return dict(observation, session_id=session_id, test_id=test_id, checks=run["checks"],
                    report=str(directory().with_suffix(".html")))
    except Exception as error:
        try:
            close_host(run)
        finally:
            run.update(status="blocked", error=str(error), finished_at=now())
            publish(run)
        raise RuntimeError(f"Focused test {test_id}: {error}") from error


def close_host(run):
    if not run["_session"]:
        return None
    session = run["_session"]
    run["_session"] = None
    return runtime.execute("close", {"session_id": session})["graceful_exit"]


def validate_frames(offsets, operation):
    if offsets and (operation not in ("start", "click", "drag", "input_action", "diagnostic") or
                    not 2 <= len(offsets) <= 3 or any(type(n) is not int or not 2 <= n <= 120 for n in offsets) or
                    any(b - a < 2 for a, b in zip(offsets, offsets[1:]))):
        raise ValueError("Motion needs an action and 2–3 increasing frame offsets (2–120, at least two frames apart)")


def step_run(run, args):
    if run["status"] != "running":
        raise ValueError("Only running tests accept steps")
    operation = dict(args.get("operation", {"type": "observe"}))
    if operation["type"] not in ("observe", "start", "click", "drag", "input_action", "diagnostic"):
        raise ValueError("Focused steps use ordinary game input or named workbench commands")
    if run["target"] == DAY_ONE_TARGET:
        if operation["type"] == "start":
            raise ValueError("Continuous Day 1 uses the visible New Game control on the production title")
        if run.get("route_interrupted") and operation["type"] != "observe":
            raise ValueError("The continuous route has ended; create a new test to replay")
    if operation["type"] == "diagnostic" and run["scope"] not in ("design", "interaction"):
        raise ValueError("Diagnostic commands are for workbench targets")
    offsets = args.get("motion_frames", [])
    validate_frames(offsets, operation["type"])
    capture = args.get("still", False) or bool(offsets)
    if offsets and args.get("still"):
        raise ValueError("Choose a still or a motion sequence")
    if args.get("capture_audio") and not run["_audio"]:
        raise ValueError("Enable audio when opening the direct game test")
    note = args.get("note", "").strip()
    if capture and not note:
        raise ValueError("Name the specific visual evidence you are capturing in note")
    if run["scope"] == "room" and run.get("left_room") and operation["type"] != "observe":
        raise ValueError("The test left its scoped room; finish this run and reopen for a new local route")
    endpoint = runtime.SESSIONS[run["_session"]]
    evidence_id = f"step-{len(run['steps']) + 1:04d}"
    entry = {"id": evidence_id, "time": now(), "operation": operation, "note": note, "frames": []}
    try:
        with endpoint.lock:
            result = endpoint.request(dict(operation, capture_image=False, wait_ms=args.get("wait_ms", 0),
                                          **({"evidence_id": evidence_id, "motion_frames": offsets} if capture else {})))
            if args.get("capture_audio"):
                from audio_observation import read_excerpt
                if endpoint.metrics_directory:
                    preview, endpoint.audio_observation_cursor, data = read_excerpt(
                        endpoint.metrics_directory, endpoint.audio_observation_cursor)
                    result["audio_preview"] = preview
                    if data:
                        result["audio_base64"] = data
                else:
                    result["audio_preview"] = {"available": False, "reason": "Recorder not ready"}
        frames = result.pop("evidence_frames", [])
        expected = ([0, *offsets] if offsets else [None]) if capture else []
        if [frame["frame"] for frame in frames] != expected:
            raise RuntimeError("Host returned unexpected evidence frame offsets")
        if offsets and any(b["elapsed_ms"] <= a["elapsed_ms"] for a, b in zip(frames, frames[1:])):
            raise RuntimeError("Evidence frames are not temporally distinct")
        for i, frame in enumerate(frames):
            path = resolve_file(frame["path"])
            if path != directory() / "runs" / run["test_id"] / "frames" / f"{evidence_id}-{i:02d}.png":
                raise RuntimeError("Focused evidence path mismatch")
            receipt = runtime.provenance.verify_image(path, ROOT, allow_fixture=True)
            source = receipt["source_identity"]
            runtime.provenance.validate_source(source, endpoint.expected_source, pid=endpoint.process.pid,
                                               executable=endpoint.executable)
            frame.update(path=str(path.relative_to(directory())).replace("\\", "/"), sha256=receipt["image_sha256"])
        observed = {key: result[key] for key in ("controller", "controller_phase", "clock", "found_count",
                    "modal_key", "matrix_index", "monitor_visible", "day", "chapter", "chapter_complete", "waiting",
                    "pending_choice", "pending_deduction", "pending_conflict") if key in result}
        if isinstance(result.get("snapshot"), dict):
            observed.update({key: result["snapshot"][key] for key in ("kind", "progress", "completed", "expression")
                             if key in result["snapshot"]})
        if result.get("navigation"):
            observed["actor_position"] = result["navigation"].get("position")
        controls = result.get("controls", [])
        if controls:
            observed["visible_text"] = list(dict.fromkeys(c["text"] for c in controls if c.get("text")))[:40]
        entry.update(frames=frames, scene=result.get("scene"), room=result.get("room"), observed=observed,
                     host_errors=result.get("host_errors", [])[-8:])
        if args.get("capture_audio"):
            entry["audio_preview"] = result["audio_preview"]
            if result.get("audio_base64"):
                audio_path = directory() / "runs" / run["test_id"] / "frames" / (evidence_id + ".wav")
                audio_path.parent.mkdir(parents=True, exist_ok=True)
                audio = base64.b64decode(result["audio_base64"], validate=True)
                audio_path.write_bytes(audio)
                entry["audio"] = {"path": audio_path.relative_to(directory()).as_posix(),
                                  "sha256": hashlib.sha256(audio).hexdigest()}
        if run["target"] == DAY_ONE_TARGET:
            state = {key: entry.get(key) for key in ("room", "scene")}
            state.update({key: observed.get(key) for key in (
                "day", "chapter", "chapter_complete", "clock", "found_count", "waiting", "pending_choice",
                "pending_deduction", "pending_conflict", "modal_key", "controller_phase")})
            trail = run.setdefault("route", [])
            if state["chapter"] is None and any(point["state"]["chapter"] is not None for point in trail):
                run["route_interrupted"] = True
                result["scope_warning"] = "Returned to the title after game entry; finish this continuous route here."
            # Report observed state transitions. Do not infer intervening visits from room lists.
            if not trail or trail[-1]["state"] != state:
                trail.append({"step": evidence_id, "state": state})
        if run["scope"] == "room" and result.get("room") != run["target"]:
            run["left_room"] = True
            result["scope_warning"] = "Room changed; finish the single-room test here."
    except Exception as error:
        entry["error"] = str(error)
        raise
    finally:
        run["steps"].append(entry)
        publish(run)
    result.update(test_id=run["test_id"], step=entry)
    if frames and args.get("inline", not offsets):
        # Deliver the retained evidence in order; no extra render/capture pass.
        result["images_base64"] = [base64.b64encode((directory() / f["path"]).read_bytes()).decode() for f in frames]
    return result


def validate_verdicts(run, verdicts):
    if set(verdicts) != set(run["checks"]):
        raise ValueError("Submit exactly the named checks from this scope in one batch")
    evidence = {step["id"] for step in run["steps"] if not step.get("error") and
                (run["scope"] != "room" or step.get("room") == run["target"])}
    for verdict in verdicts.values():
        outcome, reason, steps = verdict["outcome"], verdict["reason"], verdict.get("steps", [])
        if outcome not in ("pass", "fail", "blocked", "not_applicable") or not reason.strip():
            raise ValueError("Every verdict requires an outcome and concrete reason")
        if not set(steps) <= evidence or (outcome in ("pass", "fail") and not steps):
            raise ValueError("Pass/fail must cite observed step IDs from this scope; blocked/N/A need a reason")

    if run["target"] == DAY_ONE_TARGET:
        completion = verdicts["completion"]
        if completion["outcome"] == "not_applicable":
            raise ValueError("Completion is required for a continuous Day 1 run; record blocked or failed with the stopping reason")
        if completion["outcome"] == "pass":
            if run.get("route_interrupted"):
                raise ValueError("The route returned to the title; completion requires uninterrupted gameplay")
            cited = set(completion["steps"])
            saw_finish = False
            for point in run.get("route", []):
                if point["step"] not in cited:
                    continue
                state = point["state"]
                if state["chapter"] == 1 and state["day"] == 1 and state["chapter_complete"] is True:
                    saw_finish = True
                if saw_finish and state["chapter"] == 2 and state["day"] == 2 and state["room"] == "R05":
                    break
            else:
                raise ValueError("Completion requires cited observations of Chapter 1 complete followed by Day 2 in R05")


def finish_run(run, verdicts):
    if run["status"] == "observed":
        raise ValueError("This observation-only session is closed; open a scored retest")
    validate_verdicts(run, verdicts)
    if "verdicts" in run:
        if run["verdicts"] != verdicts:
            raise ValueError("The tester's submitted batch is immutable; start a new test for a retest")
    else:
        close_error = None
        try:
            graceful = close_host(run)
        except Exception as error:
            graceful, close_error = False, str(error)
        outcomes = {item["outcome"] for item in verdicts.values()}
        status = ("failed" if "fail" in outcomes else "incomplete" if "blocked" in outcomes or graceful is not True
                  else "passed" if "pass" in outcomes else "not_applicable")
        run.update(verdicts=verdicts, status=status, graceful_exit=graceful, finished_at=now())
        if close_error:
            run["error"] = close_error
    publish(run)
    return {key: run[key] for key in ("test_id", "tester", "status", "verdicts", "graceful_exit", "acceptance_eligible")}


def close_observation(identity):
    """Close only this connection's focused host and retain its unscored observations."""
    run = RUNS.get(identity)
    if run is None:
        return None
    with run["_lock"]:
        if run["status"] == "running":
            try:
                graceful = close_host(run)
            except Exception as error:
                run["error"] = str(error)
                graceful = False
            run.update(status="observed", graceful_exit=graceful, finished_at=now())
            publish(run)
        return {"session_id": identity, "test_id": run["test_id"], "closed": run["_session"] is None,
                "status": run["status"], "graceful_exit": run.get("graceful_exit")}


def execute(name, args):
    if name == "focus_catalog":
        return catalog()
    if name == "focus_open":
        return open_run(args)
    run = RUNS.get(args["session_id"])
    if run is None:
        raise ValueError("Unknown focused session; use the connection that opened it")
    with run["_lock"]:
        if name == "focus_step":
            return step_run(run, args)
        if name == "focus_finish":
            return finish_run(run, args["verdicts"])
        raise ValueError("Unknown focused tool")


def abandon(identity=None):
    for key in ([identity] if identity else list(RUNS)):
        run = RUNS.get(key)
        if not run:
            continue
        with run["_lock"]:
            if run["status"] != "running":
                continue
            try:
                close_host(run)
            except Exception as error:
                run["error"] = str(error)
            run.update(status="abandoned", finished_at=now())
            publish(run)
