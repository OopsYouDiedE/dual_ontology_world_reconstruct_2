"""Convenience client that really initializes and calls the stdio MCP."""
from __future__ import annotations

import argparse
import asyncio
import json
import os
from pathlib import Path
import sys

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

import common as c


async def invoke(tool=None, arguments=None):
    c.assert_project()
    params = StdioServerParameters(command=sys.executable,
        args=[str(Path(__file__).with_name("server.py")), "--expected-project-root", str(c.ROOT)], cwd=str(c.ROOT))
    async with stdio_client(params) as (incoming, outgoing):
        async with ClientSession(incoming, outgoing) as session:
            initialized = await session.initialize()
            listing = await session.list_tools()
            output = {"server": initialized.serverInfo.model_dump(mode="json"),
                      "tools": [tool.name for tool in listing.tools]}
            if tool:
                response = await session.call_tool(tool, arguments or {})
                output["result"] = response.model_dump(mode="json", by_alias=True)
                if os.name == "nt" and tool == "evaluation_start" and not response.isError:
                    run_id = response.structuredContent["run_id"]
                    print("Started " + run_id + "; keeping the Windows MCP session open until the worker finishes.", file=sys.stderr, flush=True)
                    while True:
                        await asyncio.sleep(1)
                        state = await session.call_tool("evaluation_status", {"run_id": run_id})
                        if state.isError:
                            output["status"] = state.model_dump(mode="json", by_alias=True)
                            break
                        if state.structuredContent.get("state") not in ("starting", "running"):
                            output["status"] = state.model_dump(mode="json", by_alias=True)
                            break
            return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tool", nargs="?", choices=["evaluation_start", "evaluation_status", "evaluation_cancel", "evaluation_gate", "progress_append", "render_report"])
    parser.add_argument("--arguments", default="{}", help="JSON object or @project-local JSON file")
    options = parser.parse_args()
    raw = options.arguments
    if raw.startswith("@"):
        path = c.project_path(raw[1:])
        if not path.is_file(): parser.error("Arguments file must exist inside this project")
        raw = path.read_text(encoding="utf-8-sig")
    output = asyncio.run(invoke(options.tool, json.loads(raw)))
    print(json.dumps(output, ensure_ascii=False, indent=2))
    sys.exit(1 if output.get("result", {}).get("isError") else 0)
