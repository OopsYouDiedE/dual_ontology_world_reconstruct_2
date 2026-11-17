"""Persistent interactive client for the project's formal input MCP.

Send one JSON object per line: {"tool":"on","arguments":{...}}, then
step/observe/notes/close. The server connection and its single session stay alive
until close or EOF. Every server response and returned image/audio is retained.
"""
import asyncio
import base64
import json
import os
from pathlib import Path
import secrets
import sys

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "mcp"))
import capture_provenance as provenance
PYTHON = Path(sys.executable)
HOST_TOOLS = {"on", "step", "observe", "close"}
NOTE_TOOLS = {"event_script", "character_script", "charactor_script", "review_visible_text"}
ALLOWED = HOST_TOOLS | NOTE_TOOLS


def retain_audio(block, receipt_dir, index, audio_index):
    """Retain a returned WAV with its MIME type and byte count in the receipt."""
    if block.mimeType != "audio/wav":
        raise ValueError(f"Unsupported audio type: {block.mimeType}")
    audio_bytes = base64.b64decode(block.data, validate=True)
    audio_path = receipt_dir / f"{index:06d}-{audio_index}.wav"
    audio_path.write_bytes(audio_bytes)
    return {"path": str(audio_path), "mime_type": block.mimeType, "bytes": len(audio_bytes)}


async def main():
    provenance.assert_runtime_root(ROOT)
    expected = provenance.project_identity(ROOT)
    receipt_dir = provenance.project_path(ROOT / ".runtime" / "input-client" / secrets.token_hex(8), ROOT)
    receipt_dir.mkdir(parents=True, exist_ok=False)
    parameters = StdioServerParameters(command=str(PYTHON),
        args=[str(ROOT / "mcp/game/server.py"), "--service", "input", "--expected-project-root", str(ROOT)], cwd=str(ROOT), env=os.environ.copy())
    current = None
    blind_session = False
    index = 0
    host_pid = None
    server_pid = None
    async with stdio_client(parameters) as (reader, writer):
        async with ClientSession(reader, writer) as client:
            await client.initialize()
            tools = await client.list_tools()
            print(json.dumps({"ready": True, "receipt_directory": str(receipt_dir),
                "expected_project": expected, "tools": [tool.name for tool in tools.tools]}), flush=True)
            try:
                while True:
                    line = await asyncio.to_thread(sys.stdin.readline)
                    if not line:
                        break
                    try:
                        request = json.loads(line)
                        tool = request.get("tool")
                        arguments = request.get("arguments", {})
                        if tool not in ALLOWED or not isinstance(arguments, dict):
                            raise ValueError("Use a supported tool with an arguments object.")
                        if tool == "on" and current is not None:
                            raise ValueError("Close the current session before opening another.")
                        if tool != "on":
                            if current is None:
                                raise ValueError("Open a session first.")
                            if "session_id" in arguments and arguments["session_id"] != current:
                                raise ValueError("This client owns a different session.")
                            arguments = dict(arguments, session_id=current)
                        result = await client.call_tool(tool, arguments)
                        index += 1
                        data = result.structuredContent if isinstance(result.structuredContent, dict) else {}
                        if not result.isError and tool in HOST_TOOLS:
                            source = data.get("source_identity") or {}
                            server = data.get("server_identity") or {}
                            provenance.validate_source(source, expected, pid=host_pid)
                            provenance.validate_source(server, expected)
                            if not isinstance(source.get("process_id"), int) or source["process_id"] <= 0:
                                raise ValueError("Host PID is missing from capture identity")
                            if not isinstance(server.get("server_pid"), int) or server["server_pid"] <= 0:
                                raise ValueError("Server PID is missing from capture identity")
                            if server_pid is not None and server["server_pid"] != server_pid:
                                raise ValueError("Server PID changed during capture")
                            host_pid, server_pid = source["process_id"], server["server_pid"]
                        if not result.isError and tool in NOTE_TOOLS and (host_pid is None or server_pid is None):
                            raise ValueError("Notes require a previously validated owning session.")
                        images = []
                        audio = []
                        for block in result.content:
                            if block.type == "image":
                                suffix = ".png" if block.mimeType == "image/png" else ".jpg"
                                image_path = receipt_dir / f"{index:06d}-{len(images)}{suffix}"
                                image_path.write_bytes(base64.b64decode(block.data, validate=True))
                                provenance.save_image_sidecar(image_path, data)
                                images.append(str(image_path))
                            elif block.type == "audio":
                                audio.append(retain_audio(block, receipt_dir, index, len(audio)))
                        payload = {"tool": tool, "is_error": bool(result.isError),
                            "data": result.structuredContent,
                            "text": [block.text for block in result.content if block.type == "text"],
                            "images": images, "audio": audio}
                        receipt = receipt_dir / f"{index:06d}.json"
                        receipt.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
                        payload["receipt"] = str(receipt)
                        if not result.isError and tool == "on":
                            current = result.structuredContent["session_id"]
                            blind_session = bool(arguments.get("assessment_plan"))
                        elif not result.isError and tool == "close":
                            current = None
                            host_pid = None
                        data = result.structuredContent if isinstance(result.structuredContent, dict) else {}
                        summary = {"tool": tool, "is_error": bool(result.isError), "session_id": current,
                            "receipt": str(receipt), "images": images, "audio": audio}
                        for key in (() if blind_session and tool in ("on", "step", "observe") else ("started", "busy", "scene", "observation_path", "host_errors", "source_identity", "server_identity",
                                    "closed", "graceful_exit", "movie_path", "movie_finalized", "movie_bytes",
                                    "checkpoint_path", "checkpoint_restored", "checkpoint_error", "checkpoint_saved",
                                    "controller", "controller_phase", "metrics_directory", "acceptance_eligible")):
                            if key in data:
                                summary[key] = data[key]
                        if result.isError:
                            summary["error"] = payload["text"]
                        print(json.dumps(summary), flush=True)
                    except Exception as error:
                        print(json.dumps({"is_error": True, "error": str(error)}), flush=True)
            finally:
                if current is not None:
                    result = await client.call_tool("close", {"session_id": current})
                    index += 1
                    receipt = receipt_dir / f"{index:06d}-eof-close.json"
                    receipt.write_text(json.dumps({"is_error": bool(result.isError),
                        "data": result.structuredContent,
                        "text": [block.text for block in result.content if block.type == "text"]},
                        ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    asyncio.run(main())
