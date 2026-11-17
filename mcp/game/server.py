"""Three MCP surfaces: autonomous tests, interactive input, environment preparation."""
import argparse
import asyncio
import atexit
import json

from mcp import types
from mcp.server.lowlevel import Server
from mcp.server.stdio import stdio_server

import automation
import environment
import runtime


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
RUN = schema({
    "duration_seconds": {"type": "number", "exclusiveMinimum": 0, "maximum": 86400, "description": "Wall-clock duration including build/startup; default 60 seconds"},
    "deadline": {"type": "string", "description": "Alternative absolute ISO-8601 deadline with timezone, e.g. +08:00 or Z"},
    "seed": {"type": "integer", "minimum": 0, "default": 1},
    "viewer": {"type": "string", "default": "detective"}
})
TOOLS = {
    "input": [
        types.Tool(name="on", description="Open a fresh real CLI/Godot host for human or SubAgent input. Returns session_id and initial observation; Godot starts at the title screen. No automatic decisions.",
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
                   inputSchema=schema({"session_id": SESSION, "operation": OPERATION, "wait_ms": WAIT, "capture_image":{"type":"boolean","default":True}}, ["session_id", "operation"])),
        types.Tool(name="observe", description="Read the latest observation without submitting an action. Godot returns the current rendered PNG and visible UI; its real window continues running.",
                   inputSchema=schema({"session_id": SESSION, "wait_ms": WAIT, "capture_image":{"type":"boolean","default":True}}, ["session_id"])),
        types.Tool(name="close", description="Close this session and release its actual host process.",
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
    if name == "on":
        backend = arguments.get("backend", "cli")
        options = dict(arguments, mode="cli_ai" if backend == "cli" else "godot_manual", controller="player")
        return runtime.start(options)
    return runtime.execute(name, arguments)


def cleanup():
    # A tool invocation owns each automatic run; disconnect cancels its hosts.
    for endpoint in list(runtime.SESSIONS.values()): endpoint.stop()


atexit.register(cleanup)


async def main(service):
    tools = TOOLS[service]
    server = Server("dual-ontology-" + service, version="2.0.0", instructions=(
        "Automatic tests belong to the auto MCP (GodotMCP/CliMCP); one call runs to the deadline without Agent input. "
        "Input MCP exposes only on, step, observe, close; each SubAgent opens its own session. "
        "The environment MCP prepares a project-local Godot .NET distribution when missing. "
        "Godot input starts at the production title and follows the real new-game path. "
        "Never forge receipts or inject author facts into campaign sessions. Deadline reached is not a campaign pass."))

    @server.list_tools()
    async def list_tools(): return tools

    @server.call_tool()
    async def call_tool(name, arguments):
        if name not in {tool.name for tool in tools}: raise ValueError("Unknown tool")
        try:
            result = await asyncio.to_thread(execute, service, name, arguments)
            png = result.pop("image_base64", None)
            content = [types.TextContent(type="text", text=json.dumps(result, ensure_ascii=False))]
            if png: content.append(types.ImageContent(type="image", mimeType="image/png", data=png))
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
