"""Persistent JSON-line console for this project's standard MCP stdio input server.

Each input line is {"tool":"on|step|observe|close","arguments":{...}}.
Image blocks are saved as genuine viewport PNG receipts and omitted from console output.
Use the existing MCP Python environment; no generator runs in Python.
"""
import asyncio
import json
from pathlib import Path
import sys
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def main():
    parameters = StdioServerParameters(command=sys.executable, args=[str(Path(__file__).with_name('server.py'))])
    async with stdio_client(parameters) as streams:
        async with ClientSession(*streams) as session:
            await session.initialize()
            print(json.dumps({'ready': True, 'tools': [tool.name for tool in (await session.list_tools()).tools]}), flush=True)
            while True:
                line = await asyncio.to_thread(sys.stdin.readline)
                if not line:
                    break
                try:
                    request = json.loads(line)
                    result = await session.call_tool(request['tool'], request.get('arguments', {}), read_timeout_seconds=__import__('datetime').timedelta(seconds=180))
                    print(json.dumps({'isError': result.isError, 'content': [item.model_dump() for item in result.content if item.type != 'image']}, ensure_ascii=False), flush=True)
                except Exception as error:
                    print(json.dumps({'isError': True, 'error': str(error)}), flush=True)


if __name__ == '__main__':
    asyncio.run(main())
