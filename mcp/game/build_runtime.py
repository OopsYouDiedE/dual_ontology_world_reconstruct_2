"""Build and resource preparation for production game hosts."""
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import threading
import time
import xml.etree.ElementTree as Xml

import asset_bundle
import build_cache
from environment import resolve_dotnet, resolve_godot
from host_process import spawn, terminate


ROOT = Path(__file__).resolve().parents[2]
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


@contextmanager
def _build_gate(deadline):
    if not BUILD_LOCK.acquire(timeout=remaining(deadline, 180)):
        remaining(deadline, 1)
        raise RuntimeError("Build lock timed out")
    try:
        lock = ROOT / ".runtime/engine-prepare.lock"
        lock.parent.mkdir(parents=True, exist_ok=True)
        with lock.open("a+b") as stream:
            end = time.monotonic() + remaining(deadline, 180)
            while True:
                stream.seek(0)
                try:
                    if os.name == "nt":
                        import msvcrt
                        msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
                    else:
                        import fcntl
                        fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    if time.monotonic() >= end:
                        raise DeadlineReached("Timed out waiting for shared workspace preparation")
                    time.sleep(min(.1, remaining(deadline, .1)))
                except OSError as error:
                    # Windows reports byte-range contention as EACCES.
                    if os.name != "nt" or error.errno != 13:
                        raise
                    if time.monotonic() >= end:
                        raise DeadlineReached("Timed out waiting for shared workspace preparation") from error
                    time.sleep(min(.1, remaining(deadline, .1)))
            yield  # Closing the file releases its advisory lock on both platforms.
    finally:
        BUILD_LOCK.release()


_IMPORT_INPUTS = {".import", ".gd", ".gdshader", ".cs", ".tscn", ".tres", ".res",
                  ".uid", ".godot", ".glb", ".gltf", ".fbx", ".obj", ".png", ".webp",
                  ".jpg", ".jpeg", ".svg", ".wav", ".ogg", ".mp3", ".ttf", ".otf",
                  ".po", ".csv", ".blend", ".gdignore"}


def _import_stamp(godot, deadline):
    # Git supplies the workspace resource inventory, including untracked source
    # edits, while excluding runtime captures and Godot's generated cache.
    result = subprocess.run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                            cwd=ROOT, stdin=subprocess.DEVNULL, capture_output=True,
                            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
                            timeout=remaining(deadline, 10), check=True)
    paths = {Path(os.fsdecode(part)) for part in result.stdout.split(b"\0") if part}
    if asset_bundle.MANIFEST.is_file():
        paths.update(Path(item["path"]) for item in json.loads(asset_bundle.MANIFEST.read_text(encoding="utf-8"))["files"])
    digest = hashlib.sha256()
    eligible = (path for path in paths if path.suffix in _IMPORT_INPUTS or path.name == ".gdignore")
    cache_files = sorted((ROOT / ".godot/editor").glob("filesystem_cache[0-9]*"))
    for path in [Path(godot), *sorted(eligible), Path(".godot/imported"), *cache_files]:
        try:
            data = (ROOT / path).stat()
            stamp = (data.st_size, data.st_mtime_ns)
        except FileNotFoundError:
            stamp = None
        digest.update(repr((str(path), stamp)).encode())
    return digest.hexdigest()


def _prepare_resources(godot, deadline):
    cache = ROOT / ".runtime/godot-resource-import.json"
    stamp = _import_stamp(godot, deadline)
    if (cache.is_file() and any((ROOT / ".godot/editor").glob("filesystem_cache[0-9]*"))
            and (ROOT / ".godot/imported").is_dir()
            and cache.read_text(encoding="utf-8") == stamp):
        return
    cache.unlink(missing_ok=True)
    asset_bundle.ensure()
    # This is the editor importer, not the rendered gameplay process.
    command = [godot, "--headless", "--path", ROOT, "--editor", "--import", "--audio-driver", "Dummy"]
    process = spawn(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    log = ROOT / ".runtime/godot-resource-import.log"
    try:
        output, _ = process.communicate(timeout=remaining(deadline, 180))
    except subprocess.TimeoutExpired:
        terminate(process)
        output, _ = process.communicate()
        log.write_text(output, encoding="utf-8")
        raise RuntimeError("Godot resource import timed out before the live game started")
    log.write_text(output, encoding="utf-8")
    if process.returncode:
        raise RuntimeError("Godot resource import failed:\n" + output[-6000:])
    cache.write_text(_import_stamp(godot, deadline), encoding="utf-8")


def build(backend, deadline=None):
    """Build one production backend and prepare the assets it needs to launch."""
    with _build_gate(deadline):
        expected_fingerprint = build_cache.fingerprint(backend)
        project = ROOT / ("core/cli/DuelView.Cli.csproj" if backend == "cli"
                          else "DualOntologyWorldReconstruct2.csproj")
        dotnet = resolve_dotnet(deadline=deadline)
        timeout = remaining(deadline, 180)
        msbuild = None
        if os.name != "nt":
            sdks = sorted((Path(dotnet).parent / "sdk").glob("8.*/MSBuild.dll"),
                          key=lambda path: tuple(int(part) for part in path.parent.name.split(".")))
            if sdks:
                msbuild = sdks[-1]
        command = ([dotnet, "exec", msbuild, project, "-restore", "-nologo", "-verbosity:minimal", "-m:1"]
                   if msbuild else [dotnet, "build", project, "--nologo"])
        command += ["-p:UseSharedCompilation=true", "-nodeReuse:true"]
        if backend == "godot":
            godot = resolve_godot(deadline=deadline)
            bundled_packages = Path(godot).parent / "GodotSharp/Tools/nupkgs"
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

        output_directory = None
        if backend == "cli":
            output_directory = ROOT / ".runtime/hosts" / ("cli-" + secrets.token_hex(12))
            command += (["-p:Configuration=Release", "-p:OutputPath=" + str(output_directory)]
                        if msbuild else ["--configuration", "Release", "--output", output_directory])
            command += ["-p:DvIntermediateRoot=" + str(output_directory / ".intermediate")]
        # The Godot Debug output is a shared, verified workspace artifact.
        godot_output = ROOT / ".godot/mono/temp/bin/Debug"
        cached = build_cache.reuse(backend, output_directory, fingerprint_value=expected_fingerprint)
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
            if not cached:
                build_cache.record(backend, godot_output, original_build_log, expected_fingerprint, "Debug")
            _prepare_resources(godot, deadline)
        return output_directory
