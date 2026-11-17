"""Shared production host lifecycle for automatic and input MCP services."""
from collections import deque
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
from environment import resolve_dotnet, resolve_godot
from build_runtime import DeadlineReached, build, remaining
from host_process import spawn, terminate
from concurrency_observer import ConcurrencyObserver

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import capture_provenance as provenance

ROOT = Path(__file__).resolve().parents[2]
SESSIONS = {}
COMPLETED = {}
METRICS_JOBS = {}


def collect_metrics_async(identity, endpoint, graceful):
    """Keep expensive audio analysis outside the shutdown RPC."""
    METRICS_JOBS[identity] = {"session_id": identity, "metrics_status": "running"}
    def collect():
        try:
            result = finalize_metrics(endpoint, graceful)
        except Exception as error:
            result = {"metrics_status": "error", "metrics_error": str(error)}
        METRICS_JOBS[identity] = dict(result, session_id=identity)
    threading.Thread(target=collect, name="session-metrics-" + identity, daemon=True).start()
    return {"metrics_status": "running", "metrics_poll_tool": "metrics_status"}
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
        self.expected_source = provenance.project_identity(ROOT)
        self.server_source = provenance.server_identity(ROOT, Path(__file__).with_name("server.py"))
        self.launch_scene = self.expected_source["configured_main_scene"]
        self.executable = None
        self.last_source = None
        self.snapshot_path = None
        self.scenario_path = None
        self.checkpoint_path = None
        self.checkpoint_stop_path = None
        self.metrics_directory = None
        self.concurrency_observer = None
        self.concurrency_observation_path = None
        self.concurrency_observation_error = None
        self.audio_observation_cursor = 0
        self.audio_cue_cursor = 0

    def attach(self, process):
        self.process = process
        if self.backend == "godot":
            self.concurrency_observer = ConcurrencyObserver(process.pid)
            self.concurrency_observer.start()
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
            if "error" not in response and self.backend == "godot":
                payload = response.get("result", {})
                provenance.validate_source(payload.get("source_identity"), self.expected_source,
                    pid=self.process.pid, executable=self.executable, launch_scene=self.launch_scene)
                if payload.get("checkpoint_path"):
                    actual = provenance.project_path(payload["checkpoint_path"], ROOT)
                    if actual != self.checkpoint_path:
                        raise ValueError("Host checkpoint path mismatch")
                if payload.get("metrics_directory"):
                    metrics = provenance.project_path(payload["metrics_directory"], ROOT)
                    if not metrics.name.endswith("-" + str(self.process.pid)):
                        raise ValueError("Monitor directory PID mismatch")
                    self.metrics_directory = metrics
        except (queue.Empty, TimeoutError, OSError, ValueError, RuntimeError) as error:
            self.stop()
            raise RuntimeError("Host request failed; session closed to prevent duplicate actions. " + str(error)) from error
        if "error" in response:
            raise RuntimeError(str(response["error"]))
        result = response["result"]
        if isinstance(result, dict):
            if self.backend == "cli":
                result["source_identity"] = dict(self.expected_source, process_id=self.process.pid,
                    executable_path=self.executable, verification="server-bound-process")
            self.last_source = result.get("source_identity")
            result["server_identity"] = self.server_source
            if self.snapshot_path is not None:
                result["snapshot_path"] = str(self.snapshot_path)
                result["acceptance_eligible"] = False
        if self.backend == "godot":
            result["host_errors"] = [line for line in self.logs if "ERROR:" in line or "SCRIPT ERROR" in line]
        return result

    def stop(self):
        with self.stop_lock:
            self.closed = True
            if self.concurrency_observer:
                observer, self.concurrency_observer = self.concurrency_observer, None
                directory = self.metrics_directory or (ROOT / ".runtime" / "concurrency-observations" / (str(self.process.pid) + "-" + self.token))
                try:
                    self.concurrency_observation_path = observer.stop(directory)
                except OSError as error:
                    self.concurrency_observation_error = str(error)
            if self.process: terminate(self.process)
            if self.connection:
                try: self.connection.shutdown(socket.SHUT_RDWR)
                except OSError: pass
                self.connection.close()
            if self.stream: self.stream.close()
            if self.process:
                for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
                    if stream: stream.close()



def finalize_metrics(endpoint, graceful):
    """Summarize one completed live run after its render host has stopped."""
    if endpoint.backend != "godot":
        return {"metrics_status": "not_applicable"}
    development = endpoint.snapshot_path is not None
    scenario = endpoint.scenario_path is not None
    development_flags = {"acceptance_eligible": False, "acceptance_scored": False,
                         "snapshot_path": str(endpoint.snapshot_path)} if development else {}
    if scenario:
        development_flags.update(acceptance_eligible=False, acceptance_scored=False,
                                 scenario_path=str(endpoint.scenario_path))
    if endpoint.movie_path is not None:
        return dict(development_flags, metrics_status="not_eligible", metrics_error="Fixed-step movie runs are development captures")
    if not graceful or endpoint.metrics_directory is None:
        result = dict(development_flags, metrics_status="incomplete", metrics_error="A gracefully closed monitored session is required")
        if getattr(endpoint, "concurrency_observation_path", None):
            result["concurrency_observation_path"] = str(endpoint.concurrency_observation_path)
        return result
    directory = provenance.project_path(endpoint.metrics_directory, ROOT)
    if not directory.name.endswith("-" + str(endpoint.process.pid)):
        return dict(development_flags, metrics_status="error", metrics_error="Monitor directory PID mismatch")
    output = directory / ("segment-metrics-development.json" if development else "segment-metrics.json")
    try:
        # MCP requests already run off the server event loop; the Godot render
        # process is stopped before this potentially expensive analysis.
        import importlib
        testing_path = str(ROOT / "tools/testing")
        if testing_path not in sys.path:
            sys.path.insert(0, testing_path)
        metrics = importlib.import_module("mainline_metrics")
        data = (metrics.summarize(directory, scenario_path=endpoint.scenario_path) if endpoint.scenario_path
                else metrics.summarize(directory, snapshot_path=endpoint.snapshot_path)
                if development else metrics.summarize(directory))
        if scenario and (data.get("entry") != "scenario" or data.get("acceptance_eligible") is not False
                         or data.get("scenario_path") != str(provenance.project_path(endpoint.scenario_path, ROOT))):
            raise ValueError("Scenario metrics provenance mismatch")
        if development and (data.get("acceptance_eligible") is not False
                            or data.get("snapshot_path") != str(provenance.project_path(endpoint.snapshot_path, ROOT))):
            raise ValueError("Development metrics provenance mismatch")
        provenance.validate_source(data.get("source_identity"), endpoint.expected_source, pid=endpoint.process.pid)
        observation_path = getattr(endpoint, "concurrency_observation_path", None)
        if observation_path:
            data["concurrency_observation"] = json.loads(Path(observation_path).read_text(encoding="utf-8"))
        temporary = output.with_name(output.name + ".tmp")
        try:
            temporary.write_text(json.dumps(data, ensure_ascii=False, allow_nan=False, indent=2) + "\n", encoding="utf-8")
            os.replace(temporary, output)
        finally:
            if temporary.exists():
                temporary.unlink()
        result = {"metrics_status": "complete", "metrics_summary_path": str(output),
                  "metrics_segments": list(data.get("segments", {})), "acceptance_scored": False}
        if development:
            result.update(acceptance_eligible=False, snapshot_path=data["snapshot_path"])
        if scenario:
            result.update(acceptance_eligible=False, scenario_path=data["scenario_path"])
        if observation_path:
            result["concurrency_observation_path"] = str(observation_path)
        return result
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        result = dict(development_flags, metrics_status="error", metrics_error=str(error))
        if getattr(endpoint, "concurrency_observation_path", None):
            result["concurrency_observation_path"] = str(endpoint.concurrency_observation_path)
        return result



def _movie_hash(path):
    import hashlib
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _scenario_start_ready(endpoint, observation):
    """Validate scenario host, test identity and recorder before registering it."""
    if not isinstance(observation, dict):
        raise RuntimeError("Scenario host returned an invalid observation")
    detail = observation.get("scenario_error")
    if detail:
        raise RuntimeError("Scenario entry failed: " + str(detail))
    scene = observation.get("scene")
    if scene in (None, "", "res://scenes/main/Boot.tscn"):
        return False
    if scene != "res://mcp/game/SegmentEntry.tscn":
        raise RuntimeError("Scenario entry returned unexpected scene: " + str(scene))
    if observation.get("scenario_ready") is not True:
        return False
    identity = observation.get("assessment_test_id")
    expected = endpoint.assessment_plan.get("test_id")
    if not identity:
        return False
    if not expected or identity != expected:
        raise RuntimeError("Scenario assessment test ID does not match its plan")
    recorded = observation.get("metrics_directory")
    if not recorded:
        return False
    directory = provenance.project_path(recorded, ROOT)
    if not directory.name.endswith("-" + str(endpoint.process.pid)) or endpoint.metrics_directory != directory:
        raise RuntimeError("Scenario metrics directory is not bound to the host")
    return True


def start(arguments, deadline=None):
    provenance.assert_runtime_root(ROOT)
    launch_deadline = min(deadline, time.monotonic() + 200) if deadline else time.monotonic() + 200
    session_deadline = deadline
    deadline = launch_deadline
    mode = arguments.get("mode", "cli_ai")
    if mode not in ("cli_ai", "cli_manual", "cli_auto", "godot_manual", "godot_auto"):
        raise ValueError("Unknown production session mode.")
    retired = {"scene", "test_config", "test_suite", "content_path"}.intersection(arguments)
    if retired:
        raise ValueError("Scene fixtures and content overrides are retired; use the fixed production title/new-game path.")
    controller = arguments.get("controller", "ai" if mode in ("cli_auto", "godot_auto") else "player")
    if mode == "cli_auto" and controller != "ai":
        raise ValueError("cli_auto requires controller=ai; use cli_ai for SubAgent decisions.")
    if mode in ("cli_ai", "cli_manual") and controller != "player":
        raise ValueError("cli_ai / cli_manual require controller=player.")
    endpoint = Endpoint(mode, controller, deadline)
    snapshot_path = arguments.get("snapshot_path")
    if snapshot_path is not None:
        if endpoint.backend != "godot" or mode != "godot_manual":
            raise ValueError("Snapshot restore is only available for local Godot input sessions.")
        snapshot_path = provenance.project_path(snapshot_path, ROOT)
        if not snapshot_path.is_file():
            raise ValueError("Snapshot file does not exist inside the authorized project.")
        endpoint.snapshot_path = snapshot_path
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
    elif "movie_fps" in arguments:
        raise ValueError("movie_fps requires movie_filename.")
    backend = endpoint.backend
    if arguments.get("scenario_path") and not arguments.get("assessment_plan"):
        raise ValueError("Segment entry requires its simultaneous assessment plan")
    if backend == "godot" and (arguments.get("assessment_plan") or arguments.get("decision_maker") in ("agent", "llm")):
        from assessment_plan import validate
        if not arguments.get("assessment_plan"):
            raise ValueError("Agent tests require an assessment_plan with all seven synchronous channels ready")
        endpoint.assessment_plan = validate(arguments["assessment_plan"], ROOT)
        if endpoint.assessment_plan.get("entry_mode") == "segment":
            requested = provenance.project_path(arguments.get("scenario_path", ""), ROOT)
            expected = provenance.project_path(endpoint.assessment_plan["cases"][0]["scenario_path"], ROOT)
            if snapshot_path is not None or requested != expected:
                raise ValueError("Segment test must start at its configured scenario; title/new-game entry is forbidden")
            endpoint.scenario_path = requested
        elif arguments.get("scenario_path"):
            raise ValueError("Scenario entry requires a segment assessment plan")
        if endpoint.movie_path:
            raise ValueError("Complete evaluation requires real-time capture; fixed-step movie capture cannot measure fluidity")
    # Validate capture options before reserving an output file.
    if endpoint.movie_path:
        try:
            descriptor = os.open(endpoint.movie_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError as error:
            raise ValueError("Movie file already exists; choose a new name.") from error
        os.close(descriptor)
    try:
        output_directory = build(backend, deadline)
        if backend == "cli":
            endpoint.executable = resolve_dotnet(deadline=deadline)
            endpoint.attach(spawn([endpoint.executable, output_directory / "DuelView.Cli.dll"],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE))
            open_options = {
                "controller": controller, "viewer": arguments.get("viewer", "detective"),
                "decision_maker": "engine-ai" if controller == "ai" else arguments.get("decision_maker", "agent" if mode == "cli_ai" else "human"),
                "campaign": {"seed": arguments.get("seed", 1)}, "content_path": endpoint.content_path,
                "audit": False, "developer": False}
            if arguments.get("receipt_path"):
                open_options["receipt_path"] = str(provenance.project_path(arguments["receipt_path"], ROOT))
            observation = endpoint.request({"type": "open", "options": open_options})
        else:
            with socket.socket() as reservation:
                reservation.bind(("127.0.0.1", 0))
                port = reservation.getsockname()[1]
            # Use the project's renderer, matching editor and exported gameplay.
            endpoint.executable = provenance.host_executable(resolve_godot(deadline=deadline))
            command = [endpoint.executable, "--path", ROOT, "--language", "en", "--max-fps", "60"]
            checkpoint_dir = provenance.project_path(ROOT / ".runtime/checkpoints/mcp" / endpoint.token, ROOT)
            checkpoint_dir.mkdir(parents=True, exist_ok=False)
            endpoint.checkpoint_path = checkpoint_dir / "latest.json"
            endpoint.checkpoint_stop_path = checkpoint_dir / "interrupt.request"
            if endpoint.movie_path:
                command += ["--write-movie", endpoint.movie_path, "--fixed-fps", str(arguments.get("movie_fps", 30))]
            if arguments.get("background_capture", True):
                command += ["--windowed", "--position", "-32000,-32000"]
            # The opt-in GameMcp autoload is available in every production scene.
            command += ["--", f"--dv-mcp-port={port}", f"--dv-mcp-token={endpoint.token}",
                        f"--dv-controller={controller}", f"--dv-seed={arguments.get('seed', 1)}",
                        "--dv-viewer=" + arguments.get("viewer", "detective")]
            command.append("--dv-launch-scene=" + endpoint.launch_scene)
            command.append("--dv-project-root=" + endpoint.expected_source["project_root"])
            command.append("--dv-project-sha256=" + endpoint.expected_source["project_sha256"])
            command.append("--dv-content=" + endpoint.content_path)
            if getattr(endpoint, "assessment_plan", None):
                command.append("--dv-assessment-plan=" + endpoint.assessment_plan["plan_path"])
                if endpoint.assessment_plan.get("audio_capture_enabled") is False:
                    command.append("--dv-no-audio-capture")
            command.append("--dv-checkpoint-output=" + str(endpoint.checkpoint_path))
            command.append("--dv-checkpoint-stop=" + str(endpoint.checkpoint_stop_path))
            if snapshot_path is not None:
                command.append("--dv-snapshot=" + str(snapshot_path))
            if endpoint.scenario_path is not None:
                command.append("--dv-scenario=" + str(endpoint.scenario_path))
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
            if endpoint.scenario_path is not None:
                ready_deadline = time.monotonic() + remaining(deadline, 20)
                while not _scenario_start_ready(endpoint, observation):
                    if time.monotonic() >= ready_deadline:
                        raise RuntimeError("Scenario host, assessment ID or metrics recorder did not become ready")
                    observation = endpoint.request({"type": "observe", "wait_ms": 100}, timeout=min(5, max(.1, ready_deadline - time.monotonic())))
            if snapshot_path is not None and not observation.get("checkpoint_restored", False):
                detail = observation.get("checkpoint_error") or " ".join(observation.get("host_errors", []))
                raise RuntimeError("Snapshot restoration failed: " + (detail or "restored host did not report success"))
        identity = secrets.token_hex(8)
        endpoint.deadline = session_deadline
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
    if name == "metrics_status":
        if identity not in METRICS_JOBS:
            raise ValueError("No metrics job for this session in this MCP connection")
        return dict(METRICS_JOBS[identity])
    if name == "close" and identity in COMPLETED:
        return dict(COMPLETED[identity])
    endpoint = SESSIONS.get(identity)
    if endpoint is None:
        raise ValueError("Unknown session_id in this MCP server. Start your own session.")
    with endpoint.lock:
        if name in ("event_script", "character_script", "charactor_script"):
            from blind_observation import append_observation
            return append_observation(endpoint, identity, name, arguments["text"], ROOT)
        if name == "review_visible_text":
            from text_observation import append_text_observation
            return append_text_observation(endpoint, identity, arguments["path"], arguments["text"],
                                           arguments["category"], arguments["english_verified"], ROOT)
        if name == "close":
            graceful = False
            try:
                if not endpoint.closed:
                    endpoint.request({"type": "close"}, timeout=15)
                    if endpoint.process:
                        try:
                            # The monitor allows 35 seconds to drain parallel
                            # Master/background audio workers before engine exit.
                            endpoint.process.wait(timeout=45)
                            graceful = endpoint.process.returncode == 0
                        except subprocess.TimeoutExpired:
                            graceful = False
            finally:
                endpoint.stop()
                SESSIONS.pop(identity, None)
            result = {"session_id": identity, "closed": True, "graceful_exit": graceful,
                      "source_identity": endpoint.last_source, "server_identity": endpoint.server_source}
            if endpoint.backend == "godot":
                result.update(checkpoint_path=str(endpoint.checkpoint_path), checkpoint_saved=False,
                              checkpoint_error="")
                if endpoint.snapshot_path is not None:
                    result.update(snapshot_path=str(endpoint.snapshot_path), acceptance_eligible=False)
                try:
                    envelope = json.loads(endpoint.checkpoint_path.read_text(encoding="utf-8-sig"))
                    if envelope.get("project") != "dual_ontology_world_reconstruct_2" or envelope.get("host_pid") != endpoint.process.pid:
                        raise ValueError("Final checkpoint project or host PID mismatch")
                    if envelope.get("format") != "story-checkpoint-v1":
                        raise ValueError("Final checkpoint format mismatch")
                    import base64
                    import hashlib
                    payload = base64.b64decode(envelope["payload"], validate=True)
                    if hashlib.sha256(payload).hexdigest() != envelope.get("sha256"):
                        raise ValueError("Final checkpoint checksum mismatch")
                    result["checkpoint_saved"] = True
                except (OSError, ValueError, TypeError, KeyError) as error:
                    result["checkpoint_error"] = str(error)
            if endpoint.backend == "godot" and graceful and endpoint.metrics_directory:
                result.update(collect_metrics_async(identity, endpoint, graceful))
            else:
                result.update(finalize_metrics(endpoint, graceful))
            if endpoint.concurrency_observation_error:
                result["concurrency_observation_error"] = endpoint.concurrency_observation_error
            if endpoint.movie_path:
                result.update(movie_path=str(endpoint.movie_path),
                              movie_finalized=graceful and endpoint.movie_path.is_file() and endpoint.movie_path.stat().st_size > 0,
                              movie_bytes=endpoint.movie_path.stat().st_size if endpoint.movie_path.is_file() else 0)
                if result["movie_finalized"]:
                    digest = _movie_hash(endpoint.movie_path)
                    result["movie_sha256"] = digest
                    sidecar = dict(result, capture_kind="fixed-step-runtime-video", realtime_performance_eligible=False,
                                   movie_timing="Godot Movie Maker fixed-step; use for motion/narrative evidence")
                    endpoint.movie_path.with_suffix(".avi.json").write_text(json.dumps(sidecar, ensure_ascii=False, indent=2), encoding="utf-8")
            COMPLETED[identity] = dict(result)
            return result
        operation = dict(arguments.get("operation", {})) if name == "step" else {"type": "observe"}
        if endpoint.backend == "cli":
            if operation.get("type") not in ("select", "advance", "observe", "case_reasoning"):
                raise ValueError("CLI operations: select(choice_id), advance(steps), observe.")
        elif operation.get("type") not in ("start", "select", "input_action", "click", "drag", "observe", "case_reasoning", "character", "next_case"):
            raise ValueError("Godot operations: start, select(choice_id), input_action(action,frames), click(x,y), observe.")
        if operation.get("type") == "start" and endpoint.scenario_path:
            raise ValueError("Segment sessions cannot restart from title/new-game")
        if operation.get("type") == "case_reasoning":
            query = json.loads(operation.get("case_request", "{}"))
            if not isinstance(query, dict) or query.get("operation") not in ("info", "infer", "check", "prove", "check_goal", "check_natural", "review", "strategy", "travel_actor", "sim4_plan", "sim4_execute", "questions", "scene", "seal_scene"):
                raise ValueError("Input case requests inspect the current actor's knowledge, submit a declared cognitive attempt, or plan/submit its current Sim4 action.")
            operation = dict(query, type="case_reasoning")
        if endpoint.backend == "godot":
            operation["wait_ms"] = arguments.get("wait_ms", 200)
            operation["capture_image"] = arguments.get("capture_image", True)
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
        if arguments.get("capture_audio") and endpoint.backend == "godot":
            from audio_observation import read_excerpt
            if endpoint.metrics_directory is None:
                observation["audio_preview"] = {"available": False, "reason": "The audio capture directory is not ready."}
            else:
                preview, endpoint.audio_observation_cursor, data = read_excerpt(endpoint.metrics_directory, endpoint.audio_observation_cursor)
                from audio_cue_observation import read_cues
                cues, endpoint.audio_cue_cursor = read_cues(endpoint.metrics_directory, endpoint.audio_cue_cursor)
                observation["audio_cues"] = cues
                observation["audio_preview"] = preview
                if data: observation["audio_base64"] = data
        return dict(observation, session_id=identity, mode=endpoint.mode)
