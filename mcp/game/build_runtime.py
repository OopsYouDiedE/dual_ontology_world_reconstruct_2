"""Build and resource preparation for production game hosts."""
from contextlib import contextmanager
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
        yield
    finally:
        BUILD_LOCK.release()


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
