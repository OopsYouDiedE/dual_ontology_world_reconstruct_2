"""Immediate same-protocol client for sessions whose MCP schemas are already loaded."""
from __future__ import annotations

import argparse
import asyncio
import json
from pathlib import Path
import sys

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

ROOT = Path(__file__).resolve().parents[2]


async def invoke(tool=None, arguments=None, *, test_sandbox=None):
    args = [str(Path(__file__).with_name("server.py")), "--expected-project-root", str(ROOT)]
    if test_sandbox:
        args += ["--test-sandbox", str(test_sandbox)]
    params = StdioServerParameters(command=sys.executable, args=args, cwd=str(ROOT))
    async with stdio_client(params) as (incoming, outgoing):
        async with ClientSession(incoming, outgoing) as session:
            initialized = await session.initialize()
            listed = await session.list_tools()
            result = {"initialize": initialized.model_dump(mode="json", by_alias=True),
                      "tools": [item.model_dump(mode="json", by_alias=True) for item in listed.tools]}
            if tool:
                response = await session.call_tool(tool, arguments or {})
                result["result"] = response.model_dump(mode="json", by_alias=True)
            return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tool", nargs="?", choices=["progress_append", "review_append", "semantic_append", "flush", "render"])
    parser.add_argument("--arguments", default="{}", help="JSON object, or @project-local JSON file")
    parser.add_argument("--test-sandbox")
    options = parser.parse_args()
    raw = options.arguments
    if raw.startswith("@"):
        path = Path(raw[1:])
        path = (path if path.is_absolute() else ROOT / path).resolve()
        if not path.is_relative_to(ROOT) or not path.is_file():
            parser.error("Arguments file must be inside this project")
        raw = path.read_text(encoding="utf-8-sig")
    output = asyncio.run(invoke(options.tool, json.loads(raw), test_sandbox=options.test_sandbox))
    print(json.dumps(output, ensure_ascii=False, indent=2))
    sys.exit(1 if output.get("result", {}).get("isError") else 0)
