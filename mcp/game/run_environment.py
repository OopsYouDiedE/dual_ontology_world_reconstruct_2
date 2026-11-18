"""Prepare this checkout through its formal environment MCP and retain the receipt."""
import argparse
import asyncio
from datetime import timedelta
import json
import os
from pathlib import Path
import sys

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

ROOT = Path(__file__).resolve().parents[2]


async def main(local_copy, with_blender):
    parameters = StdioServerParameters(command=sys.executable,
        args=[str(ROOT / "mcp/game/server.py"), "--service", "environment"], cwd=str(ROOT), env=os.environ.copy())
    async with stdio_client(parameters) as (reader, writer):
        async with ClientSession(reader, writer, read_timeout_seconds=timedelta(seconds=900)) as session:
            await session.initialize()
            result = await session.call_tool("prepare", {"local_copy": local_copy, "with_blender": with_blender},
                read_timeout_seconds=timedelta(seconds=900))
            receipt = {"tool": "prepare", "isError": bool(result.isError), "data": result.structuredContent,
                "text": [item.text for item in result.content if item.type == "text"]}
            destination = ROOT / ".runtime/environment-receipt.json"
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding="utf-8")
            print(json.dumps(receipt, ensure_ascii=False), flush=True)
            if result.isError:
                raise SystemExit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--local-copy", action="store_true")
    parser.add_argument("--with-blender", action="store_true")
    options = parser.parse_args()
    asyncio.run(main(options.local_copy, options.with_blender))
