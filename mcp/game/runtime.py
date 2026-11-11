"""Shared production host lifecycle for automatic and input MCP services."""
from collections import deque
from contextlib import contextmanager
import json
import os
from pathlib import Path
import queue
import re
import secrets
import socket
import subprocess
import sys
import threading
import time
import xml.etree.ElementTree as Xml
from environment import resolve_dotnet, resolve_godot
import build_cache
import linux_display
import asset_bundle

ROOT = Path(__file__).resolve().parents[2]
SESSIONS = {}
BUILD_LOCK = threading.Lock()


class DeadlineReached(TimeoutError):
    pass


def remaining(deadline, maximum):
    if deadline is None:
        return maximum
    seconds = min(maximum, deadline - time.monotonic())
    if seconds <= 0:
        raise DeadlineReached("Configured wall-clock deadline reached.")
    return seconds


def terminate(process):
    if process.poll() is not None: return
    if os.name == "nt":
        try:
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5,
                           creationflags=subprocess.CREATE_NO_WINDOW)
        except (OSError, subprocess.TimeoutExpired):
            pass
    else:
        process.kill()
    if process.poll() is None: process.kill()
    process.wait(timeout=5)

def spawn(command, **kwargs):
    environment = os.environ.copy()
    # MCP stdio clients may intentionally inherit a minimal Windows environment.
    # NuGet resolves its user configuration under APPDATA even for local builds.
    if os.name == "nt":
        environment.setdefault("APPDATA", str(Path.home() / "AppData/Roaming"))
        environment.setdefault("LOCALAPPDATA", str(Path.home() / "AppData/Local"))
        drive = environment.get("SYSTEMDRIVE", "C:")
        for key, folder in {"ProgramFiles": "Program Files", "ProgramFiles(x86)": "Program Files (x86)",
                            "ProgramData": "ProgramData", "ALLUSERSPROFILE": "ProgramData", "WINDIR": "Windows"}.items():
            environment.setdefault(key, drive + "/" + folder)
    environment.setdefault("DOTNET_ROLL_FORWARD", "Major")
    environment.setdefault("DOTNET_CLI_HOME", str(ROOT / ".runtime/dotnet-home"))
    environment.setdefault("NUGET_PACKAGES", str(ROOT / ".runtime/nuget/packages"))
    environment.setdefault("DOTNET_SKIP_FIRST_TIME_EXPERIENCE", "1")
    environment.setdefault("DOTNET_CLI_TELEMETRY_OPTOUT", "1")
    environment.setdefault("DOTNET_EnableDiagnostics", "0")
    local_dotnet = ROOT / ".runtime/dotnet"
    if local_dotnet.is_dir():
        environment["DOTNET_ROOT"] = str(local_dotnet)
        environment["PATH"] = str(local_dotnet) + os.pathsep + environment.get("PATH", "")
    if "godot" in Path(str(command[0])).name.lower() and "--headless" not in command:
        environment = linux_display.environment(environment)
        if environment.get("DV_CLOUD_DISPLAY") == "1" and "--audio-driver" not in command:
            command = [*command, "--audio-driver", "Dummy"]
    return subprocess.Popen([str(part) for part in command], cwd=ROOT,
                            encoding="utf-8", errors="replace", text=True,
                            env=environment,
                            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
                            **kwargs)


@contextmanager
def build_gate(deadline):
    if not BUILD_LOCK.acquire(timeout=remaining(deadline, 180)):
        remaining(deadline, 1)
        raise RuntimeError("Build lock timed out")
    try:
        yield
    finally:
        BUILD_LOCK.release()


def build(backend, deadline=None):
    with build_gate(deadline):
        expected_fingerprint = build_cache.fingerprint(backend)
        project = ROOT / ("core/cli/DuelView.Cli.csproj" if backend == "cli"
                          else "DualOntologyWorldReconstruct2.csproj")
        dotnet = resolve_dotnet(deadline=deadline)
        timeout = remaining(deadline, 180)
        msbuild = None
        if os.name != "nt":
            sdks = sorted((Path(dotnet).parent / "sdk").glob("8.*/MSBuild.dll"), key=lambda path: tuple(int(part) for part in path.parent.name.split(".")))
            if sdks:
                msbuild = sdks[-1]
        command = ([dotnet, "exec", msbuild, project, "-restore", "-nologo", "-verbosity:minimal", "-m:1"]
                   if msbuild else [dotnet, "build", project, "--nologo"])
        command += ["-p:UseSharedCompilation=true", "-nodeReuse:true"]
        if backend == "godot":
            # The verified .NET distribution contains its matching Godot SDK.
            # A clean checkout can restore that exact version directly, without
            # depending on a second download of the same engine packages.
            bundled_packages = Path(resolve_godot(deadline=deadline)).parent / "GodotSharp/Tools/nupkgs"
            if not bundled_packages.is_dir():
                raise RuntimeError("The Godot .NET distribution is missing its bundled SDK packages")
            configuration = Xml.Element("configuration")
            sources = Xml.SubElement(configuration, "packageSources")
            Xml.SubElement(sources, "clear")
            Xml.SubElement(sources, "add", key="Godot-local", value=str(bundled_packages))
            Xml.SubElement(sources, "add", key="nuget.org", value="https://api.nuget.org/v3/index.json")
            restore_config = ROOT / ".runtime/NuGet.local.Config"
            restore_config.parent.mkdir(parents=True, exist_ok=True)
            content = Xml.tostring(configuration, encoding="utf-8", xml_declaration=True)
            if not restore_config.is_file() or restore_config.read_bytes() != content:
                restore_config.write_bytes(content)
            command.append("-p:RestoreConfigFile=" + str(restore_config))
        # Each live CLI owns an immutable build output. Windows must not need
        # to overwrite DLLs held by another formal input/automatic session.
        output_directory = None
        if backend == "cli":
            output_directory = ROOT / ".runtime/hosts" / ("cli-" + secrets.token_hex(12))
            command += (["-p:Configuration=Release", "-p:OutputPath=" + str(output_directory)]
                        if msbuild else ["--configuration", "Release", "--output", output_directory])
            command += ["-p:DvIntermediateRoot=" + str(output_directory / ".intermediate")]
        cached = build_cache.reuse(backend, output_directory)
        exit_code = 0
        if not cached:
            process = spawn(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            try:
                output, _ = process.communicate(timeout=timeout)
            except subprocess.TimeoutExpired:
                terminate(process)
                process.communicate()
                if deadline is not None and time.monotonic() >= deadline:
                    raise DeadlineReached("Deadline reached during build; no game session was started.")
                raise RuntimeError("Build timed out; no game session was started.")
            exit_code = process.returncode
            build_logs = ROOT / ".runtime/build-logs"
            build_logs.mkdir(parents=True, exist_ok=True)
            original_build_log = build_logs / (backend + "-" + str(time.time_ns()) + ".txt")
            original_build_log.write_text("COMMAND " + " ".join(str(part) for part in command) + "\n" + output
                                          + "\nEXIT " + str(exit_code) + "\n", encoding="utf-8")
            if exit_code:
                raise RuntimeError("Build failed:\n" + output[-10000:])
        if output_directory is not None:
            check_command = [dotnet, output_directory / "DuelView.Cli.dll", "--verify-character-actions"]
            check = spawn(check_command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            try:
                check_output, _ = check.communicate(timeout=remaining(deadline, 60))
            except subprocess.TimeoutExpired:
                terminate(check)
                check_output, _ = check.communicate()
                (output_directory / "character-actions-raw.txt").write_text(check_output, encoding="utf-8")
                raise DeadlineReached("Deadline reached during character-action checks; no game session was started.")
            (output_directory / "character-actions-raw.txt").write_text(
                "COMMAND " + " ".join(str(part) for part in check_command) + "\n" + check_output
                + "\nEXIT " + str(check.returncode) + "\n", encoding="utf-8")
            if check.returncode:
                raise RuntimeError("Character-action checks failed:\n" + check_output[-10000:])
            if not cached:
                build_cache.record(backend, output_directory, original_build_log, expected_fingerprint, "Release")
            build_receipt = {
                "project": str(project), "configuration": cached["configuration"] if cached else "Release",
                "completed_epoch": time.time(), "exit_code": exit_code,
                "reused_unchanged_compilation": bool(cached),
                "source_fingerprint": build_cache.fingerprint(backend),
                "original_build_log": cached["build_log"] if cached else str(original_build_log)}
            (output_directory / "formal-build.yaml").write_text("".join(
                key + ": " + json.dumps(value, ensure_ascii=False) + "\n"
                for key, value in build_receipt.items()), encoding="utf-8")
        if backend == "godot":
            asset_bundle.ensure()
            # A fresh checkout needs actual Godot import metadata for GLB/font/
            # texture resources before the production host can load them.
            import_command = [resolve_godot(deadline=deadline), "--headless", "--path", ROOT,
                              "--editor", "--import", "--audio-driver", "Dummy"]
            process = spawn(import_command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            try:
                import_output, _ = process.communicate(timeout=remaining(deadline, 240))
            except subprocess.TimeoutExpired:
                terminate(process)
                import_output, _ = process.communicate()
                (ROOT / ".runtime/godot-resource-import.log").write_text(import_output, encoding="utf-8")
                raise RuntimeError("Godot resource import timed out before the live game started")
            (ROOT / ".runtime/godot-resource-import.log").write_text(import_output, encoding="utf-8")
            if process.returncode:
                raise RuntimeError("Godot resource import failed:\n" + import_output[-6000:])
        return output_directory


def drain(stream, target):
    for line in stream:
        if isinstance(target, queue.Queue):
            target.put(line)
        else:
            target.append(line.rstrip())
    if isinstance(target, queue.Queue):
        target.put(None)


class Endpoint:
    def __init__(self, mode, controller, deadline=None):
        self.mode, self.controller = mode, controller
        self.backend = "cli" if mode.startswith("cli") else "godot"
        self.lock = threading.Lock()
        self.logs = deque(maxlen=32)
        self.lines = queue.Queue()
        self.process = None
        self.connection = None
        self.stream = None
        self.serial = 0
        self.token = secrets.token_hex(24)
        self.closed = False
        self.content_path = str(ROOT / ("assets/data/scenarios/campaign.dv" if self.backend == "cli" else "assets/data/scenarios/life_simulation.dv"))
        self.deadline = deadline
        self.stop_lock = threading.RLock()
        self.movie_path = None

    def attach(self, process):
        self.process = process
        threading.Thread(target=drain, args=(process.stderr, self.logs), daemon=True).start()
        threading.Thread(target=drain, args=(process.stdout, self.lines if self.backend == "cli" else self.logs),
                         daemon=True).start()

    def request(self, operation, timeout=45):
        if self.closed:
            raise RuntimeError("Session is closed; start a new session.")
        timeout = remaining(self.deadline, timeout)
        self.serial += 1
        message = dict(operation, id=self.serial)
        try:
            if self.backend == "cli":
                self.process.stdin.write(json.dumps(message, ensure_ascii=False) + "\n")
                self.process.stdin.flush()
                line = self.lines.get(timeout=timeout)
            else:
                self.connection.settimeout(timeout)
                self.connection.sendall((json.dumps(dict(message, token=self.token), ensure_ascii=False) + "\n").encode())
                line = self.stream.readline(16 * 1024 * 1024)
            if not line:
                raise RuntimeError("Host exited: " + "\n".join(self.logs)[-4000:])
            response = json.loads(line)
            if response.get("id") != self.serial:
                raise RuntimeError("Host response id mismatch.")
        except (queue.Empty, TimeoutError, OSError, ValueError, RuntimeError) as error:
            self.stop()
            raise RuntimeError("Host request failed; session closed to prevent duplicate actions. " + str(error)) from error
        if "error" in response:
            raise RuntimeError(str(response["error"]))
        result = response["result"]
        if self.backend == "godot":
            result["host_errors"] = [line for line in self.logs if "ERROR:" in line or "SCRIPT ERROR" in line]
        return result

    def stop(self):
        with self.stop_lock:
            self.closed = True
            if self.process: terminate(self.process)
            if self.connection:
                try: self.connection.shutdown(socket.SHUT_RDWR)
                except OSError: pass
                self.connection.close()
            if self.stream: self.stream.close()
            if self.process:
                for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
                    if stream: stream.close()


def start(arguments, deadline=None):
    mode = arguments.get("mode", "cli_ai")
    controller = arguments.get("controller", "ai" if mode in ("cli_auto", "godot_auto") else "player")
    if mode == "cli_auto" and controller != "ai":
        raise ValueError("cli_auto requires controller=ai; use cli_ai for SubAgent decisions.")
    if mode in ("cli_ai", "cli_manual") and controller != "player":
        raise ValueError("cli_ai / cli_manual require controller=player.")
    endpoint = Endpoint(mode, controller, deadline)
    movie_filename = arguments.get("movie_filename")
    if movie_filename is not None:
        if endpoint.backend != "godot" or mode != "godot_manual":
            raise ValueError("Movie capture is available only for formal Godot input sessions.")
        if not arguments.get("background_capture", True):
            raise ValueError("Movie capture requires background_capture=true.")
        if not isinstance(movie_filename, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,79}\.avi", movie_filename):
            raise ValueError("movie_filename must be a simple .avi basename.")
        if movie_filename.split(".", 1)[0].upper() in {"CON", "PRN", "AUX", "NUL", *(f"COM{i}" for i in range(1, 10)), *(f"LPT{i}" for i in range(1, 10))}:
            raise ValueError("movie_filename uses a reserved Windows name.")
        fps = arguments.get("movie_fps", 30)
        if isinstance(fps, bool) or not isinstance(fps, int) or not 1 <= fps <= 60:
            raise ValueError("movie_fps must be an integer between 1 and 60.")
        movie_directory = (ROOT / "artifacts" / "recordings").resolve()
        if not movie_directory.is_relative_to(ROOT.resolve()):
            raise ValueError("Movie directory must remain inside the project.")
        movie_directory.mkdir(parents=True, exist_ok=True)
        endpoint.movie_path = movie_directory / movie_filename
        try:
            descriptor = os.open(endpoint.movie_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError as error:
            raise ValueError("Movie file already exists; choose a new name.") from error
        os.close(descriptor)
    elif "movie_fps" in arguments:
        raise ValueError("movie_fps requires movie_filename.")
    endpoint.content_path = str(Path(arguments.get("content_path", endpoint.content_path)).resolve())
    backend = endpoint.backend
    try:
        output_directory = build(backend, deadline)
        if backend == "cli":
            endpoint.attach(spawn([resolve_dotnet(deadline=deadline), output_directory / "DuelView.Cli.dll"],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE))
            open_options = {
                "controller": controller, "viewer": arguments.get("viewer", "detective"),
                "decision_maker": "engine-ai" if controller == "ai" else arguments.get("decision_maker", "agent" if mode == "cli_ai" else "human"),
                "campaign": {"seed": arguments.get("seed", 1)}, "content_path": endpoint.content_path,
                "audit": False, "developer": False}
            if arguments.get("receipt_path"):
                open_options["receipt_path"] = str(Path(arguments["receipt_path"]).resolve())
            observation = endpoint.request({"type": "open", "options": open_options})
        else:
            with socket.socket() as reservation:
                reservation.bind(("127.0.0.1", 0))
                port = reservation.getsockname()[1]
            # Use the project's renderer, matching editor and exported gameplay.
            command = [resolve_godot(deadline=deadline), "--path", ROOT / "."]
            if endpoint.movie_path:
                command += ["--write-movie", endpoint.movie_path, "--fixed-fps", str(arguments.get("movie_fps", 30))]
            if arguments.get("background_capture", True):
                command += ["--windowed", "--position", "-32000,-32000"]
            scene = arguments.get("scene", "")
            if mode == "scene":
                path = (ROOT / "." / scene.removeprefix("res://")).resolve()
                if not any(path.is_relative_to((ROOT / folder).resolve()) for folder in ("scenes", "tools")):
                    raise ValueError("Scene must be inside scenes/ or tools/.")
                if path.suffix != ".tscn" or not path.is_file():
                    raise ValueError("scene must name an existing scenes/*.tscn resource.")
                command.append("res://" + path.relative_to(ROOT / ".").as_posix())
            elif scene:
                raise ValueError("scene is only accepted in mode=scene.")
            # The opt-in GameMcp autoload is available in every production scene.
            command += ["--", f"--dv-mcp-port={port}", f"--dv-mcp-token={endpoint.token}",
                        f"--dv-controller={controller}", f"--dv-seed={arguments.get('seed', 1)}",
                        "--dv-viewer=" + arguments.get("viewer", "detective")]
            command.append("--dv-content=" + endpoint.content_path)
            save_slot = arguments.get("save_slot", endpoint.token)
            if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", save_slot):
                raise ValueError("Invalid save slot")
            command.append("--dv-save-slot=" + save_slot)
            if arguments.get("background_capture", True):
                command.append("--dv-background-capture")
            else:
                command.append("--dv-visible-window")
            endpoint.attach(spawn(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE))
            connect_deadline = time.monotonic() + remaining(deadline, 30)
            while True:
                try:
                    endpoint.connection = socket.create_connection(("127.0.0.1", port), timeout=remaining(deadline, 1))
                    break
                except OSError:
                    if endpoint.process.poll() is not None or time.monotonic() >= connect_deadline:
                        raise RuntimeError("Godot bridge did not start: " + "\n".join(endpoint.logs)[-4000:])
                    time.sleep(.1)
            endpoint.stream = endpoint.connection.makefile("rb")
            observation = endpoint.request({"type": "observe", "wait_ms": 300})
        identity = secrets.token_hex(8)
        SESSIONS[identity] = endpoint
        return dict(observation, session_id=identity, mode=mode,
                    **({"movie_path": str(endpoint.movie_path), "movie_fps": arguments.get("movie_fps", 30),
                        "movie_timing": "fixed-step; not real-time performance"} if endpoint.movie_path else {}))
    except BaseException:
        endpoint.stop()
        if endpoint.movie_path and endpoint.movie_path.is_file() and endpoint.movie_path.stat().st_size == 0:
            endpoint.movie_path.unlink()
        raise


def execute(name, arguments):
    if name == "on":
        return start(arguments)
    identity = arguments["session_id"]
    endpoint = SESSIONS.get(identity)
    if endpoint is None:
        raise ValueError("Unknown session_id in this MCP server. Start your own session.")
    with endpoint.lock:
        if name == "close":
            graceful = False
            try:
                if not endpoint.closed:
                    endpoint.request({"type": "close"}, timeout=15)
                    if endpoint.process:
                        try:
                            endpoint.process.wait(timeout=30)
                            graceful = endpoint.process.returncode == 0
                        except subprocess.TimeoutExpired:
                            graceful = False
            finally:
                endpoint.stop()
                SESSIONS.pop(identity, None)
            result = {"session_id": identity, "closed": True, "graceful_exit": graceful}
            if endpoint.movie_path:
                result.update(movie_path=str(endpoint.movie_path),
                              movie_finalized=graceful and endpoint.movie_path.is_file() and endpoint.movie_path.stat().st_size > 0,
                              movie_bytes=endpoint.movie_path.stat().st_size if endpoint.movie_path.is_file() else 0)
            return result
        operation = dict(arguments.get("operation", {})) if name == "step" else {"type": "observe"}
        if endpoint.backend == "cli":
            if operation.get("type") not in ("select", "advance", "observe", "case_reasoning"):
                raise ValueError("CLI operations: select(choice_id), advance(steps), observe.")
        elif operation.get("type") not in ("start", "load", "select", "input_action", "click", "observe", "reload_content", "case_reasoning", "character"):
            raise ValueError("Godot operations: start, select(choice_id), input_action(action,frames), click(x,y), observe.")
        if operation.get("type") == "case_reasoning":
            query = json.loads(operation.get("case_request", "{}"))
            if not isinstance(query, dict) or query.get("operation") not in ("info", "infer", "check", "prove", "check_goal", "check_natural", "review", "strategy", "travel_actor", "sim4_plan", "sim4_execute", "questions", "scene", "seal_scene"):
                raise ValueError("Input case requests inspect the current actor's knowledge, submit a declared cognitive attempt, or plan/submit its current Sim4 action.")
            operation = dict(query, type="case_reasoning")
        if endpoint.backend == "godot":
            operation["wait_ms"] = arguments.get("wait_ms", 200)
            operation["capture_image"] = arguments.get("capture_image", True)
        if operation.get("type") == "reload_content" and not operation.get("path") and "content_source" not in operation:
            operation["path"] = endpoint.content_path
        # A legal CLI batch can complete up to 100 formal actions. Give it a
        # bounded host budget inside the input client's 240-second timeout;
        # a failed request still closes the session and is never retried.
        request_timeout = 45
        if (endpoint.backend == "cli" and operation.get("type") in ("advance", "select")
                and isinstance(operation.get("steps", 1), int) and operation.get("steps", 1) > 1):
            request_timeout = 180
        observation = endpoint.request(operation, timeout=request_timeout)
        if not isinstance(observation, dict):
            observation = {"case_reasoning": observation}
        return dict(observation, session_id=identity, mode=endpoint.mode)
