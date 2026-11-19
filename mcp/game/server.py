"""Standalone Godot test MCP. All test output is scoped to an owned run."""
import argparse
from contextlib import asynccontextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import time
from typing import Literal

from mcp.server.fastmcp import FastMCP, Image
import environment

ROOT = environment.ROOT
SCENE = "res://scenes/rogue/Run.tscn"
AUTOLOAD = 'GameMcp="*res://mcp/game/GameControl.gd"'


def readiness():
    project = (ROOT / "project.godot").read_text(encoding="utf-8-sig")
    match = re.search(r"(?ms)^\[autoload\][^\S\n]*\n(.*?)(?=^\[|\Z)", project)
    entries = [line.strip() for line in match[1].splitlines()
               if line.strip() and not line.lstrip().startswith(";")] if match else []
    reasons = []
    if not (ROOT / SCENE.removeprefix("res://")).is_file():
        reasons.append(f"Missing {SCENE}")
    if entries != [AUTOLOAD]:
        reasons.append(f"Expected the sole [autoload] entry: {AUTOLOAD}")
    return {"ready": not reasons, "scene": SCENE, "renderer": "forward_plus", "reasons": reasons}


class Run:
    def __init__(self, seed, architecture_lab=False):
        godot = Path(environment.resolve_godot()).resolve()
        if os.name == "nt" and godot.name.lower().endswith("_console.exe"):
            godot = godot.with_name(godot.name[:-len("_console.exe")] + ".exe")
            if not godot.is_file():
                raise RuntimeError(f"Godot host executable missing: {godot}")
        self.id = secrets.token_hex(16)
        self.directory = ROOT / ".runtime" / "rogue-mcp" / self.id
        self.directory.mkdir(parents=True, exist_ok=False)
        self.sequence = 0
        self.project_sha = hashlib.sha256((ROOT / "project.godot").read_bytes()).hexdigest()
        env = os.environ.copy()
        profiles = ("APPDATA", "LOCALAPPDATA") if os.name == "nt" else ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME")
        for key in profiles:
            folder = self.directory / "profile" / key.lower()
            folder.mkdir(parents=True)
            env[key] = str(folder)
        dotnet = environment.resolve_dotnet(required=False)
        if dotnet:
            env["DOTNET_ROOT"] = str(Path(dotnet).parent)
            env["PATH"] = str(Path(dotnet).parent) + os.pathsep + env.get("PATH", "")
        self.log = self.directory / "godot.log"
        command = [str(godot), "--path", str(ROOT), "--rendering-method", "forward_plus",
                   "--language", "en", "--max-fps", "60", "--windowed", "--position", "-32000,-32000",
                   "--log-file", str(self.log), SCENE, "--", f"--rogue-mcp-dir={self.directory}", f"--run-seed={seed}"]
        if architecture_lab:
            command.append("--architecture-lab")
        with (self.directory / "process.log").open("wb") as log:
            self.process = subprocess.Popen(command, cwd=ROOT, env=env, stdin=subprocess.DEVNULL,
                                            stdout=log, stderr=subprocess.STDOUT,
                                            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)

    def request(self, operation, *, screenshot=False, timeout=15, **args):
        self.sequence += 1
        name = f"{self.sequence:06d}"
        request = self.directory / "request.json"
        temp = request.with_suffix(".tmp")
        temp.write_text(json.dumps(dict(args, id=name, operation=operation, screenshot=screenshot)), encoding="utf-8")
        temp.replace(request)
        reply = self.directory / f"{name}.json"
        deadline = time.monotonic() + timeout
        while not reply.is_file():
            code = self.process.poll()
            if code is not None or time.monotonic() >= deadline:
                raise RuntimeError(f"Godot {'exited (' + str(code) + ')' if code is not None else 'timed out'}; log: {self.log}")
            time.sleep(.025)
        result = json.loads(reply.read_text(encoding="utf-8"))
        if (result.get("pid") != self.process.pid or result.get("project_sha256") != self.project_sha
                or Path(result.get("project_root", "")).resolve() != ROOT.resolve()
                or result.get("scene") != SCENE or result.get("renderer") != "forward_plus"
                or str(result.get("window_backend", "")).lower() in ("", "headless")):
            raise RuntimeError(f"Wrong scene, project, host or renderer: {result}; log: {self.log}")
        if result.get("error"):
            raise ValueError(result["error"])
        result.update(session_id=self.id, log=str(self.log))
        if screenshot:
            image = self.directory / f"{name}.png"
            if not image.is_file():
                raise RuntimeError(f"Godot did not produce screenshot; log: {self.log}")
            result["screenshot"] = str(image)
            return [json.dumps(result, ensure_ascii=False), Image(path=str(image))]
        return result

    def close(self):
        # Only the Popen child created for this connection is stopped.
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)


def game_server():
    import threading
    lock = threading.Lock()
    run = None

    @asynccontextmanager
    async def lifespan(_server):
        nonlocal run
        try:
            yield {}
        finally:
            with lock:
                if run is not None:
                    run.close()
                    run = None

    server = FastMCP("dual-ontology-rogue", lifespan=lifespan)

    def owned(session_id):
        if run is None or run.id != session_id:
            raise ValueError("Use the session_id returned by on on this connection")
        return run

    @server.tool()
    def status() -> dict:
        """Check whether the fixed Rogue Run scene and sole GameMcp autoload exist."""
        return readiness()

    @server.tool(structured_output=False)
    def on(seed: int = 1, screenshot: bool = True, architecture_lab: bool = False):
        """Open scenes/rogue/Run.tscn directly in real Forward+ with an isolated user profile."""
        nonlocal run
        with lock:
            if run is not None:
                raise ValueError("Close the current session before starting another")
            state = readiness()
            if not state["ready"]:
                raise ValueError("; ".join(state["reasons"]))
            candidate = Run(seed, architecture_lab)
            try:
                result = candidate.request("observe", screenshot=screenshot, timeout=40)
            except BaseException:
                candidate.close()
                raise
            run = candidate
            return result

    @server.tool(structured_output=False)
    def observe(session_id: str, screenshot: bool = True):
        """Read current scene state and optionally capture the real viewport."""
        with lock:
            return owned(session_id).request("observe", screenshot=screenshot)

    @server.tool(structured_output=False)
    def step(session_id: str, operation: Literal["action", "click", "wait"], action: str = "",
             x: float = 0, y: float = 0, frames: int = 1, screenshot: bool = True):
        """Press an InputMap action, click at viewport coordinates, or wait 1–120 process frames."""
        if not 1 <= frames <= 120:
            raise ValueError("frames must be 1–120")
        with lock:
            return owned(session_id).request(operation, screenshot=screenshot, action=action, x=x, y=y, frames=frames)

    @server.tool()
    def close(session_id: str) -> dict:
        """Stop the owned Godot process; keep its screenshots and log."""
        nonlocal run
        with lock:
            host = owned(session_id)
            host.close()
            run = None
            return {"closed": True, "directory": str(host.directory)}

    return server


def environment_server():
    server = FastMCP("dual-ontology-environment")

    @server.tool()
    def prepare(local_copy: bool = False, with_blender: bool = False) -> dict:
        """Prepare the project-local Godot 4.7.2 .NET and .NET 8 runtime, optionally Blender."""
        return environment.prepare(local_copy=local_copy, with_blender=with_blender)

    return server


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--service", choices=["input", "environment"], default="input")
    parser.add_argument("--expected-project-root", type=Path)
    options = parser.parse_args()
    if options.expected_project_root and options.expected_project_root.resolve() != ROOT:
        parser.error(f"Expected project root does not match {ROOT}")
    (environment_server() if options.service == "environment" else game_server()).run()
