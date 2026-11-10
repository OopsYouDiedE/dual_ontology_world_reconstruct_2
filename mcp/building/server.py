"""Project-local Godot MCP input: real host, real UI, original receipts; no C# build."""
import asyncio
import atexit
import base64
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import threading
import time

from mcp import types
from mcp.server.lowlevel import Server
from mcp.server.stdio import stdio_server

ROOT = Path(__file__).resolve().parents[2]
SESSIONS = {}


class Host:
    def __init__(self):
        self.identity = secrets.token_hex(8)
        self.token = secrets.token_hex(32)
        self.directory = ROOT / '.runtime' / 'mcp-runs' / self.identity
        self.directory.mkdir(parents=True, exist_ok=False)
        self.process = None
        self.connection = None
        self.stream = None
        self.logs = []
        self.lock = threading.Lock()
        self.sequence = 0

    def request(self, operation):
        with self.lock:
            self.sequence += 1
            request = dict(operation, id=self.sequence, token=self.token)
            self.connection.sendall((json.dumps(request) + '\n').encode())
            line = self.stream.readline()
            if not line:
                raise RuntimeError('Godot bridge disconnected: ' + '\n'.join(self.logs[-30:]))
            response = json.loads(line)
            if response.get('id') != self.sequence:
                raise RuntimeError('Godot response ID mismatch')
            receipt = dict(response)
            if isinstance(receipt.get('result'), dict):
                receipt['result'] = {k: v for k, v in receipt['result'].items() if k != 'image_base64'}
            (self.directory / ('transport-%06d.json' % self.sequence)).write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding='utf-8')
            if 'error' in response:
                raise RuntimeError(response['error'])
            result = response['result']
            result.update(session_id=self.identity, host_errors=[x for x in self.logs if 'ERROR:' in x or 'SCRIPT ERROR' in x])
            return result

    def collect(self):
        with (self.directory / 'host.log').open('w', encoding='utf-8') as log:
            for line in self.process.stdout:
                self.logs.append(line.rstrip())
                log.write(line)
                log.flush()

    def stop(self):
        if self.connection:
            self.connection.close()
        if self.stream:
            self.stream.close()
        if self.process and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.process.kill()


def on(arguments):
    executable = next(iter(sorted((ROOT / '.runtime/godot').glob('*/Godot*_console.exe'))), None)
    if executable is None:
        raise RuntimeError('Project-local Godot .NET executable is missing')
    host = Host()
    try:
        command = [str(executable), '--headless', '--path', str(ROOT), '--editor', '--import', '--quit']
        built = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, encoding='utf-8', errors='replace', timeout=120, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        (host.directory / 'import.log').write_text('COMMAND ' + ' '.join(command) + '\n' + built.stdout + '\nEXIT ' + str(built.returncode), encoding='utf-8')
        if built.returncode or 'SCRIPT ERROR:' in built.stdout:
            raise RuntimeError('Godot import failed: ' + built.stdout[-6000:])
        with socket.socket() as reservation:
            reservation.bind(('127.0.0.1', 0))
            port = reservation.getsockname()[1]
        command = [str(executable), '--path', str(ROOT)]
        if arguments.get('background_capture', True):
            command += ['--windowed', '--position', '-32000,-32000']
        command += ['--', '--building-mcp-port=' + str(port), '--building-mcp-token=' + host.token, '--building-mcp-receipts=' + str(host.directory)]
        host.process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, encoding='utf-8', errors='replace', creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        threading.Thread(target=host.collect, daemon=True).start()
        deadline = time.monotonic() + 30
        while True:
            try:
                host.connection = socket.create_connection(('127.0.0.1', port), timeout=1)
                host.connection.settimeout(60)
                break
            except OSError:
                if host.process.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError('Godot MCP did not start: ' + '\n'.join(host.logs[-30:]))
                time.sleep(0.1)
        host.stream = host.connection.makefile('rb')
        result = host.request({'type': 'observe', 'wait_ms': 300})
        SESSIONS[host.identity] = host
        return result
    except BaseException:
        host.stop()
        raise


def execute(name, arguments):
    if name == 'on':
        return on(arguments)
    host = SESSIONS[arguments['session_id']]
    if name == 'close':
        try:
            result = host.request({'type': 'close'})
            host.process.wait(timeout=10)
            return result
        finally:
            host.stop()
            SESSIONS.pop(host.identity, None)
    request = dict(arguments.get('operation', {})) if name == 'step' else {'type': 'observe'}
    if request.get('type') not in ('click', 'input_action', 'observe', 'pointer', 'mouse_button', 'key', 'text'):
        raise ValueError('Only real UI click/input_action and observe are supported')
    request.update(wait_ms=arguments.get('wait_ms', 200), capture_image=arguments.get('capture_image', True))
    return host.request(request)


def schema(properties, required=()):
    return {'type': 'object', 'properties': properties, 'required': list(required), 'additionalProperties': False}


async def main():
    server = Server('dual-ontology-building-input', instructions='Use on, then serial step/observe from the latest real viewport, then close. Do not inject state.')
    identity = {'type': 'string'}
    common = {'session_id': identity, 'wait_ms': {'type': 'integer', 'minimum': 0, 'maximum': 10000}, 'capture_image': {'type': 'boolean'}}
    operation = schema({'type': {'type': 'string', 'enum': ['click', 'input_action', 'observe', 'pointer', 'mouse_button', 'key', 'text']}, 'x': {'type': 'number'}, 'y': {'type': 'number'}, 'action': {'type': 'string'}, 'frames': {'type': 'integer', 'minimum': 1, 'maximum': 120}, 'key': {'type':'string'}, 'text': {'type':'string'}, 'ctrl': {'type':'boolean'}, 'shift': {'type':'boolean'}, 'button': {'type':'integer'}, 'pressed': {'type':'boolean'}, 'double_click': {'type':'boolean'}, 'dx': {'type':'number'}, 'dy': {'type':'number'}, 'mask': {'type':'integer'}}, ['type'])
    tools = [types.Tool(name='on', description='Build/import and open the actual building simulator in this project.', inputSchema=schema({'background_capture': {'type': 'boolean'}})), types.Tool(name='step', description='Submit one real UI operation from the latest observation.', inputSchema=schema(dict(common, operation=operation), ['session_id', 'operation'])), types.Tool(name='observe', description='Read the current Godot viewport and visible controls.', inputSchema=schema(common, ['session_id'])), types.Tool(name='close', description='Close this MCP-owned Godot process.', inputSchema=schema({'session_id': identity}, ['session_id']))]

    @server.list_tools()
    async def list_tools():
        return tools

    @server.call_tool()
    async def call_tool(name, arguments):
        try:
            result = await asyncio.to_thread(execute, name, arguments)
            png = result.pop('image_base64', None)
            content = [types.TextContent(type='text', text=json.dumps(result, ensure_ascii=False))]
            if png:
                content.append(types.ImageContent(type='image', mimeType='image/png', data=png))
            return types.CallToolResult(content=content, structuredContent=result)
        except Exception as error:
            return types.CallToolResult(content=[types.TextContent(type='text', text=str(error))], isError=True)

    async with stdio_server() as streams:
        await server.run(*streams, server.create_initialization_options())


@atexit.register
def cleanup():
    for host in SESSIONS.values():
        host.stop()


if __name__ == '__main__':
    asyncio.run(main())
