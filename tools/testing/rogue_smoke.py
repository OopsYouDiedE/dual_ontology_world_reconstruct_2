"""Launch the project's actual stdio MCP and capture the Rogue Run viewport."""
import argparse
import asyncio
from datetime import timedelta
import json
from pathlib import Path
import sys

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

ROOT = Path(__file__).resolve().parents[2]


def data(result):
    text = next((block.text for block in result.content if block.type == "text"), "{}")
    if result.isError:
        raise RuntimeError(text)
    return result.structuredContent or json.loads(text)


async def smoke(seed, action, click, frames):
    params = StdioServerParameters(command=sys.executable, cwd=str(ROOT),
        args=[str(ROOT / "mcp/game/server.py"), "--service", "input", "--expected-project-root", str(ROOT)])
    async with stdio_client(params) as (reader, writer):
        async with ClientSession(reader, writer, read_timeout_seconds=timedelta(seconds=120)) as client:
            await client.initialize()
            ready = data(await client.call_tool("status", {}))
            if not ready["ready"]:
                raise RuntimeError("; ".join(ready["reasons"]))
            initial = data(await client.call_tool("on", {"seed": seed}))
            identity = initial["session_id"]
            try:
                args = {"session_id": identity, "operation": "action" if action else "wait", "frames": frames}
                if action:
                    args["action"] = action
                if click:
                    args.update(operation="click", x=click[0], y=click[1])
                after = data(await client.call_tool("step", args))
                print(json.dumps({"initial": initial, "after": after}, ensure_ascii=False, indent=2))
            finally:
                data(await client.call_tool("close", {"session_id": identity}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=int, default=1)
    operation = parser.add_mutually_exclusive_group()
    operation.add_argument("--action", help="Optional action defined by the game in InputMap")
    operation.add_argument("--click", type=float, nargs=2, metavar=("X", "Y"), help="Click at viewport coordinates")
    parser.add_argument("--frames", type=int, default=8, choices=range(1, 121), metavar="1..120")
    opts = parser.parse_args()
    asyncio.run(smoke(opts.seed, opts.action, opts.click, opts.frames))
