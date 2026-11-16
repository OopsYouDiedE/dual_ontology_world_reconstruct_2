"""Project-bound evaluation and live-report MCP (stdio JSON-RPC)."""
from __future__ import annotations

import argparse
import asyncio
from datetime import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import sysconfig
import time
import uuid

from jsonschema import Draft202012Validator
from mcp import types
from mcp.server.lowlevel import Server
from mcp.server.stdio import stdio_server

import common as c
sys.path.insert(0, str(c.ROOT / "mcp/review"))
from core import Store  # noqa: E402


def schema(properties, required=()):
    return {"type": "object", "properties": properties, "required": list(required), "additionalProperties": False}


ROOT_FIELD = {"expected_project_root": {"type": "string", "description": "Optional extra assertion, not an override."}}
RUN = {"type": "string", "pattern": r"^eval-[0-9]{8}t[0-9]{6}-[a-f0-9]{8}$"}
TEXT = {"type": "string", "minLength": 1, "maxLength": 8000}
ID = {"type": "string", "pattern": r"^[a-z0-9][a-z0-9_-]{1,119}$"}
SCHEMAS = {
    "evaluation_start": schema({**ROOT_FIELD,
        "profile": {"enum": ["chapter1_ui", "chapter1_flow", "room_fast", "kitchen_click", "scenario"], "default": "chapter1_ui"},
        "rendered": {"type": "boolean", "default": False},
        "godot": {"type": "string", "description": "Optional project-local 4.7.2 executable."},
        "snapshot_path": {"type": "string", "description": "Project-local checkpoint for room_fast or kitchen_click."},
        "interaction_id": {"type": "string", "pattern": "^[a-z0-9_]{1,64}$", "description": "Optional kitchen item ID for the direct-handler diagnostic."},
        "scenario_path": {"type": "string", "description": "Project-local YAML/JSON configuration for scenario."},
        "monitor_visible": {"type": "boolean", "default": False, "description": "Opt in to the scenario overlay; metrics are collected either way."},
        "workers": {"type": "integer", "minimum": 1, "maximum": 2, "description": "Optional concurrency cap; reduced automatically on low-memory hosts."},
        "motion_time_scale": {"type": "number", "exclusiveMinimum": 0, "maximum": 120, "description": "Optional development-only walking/transit time-scale cap for chapter-one probes."},
        "pretransit_to": {"enum": list(c.FLOW_PRETRANSIT_TARGETS), "description": "Optional investigated destination for a first-step development checkpoint from 2F-cross-M."},
        "max_seconds": {"type": "integer", "minimum": 10, "maximum": 28800, "default": 600}}),
    "evaluation_status": schema({**ROOT_FIELD, "run_id": RUN}, ["run_id"]),
    "evaluation_cancel": schema({**ROOT_FIELD, "run_id": RUN}, ["run_id"]),
    "evaluation_gate": schema({**ROOT_FIELD, "run_id": RUN}, ["run_id"]),
    "progress_append": schema({**ROOT_FIELD, "event_id": ID, "work_id": ID, "segment_id": ID,
        "kind": {"enum": ["change", "check", "complete"]}, "summary": TEXT, "result": TEXT,
        "revision": {"type": "string", "pattern": "^[0-9a-f]{7,40}$"},
        "evidence": {"type": "array", "items": {"type": "string", "minLength": 1}, "maxItems": 100, "uniqueItems": True},
        "related_event_ids": {"type": "array", "items": ID, "uniqueItems": True, "maxItems": 1000}},
        ["work_id", "segment_id", "kind", "summary", "result", "revision", "evidence"]),
    "render_report": schema(ROOT_FIELD),
}
DESCRIPTIONS = {
    "evaluation_start": "Start a project/PID-bound development batch: chapter-one and UI/room checks, isolated chapter-one or kitchen-handler diagnostics, or one checkpoint/scenario. Returns a run_id immediately. All results are ineligible for acceptance.",
    "evaluation_status": "Read the atomically updated run YAML/JSON and actual job PIDs; no acceptance score is inferred.",
    "evaluation_cancel": "Request cancellation only after verifying the actual owned worker PID, executable, cwd and creation time. The worker cleans up its own child hosts.",
    "evaluation_gate": "Check whether the present committed revision and each room fast check permit a separate blind slow run. Formal verdict remains pending unless independently validated Terra evidence exists.",
    "progress_append": "Append one immutable review progress event; update live-progress.js atomically without expensive full rendering. Complete must reference the work's prior events.",
    "render_report": "At a milestone render index.html, gameplay.html and illustrated Markdown, then verify every local link.",
}


def _goal():
    """Use the earliest documented/persisted cutoff, never a fresh 8-hour timer."""
    import math
    from datetime import timezone
    c.assert_project()
    document = c.documented_goal()
    c.STATE.mkdir(parents=True, exist_ok=True)
    path = c.project_path(c.STATE / "active-goal.json")
    if not path.exists():
        payload = {"schema_version": 1, "project_root": str(c.ROOT), **document,
                   "source": "goal.md existing goal"}
        try:
            with path.open("x", encoding="utf-8") as stream:
                json.dump(payload, stream, ensure_ascii=False, indent=2)
                stream.flush()
                os.fsync(stream.fileno())
        except FileExistsError:
            pass
    value = c.read_json(path)
    if value.get("project_root") != str(c.ROOT) or value.get("schema_version") != 1:
        raise ValueError("Eight-hour goal receipt has the wrong project identity")
    recorded_start, recorded_deadline = float(value["started_epoch"]), float(value["deadline_epoch"])
    if not math.isfinite(recorded_start) or not math.isfinite(recorded_deadline) or recorded_deadline <= recorded_start:
        raise ValueError("Invalid persisted goal window; refusing to reset it")
    started = min(recorded_start, document["started_epoch"])
    deadline = min(recorded_deadline, document["deadline_epoch"], started + 8 * 3600)
    effective = dict(value, started_epoch=started, deadline_epoch=deadline,
                     started_at=datetime.fromtimestamp(started, timezone.utc).isoformat(),
                     deadline_at=datetime.fromtimestamp(deadline, timezone.utc).isoformat(),
                     source="earliest goal.md / persisted receipt; no reset")
    if effective != value:
        c.write_json(path, effective)
    remaining = deadline - time.time()
    if remaining <= 0:
        raise RuntimeError("Eight-hour goal limit reached; stop new work and export/commit the existing results")
    return effective, remaining


def _verify_worker(launch):
    return c.inspect_process(launch["worker_pid"], expected_exe=launch["worker_executable"],
                             required=[str(Path(__file__).with_name("worker.py").resolve()), launch["run_id"]],
                             created=launch["worker_create_time"])


def start(args):
    profile = args.get("profile", "chapter1_ui")
    if "motion_time_scale" in args and profile not in ("chapter1_flow", "chapter1_ui"):
        raise ValueError("motion_time_scale is only applicable to chapter-one diagnostic profiles")
    if "pretransit_to" in args and profile not in ("chapter1_flow", "chapter1_ui"):
        raise ValueError("pretransit_to is only applicable to chapter-one diagnostic profiles")
    if args.get("pretransit_to", c.FLOW_PRETRANSIT_TARGETS[0]) not in c.FLOW_PRETRANSIT_TARGETS:
        raise ValueError("Unsupported pretransit diagnostic destination")
    if "interaction_id" in args and profile != "kitchen_click":
        raise ValueError("interaction_id is only applicable to kitchen_click")
    if profile == "kitchen_click" and args.get("rendered", False):
        raise ValueError("kitchen_click is a headless direct-handler diagnostic, not a visual capture")
    godot = c.executable(args.get("godot"))
    if profile in ("room_fast", "kitchen_click"):
        if not args.get("snapshot_path"):
            raise ValueError(profile + " needs snapshot_path")
        c.validate_snapshot(args["snapshot_path"])
    if profile == "scenario":
        scenario = c.project_path(args.get("scenario_path") or "assets/data/test_scenarios/wake.yaml")
        if not scenario.is_file() or scenario.suffix.lower() not in (".yaml", ".yml", ".json"):
            raise ValueError("scenario_path must be an existing project-local YAML/JSON file")
        args["scenario_path"] = str(scenario)
    # Acquire/release a probe lock. The worker holds the real lock for its full lifetime.
    with c.exclusive_run_lock():
        pass
    goal, remaining = _goal()
    resources = c.recommended_workers()
    resources["workers"] = min(resources["workers"], int(args.get("workers", resources["workers"])))
    maximum = min(float(args.get("max_seconds", 600)), remaining)
    if maximum < 1:
        raise RuntimeError("Insufficient remaining goal time")
    stamp = datetime.now().strftime("%Y%m%dt%H%M%S")
    run_id = "eval-" + stamp + "-" + uuid.uuid4().hex[:8]
    directory = c.run_dir(run_id)
    directory.mkdir(parents=True, exist_ok=False)
    c.write_json(directory / "status.json", {"schema_version": 1, "run_id": run_id, "state": "starting",
        "source_identity": c.provenance.project_identity(c.ROOT), "acceptance_eligible": False})
    worker = Path(__file__).with_name("worker.py").resolve()
    worker_python = getattr(sys, "_base_executable", sys.executable) if os.name == "nt" else sys.executable
    command = [worker_python, "-u", str(worker), run_id]
    worker_env = os.environ.copy()
    if os.name == "nt":
        worker_env["PYTHONPATH"] = os.pathsep.join(filter(None, [sysconfig.get_path("purelib"), worker_env.get("PYTHONPATH")]))
    log_path = directory / "worker.log"
    with log_path.open("ab") as log:
        process = subprocess.Popen(command, cwd=c.ROOT, env=worker_env, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=(os.name != "nt"),
                                   creationflags=(subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW) if os.name == "nt" else 0)
    try:
        identity = worker_identity(process, [str(worker), run_id])
        launch = {"schema_version": 1, "run_id": run_id, "worker_pid": identity["pid"],
                  "worker_create_time": identity["create_time"], "worker_executable": identity["executable"],
                  "worker_command": identity["command"], "project_root": str(c.ROOT),
                  "profile": profile, "rendered": args.get("rendered", False),
                  "monitor_visible": args.get("monitor_visible", False),
                  "motion_time_scale": args.get("motion_time_scale"),
                  "pretransit_to": args.get("pretransit_to", c.FLOW_PRETRANSIT_TARGETS[0]),
                  "interaction_id": args.get("interaction_id"),
                  "godot": str(godot), "snapshot_path": args.get("snapshot_path"),
                  "scenario_path": args.get("scenario_path"), "deadline_seconds": maximum,
                  "resource_policy": resources,
                  "goal_started_at": goal["started_at"], "goal_deadline_epoch": goal["deadline_epoch"],
                  "started_at": c.now(), "acceptance_eligible": False}
        c.write_json(directory / "launch.json", launch)
    except Exception:
        process.terminate()
        process.wait(timeout=5)
        raise
    return {"run_id": run_id, "worker_pid": identity["pid"],
            "status_file": str(directory / "status.json"), "report_yaml": str(directory / "report.yaml"),
            "live_html": str(c.ROOT / "artifacts/review/index.html"),
            "goal_seconds_remaining_at_start": round(remaining, 1), "resource_policy": resources,
            "acceptance_eligible": False}


def worker_identity(process, required):
    import psutil
    expected = getattr(sys, "_base_executable", sys.executable) if os.name == "nt" else sys.executable
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        try:
            parent = psutil.Process(process.pid)
            candidates = [parent, *parent.children(recursive=True)]
        except psutil.NoSuchProcess:
            break
        for candidate in candidates:
            try:
                return c.inspect_process(candidate.pid, expected_exe=expected, required=required)
            except (ValueError, psutil.AccessDenied):
                continue
        if process.poll() is not None:
            break
        time.sleep(0.01)
    raise ValueError("Actual Python worker process could not be verified")


def status(run_id):
    directory = c.run_dir(run_id)
    data = c.read_json(directory / "status.json")
    launch = c.read_json(directory / "launch.json")
    if launch.get("project_root") != str(c.ROOT) or launch.get("run_id") != run_id:
        raise ValueError("Run launch identity mismatch")
    c.provenance.validate_source(data.get("source_identity"), c.provenance.project_identity(c.ROOT))
    if data.get("state") in ("starting", "running"):
        try:
            data["worker_alive"] = bool(_verify_worker(launch))
        except ValueError:
            data["worker_alive"] = False
            data["state"] = "interrupted"
            data["notice"] = "Worker exited before publishing a terminal status; inspect worker.log."
    else:
        data["worker_alive"] = False
    return data


def cancel(run_id):
    directory = c.run_dir(run_id)
    data = status(run_id)
    if not data.get("worker_alive"):
        return {"run_id": run_id, "cancel_requested": False, "state": data.get("state")}
    launch = c.read_json(directory / "launch.json")
    _verify_worker(launch)
    c.atomic_text(directory / "cancel.request", str(launch["worker_pid"]) + "\n")
    return {"run_id": run_id, "cancel_requested": True, "worker_pid": launch["worker_pid"]}


def gate(run_id):
    data = status(run_id)
    current = c.revision_state()
    jobs = data.get("jobs", {})
    required = ("chapter1-flow", "bedroom-fast", "corridor-fast", "kitchen-fast")
    checks = {name: jobs.get(name, {}).get("state") == "passed" for name in required}
    same = data.get("revision") == current["revision"]
    clean = not current["working_tree_changes"] and not data.get("working_tree_changes")
    unchanged = data.get("source_changed_during_run") is False
    ready = data.get("state") == "completed" and all(checks.values()) and same and clean and unchanged
    # Never convert a development run to an acceptance score. The existing review
    # MCP separately enforces Terra/title/new-game/provenance and all seven scores.
    return {"run_id": run_id, "fast_checks": checks, "same_revision": same, "clean_committed_revision": clean,
            "source_unchanged": unchanged, "ready_for_independent_slow_run": ready,
            "formal_acceptance": "pending_independent_terra_review",
            "reason": "All specified room checks, clean committed sources and a separate independent title/new-game review are required."}


def execute(name, arguments):
    if name not in SCHEMAS:
        raise ValueError("Unknown tool")
    Draft202012Validator(SCHEMAS[name]).validate(arguments)
    expected = arguments.pop("expected_project_root", None)
    c.assert_project(expected)
    if name == "evaluation_start": return start(arguments)
    if name == "evaluation_status": return status(arguments["run_id"])
    if name == "evaluation_cancel": return cancel(arguments["run_id"])
    if name == "evaluation_gate": return gate(arguments["run_id"])
    store = Store(c.ROOT, server_script=__file__)
    if name == "progress_append": return store.progress_append(**arguments)
    if name == "render_report": return store.flush(full_render=True)
    raise ValueError("Unknown tool")


async def main(expected):
    c.assert_project(expected)
    server = Server("dual-ontology-evaluation", version="1.0.0", instructions=(
        "Only this exact project may be launched. Development checks are never independent acceptance. "
        "Use chapter1_ui before targeted room_fast; use scenario for isolated YAML mock states. "
        "Append lightweight progress live; render only at milestones. Eight-hour budget applies across runs."))

    @server.list_tools()
    async def list_tools():
        return [types.Tool(name=name, description=DESCRIPTIONS[name], inputSchema=value) for name, value in SCHEMAS.items()]

    @server.call_tool()
    async def call_tool(name, arguments):
        try:
            result = await asyncio.to_thread(execute, name, dict(arguments or {}))
            return types.CallToolResult(content=[types.TextContent(type="text", text=json.dumps(result, ensure_ascii=False))], structuredContent=result)
        except Exception as error:
            return types.CallToolResult(isError=True, content=[types.TextContent(type="text", text=type(error).__name__ + ": " + str(error))])

    async with stdio_server() as (incoming, outgoing):
        await server.run(incoming, outgoing, server.create_initialization_options())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected-project-root", default=str(c.ROOT))
    options = parser.parse_args()
    asyncio.run(main(options.expected_project_root))
