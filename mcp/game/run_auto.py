"""Keep a real auto MCP connection open for one complete engine-AI run."""
import argparse
import asyncio
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import sys

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

ROOT = Path(__file__).resolve().parents[2]


async def run(options):
    arguments = {"seed": options.seed, "viewer": options.viewer}
    if options.deadline:
        target = datetime.fromisoformat(options.deadline.replace("Z", "+00:00"))
        if target.tzinfo is None:
            raise ValueError("deadline must include a timezone")
        seconds = (target - datetime.now(timezone.utc)).total_seconds()
        arguments["deadline"] = options.deadline
    else:
        seconds = options.duration_seconds
        arguments["duration_seconds"] = seconds
    if not 0 < seconds <= 86400:
        raise ValueError("run duration must be between 0 and 86400 seconds")
    if options.content_path:
        arguments["content_path"] = str(Path(options.content_path).resolve())
    destination = Path(options.receipt).resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    parameters = StdioServerParameters(command=sys.executable,
        args=[str(ROOT / "mcp/game/server.py"), "--service", "auto"], cwd=str(ROOT), env=os.environ.copy())
    tool = "CliMCP" if options.backend == "cli" else "GodotMCP"
    async with stdio_client(parameters) as (reader, writer):
        async with ClientSession(reader, writer,
                read_timeout_seconds=timedelta(seconds=seconds + 90)) as session:
            await session.initialize()
            result = await session.call_tool(tool, arguments,
                read_timeout_seconds=timedelta(seconds=seconds + 90))
            receipt = {"tool": tool, "arguments": arguments, "isError": result.isError,
                "data": result.structuredContent,
                "text": [block.text for block in result.content if block.type == "text"]}
            destination.write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding="utf-8")
            print("RECEIPT", destination, flush=True)
            data = result.structuredContent or {}
            print(json.dumps({key: data[key] for key in
                ("run_id", "status", "detail", "report_path", "transcript_path") if key in data},
                ensure_ascii=False), flush=True)
            if result.isError:
                print("\n".join(receipt["text"]), flush=True)
                raise SystemExit(1)
            if data.get("status") == "failed":
                raise SystemExit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backend", choices=("cli", "godot"), default="cli")
    deadline = parser.add_mutually_exclusive_group()
    deadline.add_argument("--duration-seconds", type=float, default=600)
    deadline.add_argument("--deadline")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--viewer", default="detective")
    parser.add_argument("--content-path")
    parser.add_argument("--receipt", required=True)
    asyncio.run(run(parser.parse_args()))
