"""Persistent interactive client for the project's formal input MCP.

Send one JSON object per line: {"tool":"on","arguments":{...}}, then
step/observe/close. The server connection and its single session stay alive
until close or EOF. Every server response and returned image is retained.
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
PYTHON = Path(sys.executable)
ALLOWED = {"on", "step", "observe", "close"}


async def main():
    receipt_dir = ROOT / ".runtime" / "input-client" / secrets.token_hex(8)
    receipt_dir.mkdir(parents=True, exist_ok=False)
    parameters = StdioServerParameters(command=str(PYTHON),
        args=[str(ROOT / "mcp/game/server.py"), "--service", "input"], cwd=str(ROOT), env=os.environ.copy())
    current = None
    index = 0
    async with stdio_client(parameters) as (reader, writer):
        async with ClientSession(reader, writer) as client:
            await client.initialize()
            tools = await client.list_tools()
            print(json.dumps({"ready": True, "receipt_directory": str(receipt_dir),
                "tools": [tool.name for tool in tools.tools]}), flush=True)
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
                            raise ValueError("Use on, step, observe or close with an arguments object.")
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
                        images = []
                        for block in result.content:
                            if block.type == "image":
                                suffix = ".png" if block.mimeType == "image/png" else ".jpg"
                                image_path = receipt_dir / f"{index:06d}-{len(images)}{suffix}"
                                image_path.write_bytes(base64.b64decode(block.data, validate=True))
                                images.append(str(image_path))
                        payload = {"tool": tool, "is_error": bool(result.isError),
                            "data": result.structuredContent,
                            "text": [block.text for block in result.content if block.type == "text"],
                            "images": images}
                        receipt = receipt_dir / f"{index:06d}.json"
                        receipt.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
                        payload["receipt"] = str(receipt)
                        if not result.isError and tool == "on":
                            current = result.structuredContent["session_id"]
                        elif not result.isError and tool == "close":
                            current = None
                        data = result.structuredContent if isinstance(result.structuredContent, dict) else {}
                        summary = {"tool": tool, "is_error": bool(result.isError), "session_id": current,
                            "receipt": str(receipt), "images": images}
                        for key in ("started", "busy", "scene", "observation_path", "host_errors",
                                    "closed", "graceful_exit", "movie_path", "movie_finalized", "movie_bytes"):
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
