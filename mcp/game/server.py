"""Three MCP surfaces: autonomous tests, interactive input, environment preparation."""
import argparse
import asyncio
import atexit
import json
import threading

from mcp import types
from mcp.server.lowlevel import Server
from mcp.server.stdio import stdio_server

import automation
import environment
import runtime

BLIND_SESSIONS = set()

def schema(properties, required=()):
    return {"type": "object", "properties": properties, "required": list(required), "additionalProperties": False}


SESSION = {"type": "string", "description": "session_id returned by on in this MCP connection"}
WAIT = {"type": "integer", "minimum": 0, "maximum": 10000, "default": 200}
OPERATION = schema({
    "type": {"type": "string", "enum": ["select", "advance", "start", "input_action", "click", "drag", "case_reasoning", "character", "next_case"]},
    "command": {"type":"string","enum":["action","deduce","conversation","order","continue","cancel","save","walk","pause"]},
    "paused": {"type":"boolean"},
    "action_id": {"type":"string"},
    "evidence_ids": {"type":"array","items":{"type":"string"},"description":"Evidence IDs selected from the current deduction preview; never author-injected facts."},
    "order": {"type":"array","items":{"type":"string"}},
    "position": {"type":"array","items":{"type":"number"},"minItems":3,"maxItems":3},
    "case_request": {"type": "string", "description": "JSON actor proof request: operation info/questions/scene/infer/check/prove/check_goal/check_natural/review/strategy/travel_actor/sim4_plan/sim4_execute; seal_scene requires case_id and query_id and commits DV-declared cognitive time, repeats are idempotent; no author evidence injection"},
    "choice_id": {"type": "string"},
    "decision_maker": {"type": "string", "enum": ["human", "agent", "llm", "player"], "description": "Who submitted this CLI choice; does not change its controller or AI scores."},
    "steps": {"type": "integer", "minimum": 1, "maximum": 100},
    "action": {"type": "string"},
    "frames": {"type": "integer", "minimum": 1, "maximum": 120},
    "x": {"type": "number", "minimum": 0}, "y": {"type": "number", "minimum": 0},
    "to_x": {"type": "number", "minimum": 0}, "to_y": {"type": "number", "minimum": 0}
}, ["type"])
FOCUS_OPERATION = schema({
    **{key: OPERATION["properties"][key] for key in ("action", "frames", "x", "y", "to_x", "to_y")},
    "type": {"type": "string", "enum": ["observe", "start", "click", "drag", "input_action", "diagnostic"]},
}, ["type"])
FOCUS_VERDICT = schema({
    "outcome": {"type": "string", "enum": ["pass", "fail", "blocked", "not_applicable"]},
    "reason": {"type": "string", "minLength": 1, "maxLength": 2500},
    "steps": {"type": "array", "uniqueItems": True, "items": {"type": "string", "pattern": "^step-[0-9]{4,}$"}},
}, ["outcome", "reason"])
FOCUS_TOOLS = [
    types.Tool(name="focus_catalog", description="List five focused Forward+ development test scopes, named targets, fixture readiness, and exact rubric keys.", inputSchema=schema({})),
    types.Tool(name="focus_open", description="Open one named scope with one tester. Direct entry; no screenshot or assessment setup. Publishes running or blocked state to the local live HTML.", inputSchema=schema({
        "scope": {"type": "string", "enum": ["room", "interaction", "ui", "design", "story"]},
        "target": {"type": "string", "minLength": 1, "maxLength": 120},
        "tester": {"type": "string", "minLength": 1, "maxLength": 100},
        "audio": {"type": "boolean", "default": False, "description": "Enable on-demand live audio preview for direct game entries."},
    }, ["scope", "target", "tester"])),
    types.Tool(name="focus_step", description="Operate or observe the focused host. Opt in to a still or to ordered pre-action and motion-frame evidence. Named workbench actions: monitor, reload, previous_case, next_case.", inputSchema=schema({
        "session_id": SESSION, "operation": FOCUS_OPERATION,
        "wait_ms": {**WAIT, "default": 0},
        "note": {"type": "string", "maxLength": 2000, "description": "What to verify/what you observed; required when taking a screenshot."},
        "still": {"type": "boolean", "default": False},
        "motion_frames": {"type": "array", "minItems": 2, "maxItems": 3, "items": {"type": "integer", "minimum": 2, "maximum": 120},
                          "description": "Two or three frame offsets from dispatch; frame zero is captured before the action automatically."},
        "inline": {"type": "boolean", "description": "Return retained images inline (default yes for still, no for a motion sequence)."},
        "capture_audio": {"type": "boolean", "default": False},
    }, ["session_id"])),
    types.Tool(name="focus_finish", description="Close the host and publish the opening tester's single immutable verdict batch. Use exact rubric keys; cite observed step IDs for pass/fail, give reasons for blocked or not applicable.", inputSchema=schema({
        "session_id": SESSION, "verdicts": {"type": "object", "additionalProperties": FOCUS_VERDICT},
    }, ["session_id", "verdicts"])),
]
RUN = schema({
    "duration_seconds": {"type": "number", "exclusiveMinimum": 0, "maximum": 86400, "description": "Wall-clock duration including build/startup; default 60 seconds"},
    "deadline": {"type": "string", "description": "Alternative absolute ISO-8601 deadline with timezone, e.g. +08:00 or Z"},
    "seed": {"type": "integer", "minimum": 0, "default": 1},
    "viewer": {"type": "string", "default": "detective"}
})
TOOLS = {
    "input": FOCUS_TOOLS + [
        types.Tool(name="on", description="Open a fresh real CLI/Godot host for human or SubAgent input. Returns session_id and initial observation. Segment tests require explicit scenario_path and a matching assessment_plan; never default them to title/new-game. No automatic decisions.",
                   inputSchema=schema({"backend": {"type": "string", "enum": ["cli", "godot"], "default": "cli"},
                                       "seed": {"type": "integer", "minimum": 0, "default": 1},
                                       "viewer": {"type": "string", "default": "detective"},
                                       "decision_maker": {"type": "string", "enum": ["human", "agent", "llm", "player"], "description": "Decision maker recorded for CLI player input."},
                                       "assessment_plan": {"type": "string", "description": "Project-local simultaneous seven-category plan; required for agent Godot tests. Validates all channels, blind observer readiness and reference images before launch."},
                                       "scenario_path": {"type": "string", "description": "Direct isolated segment entry; must match the first scenario in a validated segment assessment plan. Skips title/new-game."},
                                       "snapshot_path": {"type":"string","description":"Project-local snapshot to restore in a Godot development session; ineligible for independent acceptance."},
                                       "save_slot": {"type":"string","pattern":"^[A-Za-z0-9_-]{1,64}$","description":"Optional stable isolated save slot for a local player interface."},
                                       "movie_filename": {"type": "string", "pattern": "^[A-Za-z0-9][A-Za-z0-9_-]{0,79}\\.avi$", "description": "Optional new Godot Movie Maker AVI basename in artifacts/recordings; existing files are never overwritten."},
                                       "movie_fps": {"type": "integer", "minimum": 1, "maximum": 60, "description": "Fixed simulation/video frame rate for movie capture (30 if omitted); this is not a real-time performance benchmark."},
                                       "background_capture": {"type": "boolean", "default": True, "description": "Keep the real Godot window minimized while rendering MCP observations; false opens a visible manual window."}})),
        types.Tool(name="step", description="Submit one live operation and return the new observation. CLI: advance/select. Godot: start/select/input_action/click. Choices must come from the current screen.",
                   inputSchema=schema({"session_id": SESSION, "operation": OPERATION, "wait_ms": WAIT, "capture_image":{"type":"boolean","default":True}, "capture_audio":{"type":"boolean","default":False,"description":"Include new captured Master audio as a WAV listening preview."}}, ["session_id", "operation"])),
        types.Tool(name="observe", description="Read the latest observation without submitting an action. Godot returns the current rendered PNG and visible UI; its real window continues running.",
                   inputSchema=schema({"session_id": SESSION, "wait_ms": WAIT, "capture_image":{"type":"boolean","default":True}, "capture_audio":{"type":"boolean","default":False,"description":"Include new captured Master audio as a WAV listening preview."}}, ["session_id"])),
        types.Tool(name="event_script", description="Record an English blind observation of visible actions or heard cues in this session.",
                   inputSchema=schema({"session_id": SESSION, "text": {"type": "string", "minLength": 1, "maxLength": 4096}}, ["session_id", "text"])),
        types.Tool(name="character_script", description="Record English dialogue observed in this session.",
                   inputSchema=schema({"session_id": SESSION, "text": {"type": "string", "minLength": 1, "maxLength": 4096}}, ["session_id", "text"])),
        types.Tool(name="charactor_script", description="Compatibility alias for character_script.",
                   inputSchema=schema({"session_id": SESSION, "text": {"type": "string", "minLength": 1, "maxLength": 4096}}, ["session_id", "text"])),
        types.Tool(name="review_visible_text", description="Classify a currently visible text string and verify whether it is English.",
                   inputSchema=schema({"session_id": SESSION, "path": {"type":"string", "minLength":1}, "text": {"type":"string", "minLength":1}, "category": {"type":"string", "enum":["dialogue", "spoken_dialogue", "speech", "prompt", "interaction_prompt", "nameplate", "single_key_icon", "action_key_icon", "hud", "menu", "other_ui"]}, "english_verified": {"type":"boolean"}}, ["session_id", "path", "text", "category", "english_verified"])),
        types.Tool(name="close", description="Close an owned session and release its host. Focused observations are retained without verdicts.",
                   inputSchema=schema({"session_id": SESSION}, ["session_id"])),
        types.Tool(name="metrics_status", description="Poll same-session telemetry analysis after close; keep this MCP connection open until complete or error.",
                   inputSchema=schema({"session_id": SESSION}, ["session_id"])),
    ],
    "auto": [
        types.Tool(name="GodotMCP", description="Run a complete autonomous real Godot engine-AI test until completion, fault or the configured deadline, then return its final report/observation. One call; no Agent input, polling or follow-up steps required. Duration includes build/startup.", inputSchema=RUN),
        types.Tool(name="CliMCP", description="Run a complete autonomous production CLI engine-AI test until completion, fault or the configured deadline, then return its final report/observation. The tool itself advances formal actions; no Agent input or polling required.", inputSchema=RUN),
    ],
    "environment": [
        types.Tool(name="prepare", description="Prepare Godot .NET/C#, .NET 8 SDK and optionally Blender 4.5.3 (with_blender=true) in this project folder; report the active Python runtime. Reuse valid installations; local_copy=true clones existing Godot binaries into .runtime/godot. Official downloads are checksum verified. Windows/Linux x64; no global install or recursive deletion.",
                   inputSchema=schema({"local_copy": {"type": "boolean", "default": False}, "with_blender": {"type": "boolean", "default": False}})),
    ],
}


def execute(service, name, arguments):
    runtime.provenance.assert_runtime_root(runtime.ROOT)
    if service == "environment":
        return dict(environment.prepare(**arguments), server_identity=runtime.provenance.server_identity(runtime.ROOT, __file__))
    if service == "auto":
        return automation.tool("godot" if name == "GodotMCP" else "cli", arguments)
    if name.startswith("focus_"):
        import focused
        return focused.execute(name, arguments)
    if name == "close":
        import focused
        observation = focused.close_observation(arguments["session_id"])
        if observation is not None:
            return observation
    if name == "on":
        backend = arguments.get("backend", "cli")
        options = dict(arguments, mode="cli_ai" if backend == "cli" else "godot_manual", controller="player")
        return runtime.start(options)
    return runtime.execute(name, arguments)



def observer_result(service, name, result, session_id=None):
    """Keep blind gameplay responses to pixels and transport provenance."""
    if service != "input" or not isinstance(result, dict):
        return result
    session_id = result.get("session_id") or session_id
    endpoint = runtime.SESSIONS.get(session_id)
    if endpoint is not None and getattr(endpoint, "assessment_plan", None):
        BLIND_SESSIONS.add(session_id)
    if session_id not in BLIND_SESSIONS:
        return result
    allowed = ("session_id", "source_identity", "server_identity", "image_base64", "audio_base64")
    if name == "close":
        allowed += ("closed", "graceful_exit", "metrics_status", "metrics_poll_tool")
    elif name == "metrics_status":
        allowed += ("metrics_status", "metrics_summary_path", "metrics_error")
    elif name in ("event_script", "character_script", "charactor_script", "review_visible_text"):
        allowed += ("recorded", "kind", "evidence_path", "monitor_elapsed_s")
    visible = {key: result[key] for key in allowed if key in result}
    # Runtime scene paths are also nested in capture provenance. Retain only
    # the static project identity and owning process needed for validation.
    if isinstance(visible.get("source_identity"), dict):
        keys = ("project_root", "project_sha256", "configured_main_scene", "process_id", "executable_path")
        visible["source_identity"] = {key: visible["source_identity"][key] for key in keys
                                      if key in visible["source_identity"]}
    return visible


async def execute_owned(service, name, arguments):
    """Close a session if the caller disappears while its launch is running."""
    task = asyncio.create_task(asyncio.to_thread(execute, service, name, arguments))
    try:
        return await asyncio.shield(task)
    except asyncio.CancelledError:
        def dispose(finished):
            try:
                result = finished.result()
                session_id = result.get("session_id") if isinstance(result, dict) else None
                if service == "input" and name == "focus_open" and session_id:
                    import focused
                    threading.Thread(target=focused.abandon, args=(session_id,), daemon=True).start()
                if service == "input" and name == "on" and session_id:
                    threading.Thread(target=runtime.execute, args=("close", {"session_id": session_id}), daemon=True).start()
            except (Exception, asyncio.CancelledError):
                pass
        task.add_done_callback(dispose)
        raise


def cleanup():
    # A tool invocation owns each automatic run; disconnect cancels its hosts.
    # Import only when a focused tool has been used (normal input startup stays light).
    import sys
    try:
        if "focused" in sys.modules:
            sys.modules["focused"].abandon()
    finally:
        for endpoint in list(runtime.SESSIONS.values()): endpoint.stop()


atexit.register(cleanup)


async def main(service):
    tools = TOOLS[service]
    server = Server("dual-ontology-" + service, version="2.0.0", instructions=(
        "Automatic tests belong to the auto MCP (GodotMCP/CliMCP); one call runs to the deadline without Agent input. "
        "Input MCP exposes on, step, observe, event_script, character_script and close; each observer opens its own session. "
        "The environment MCP prepares a project-local Godot .NET distribution when missing. "
        "Segment tests start at their explicit scenario/checkpoint using a matching assessment plan. Title startup is reserved for explicitly requested menu tests. "
        "Never forge receipts or inject author facts into campaign sessions. Deadline reached is not a campaign pass."))

    @server.list_tools()
    async def list_tools(): return tools

    @server.call_tool()
    async def call_tool(name, arguments):
        if name not in {tool.name for tool in tools}: raise ValueError("Unknown tool")
        try:
            result = await execute_owned(service, name, arguments)
            result = observer_result(service, name, result, arguments.get("session_id"))
            png = result.pop("image_base64", None)
            images = result.pop("images_base64", [])
            audio = result.pop("audio_base64", None)
            content = [types.TextContent(type="text", text=json.dumps(result, ensure_ascii=False))]
            if png: images.append(png)
            content.extend(types.ImageContent(type="image", mimeType="image/png", data=image) for image in images)
            if audio: content.append(types.AudioContent(type="audio", mimeType="audio/wav", data=audio))
            return types.CallToolResult(content=content, structuredContent=result)
        except Exception as error:
            return types.CallToolResult(isError=True, content=[types.TextContent(type="text", text=str(error))])

    try:
        async with stdio_server() as (incoming, outgoing):
            await server.run(incoming, outgoing, server.create_initialization_options())
    finally:
        cleanup()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--service", choices=list(TOOLS), default="input")
    parser.add_argument("--expected-project-root")
    options = parser.parse_args()
    runtime.provenance.assert_runtime_root(runtime.ROOT, options.expected_project_root)
    asyncio.run(main(options.service))
