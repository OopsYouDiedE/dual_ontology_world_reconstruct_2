"""Resolve or prepare the project's Godot .NET and .NET SDK environment."""
import hashlib
import json
import os
import platform
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import threading
import time
import urllib.request
import uuid
import zipfile
import asset_bundle

ROOT = Path(__file__).resolve().parents[2]
LOCAL = ROOT / ".runtime"
LOCK = threading.Lock()
VERSION = re.search(r'Godot.NET.Sdk/([^"\s]+)', (ROOT / "DualOntologyWorldReconstruct2.csproj").read_text()).group(1)
BLENDER_VERSION = "4.5.3"


def command_output(command, deadline=None):
    timeout = 15 if deadline is None else max(0.001, min(15, deadline - time.monotonic()))
    if deadline is not None and time.monotonic() >= deadline: return ""
    try:
        environment = os.environ.copy()
        environment.update(DOTNET_CLI_HOME=str(LOCAL / "dotnet-home"), DOTNET_SKIP_FIRST_TIME_EXPERIENCE="1", DOTNET_CLI_TELEMETRY_OPTOUT="1")
        result = subprocess.run([str(x) for x in command], capture_output=True, text=True, env=environment,
                                encoding="utf-8", errors="replace", timeout=timeout,
                                creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        return result.stdout.strip() if result.returncode == 0 else ""
    except (OSError, subprocess.TimeoutExpired):
        return ""


def resolve_dotnet(required=True, deadline=None):
    executable = "dotnet.exe" if os.name == "nt" else "dotnet"
    for candidate in [LOCAL / "dotnet" / executable, shutil.which("dotnet")]:
        if candidate and Path(candidate).is_file() and any(
                line.startswith("8.") for line in command_output([candidate, "--list-sdks"], deadline).splitlines()):
            return str(Path(candidate).resolve())
    if required:
        raise RuntimeError(".NET 8 SDK missing. Call dual-ontology-environment.prepare first.")
    return None


def godot_candidates():
    base = LOCAL / "godot" / VERSION
    if base.exists():
        yield from base.rglob("*_console.exe")
        yield from base.rglob("Godot*_linux.x86_64")
    yield os.environ.get("DV_GODOT")
    yield shutil.which(f"Godot_v{VERSION}-stable_mono_win64_console.exe")
    yield shutil.which("godot")


def resolve_godot(required=True, deadline=None):
    for candidate in godot_candidates():
        if not candidate or not Path(candidate).is_file():
            continue
        version = command_output([candidate, "--version"], deadline)
        if version.startswith(VERSION + ".") and ".mono." in version and (Path(candidate).parent / "GodotSharp").is_dir():
            return str(Path(candidate).resolve())
    if required:
        raise RuntimeError(f"Godot {VERSION} .NET missing. Call dual-ontology-environment.prepare first.")
    return None


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "dual-ontology-environment/1.0"})
    return urllib.request.urlopen(request, timeout=30)


def download(url, destination, expected, algorithm):
    digest = hashlib.new(algorithm)
    cached = Path(os.environ.get("DV_DOWNLOAD_CACHE", str(LOCAL / "downloads"))) / url.rsplit("/", 1)[-1]
    source = cached.open("rb") if cached.is_file() else fetch(url)
    with source as response, destination.open("xb") as output:
        while chunk := response.read(1024 * 1024):
            digest.update(chunk)
            output.write(chunk)
    if digest.hexdigest().lower() != expected.lower():
        raise RuntimeError(f"{algorithm} checksum mismatch; archive was not installed: {destination}")


def unpack(archive, destination):
    destination.mkdir(parents=True)
    if str(archive).endswith((".tar.gz", ".tgz", ".tar.xz")):
        with tarfile.open(archive) as bundle:
            bundle.extractall(destination, filter="data")
        return
    with zipfile.ZipFile(archive) as bundle:
        for item in bundle.infolist():
            target = (destination / item.filename).resolve()
            target.relative_to(destination.resolve())
            if item.filename.startswith(("/", "\\")) or (item.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError("Archive contains an unsafe path or symbolic link")
        bundle.extractall(destination)
        if os.name != "nt":
            for item in bundle.infolist():
                mode = (item.external_attr >> 16) & 0o777
                if mode:
                    (destination / item.filename).chmod(mode)


def prepare_blender():
    """Install the exact official Blender used by the existing scene sources."""
    windows = os.name == "nt"
    filename = f"blender-{BLENDER_VERSION}-{'windows-x64.zip' if windows else 'linux-x64.tar.xz'}"
    target = LOCAL / "blender" / BLENDER_VERSION
    executable_name = "blender.exe" if windows else "blender"
    if target.is_dir():
        for executable in target.rglob(executable_name):
            version = command_output([executable, "--version"])
            if version.startswith("Blender " + BLENDER_VERSION):
                return {"path": str(executable), "version": BLENDER_VERSION, "verified": True, "installed": False}
        raise RuntimeError(f"An incomplete Blender directory exists; preserved for inspection: {target}")
    base = "https://download.blender.org/release/Blender4.5/"
    with fetch(base + f"blender-{BLENDER_VERSION}.sha256") as response:
        checksums = response.read().decode("utf-8")
    expected = next(line.split()[0] for line in checksums.splitlines() if line.split()[-1].lstrip("*") == filename)
    stage = LOCAL / ("install-blender-" + uuid.uuid4().hex)
    stage.mkdir(parents=True)
    archive = stage / filename
    download(base + filename, archive, expected, "sha256")
    unpack(archive, stage / "distribution")
    executable = next((stage / "distribution").rglob(executable_name))
    if not command_output([executable, "--version"]).startswith("Blender " + BLENDER_VERSION):
        raise RuntimeError("Official Blender did not validate; staging files preserved.")
    relative = executable.relative_to(stage / "distribution")
    target.parent.mkdir(parents=True, exist_ok=True)
    (stage / "distribution").rename(target)
    archive.unlink()
    if not any(stage.iterdir()):
        stage.rmdir()
    return {"path": str(target / relative), "version": BLENDER_VERSION, "verified": True,
            "installed": True, "sha256": expected, "source": base + filename}


def prepare(local_copy=False, with_blender=False):
    """Reuse a valid installation; if missing, install official binaries locally.

    local_copy requests a project-local Godot copy even if an external one exists.
    No global installation, environment-variable mutation, or recursive deletion.
    """
    if platform.system() not in ("Windows", "Linux") or platform.machine().lower() not in ("amd64", "x86_64"):
        raise RuntimeError("This project's environment installer supports Windows and Linux x64.")
    windows = os.name == "nt"
    with LOCK:
        godot = resolve_godot(False)
        dotnet = resolve_dotnet(False)
        actions = []
        if not dotnet:
            LOCAL.mkdir(exist_ok=True)
            with fetch("https://builds.dotnet.microsoft.com/dotnet/release-metadata/8.0/releases.json") as response:
                metadata = json.load(response)
            sdk = next(release["sdk"] for release in metadata["releases"] if release.get("sdk"))
            suffix = ".zip" if windows else ".tar.gz"
            package = next(file for file in sdk["files"] if file["rid"] == ("win-x64" if windows else "linux-x64") and file["url"].endswith(suffix))
            stage = LOCAL / ("install-dotnet-" + uuid.uuid4().hex)
            stage.mkdir()
            archive = stage / ("sdk" + suffix)
            download(package["url"], archive, package["hash"], "sha512")
            unpack(archive, stage / "sdk")
            if not command_output([stage / "sdk" / ("dotnet.exe" if windows else "dotnet"), "--list-sdks"]):
                raise RuntimeError("Downloaded .NET SDK did not validate; staging files preserved.")
            (stage / "sdk").rename(LOCAL / "dotnet")
            archive.unlink()
            if not any(stage.iterdir()):
                stage.rmdir()
            dotnet = resolve_dotnet()
            actions.append("installed-official-dotnet-8-sdk")
        target = LOCAL / "godot" / VERSION
        needs_copy = local_copy and godot and not Path(godot).is_relative_to(LOCAL)
        if not godot or needs_copy:
            if target.exists():
                raise RuntimeError(f"An incomplete local Godot directory exists; it was not overwritten: {target}")
            LOCAL.mkdir(exist_ok=True)
            stage = LOCAL / ("install-godot-" + uuid.uuid4().hex)
            stage.mkdir()
            distribution = stage / "distribution"
            if godot:
                source = Path(godot).parent
                distribution.mkdir()
                shutil.copy2(godot, distribution / Path(godot).name)
                regular = source / Path(godot).name.replace("_console.exe", ".exe")
                if regular.is_file(): shutil.copy2(regular, distribution / regular.name)
                shutil.copytree(source / "GodotSharp", distribution / "GodotSharp")
                actions.append("cloned-existing-mono-distribution")
            else:
                # Resolve the exact SDK version and verify the official release checksum.
                filename = f"Godot_v{VERSION}-stable_mono_{'win64' if windows else 'linux_x86_64'}.zip"
                url = f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}-stable/{filename}"
                archive = stage / filename
                with fetch(f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}-stable/SHA512-SUMS.txt") as response:
                    checksums = response.read().decode("utf-8")
                checksum = next(line.split()[0] for line in checksums.splitlines() if line.split()[-1].lstrip("*") == filename)
                download(url, archive, checksum, "sha512")
                unpack(archive, distribution)
                actions.append("downloaded-verified-official-mono-distribution")
            executable = next(distribution.rglob("*_console.exe" if windows else "Godot*_linux.x86_64"))
            if not windows:
                executable.chmod(executable.stat().st_mode | 0o111)
            version = command_output([executable, "--version"])
            if not version.startswith(VERSION + ".") or ".mono." not in version or not (executable.parent / "GodotSharp").is_dir():
                raise RuntimeError("Godot .NET validation failed; staging files preserved.")
            target.parent.mkdir(parents=True, exist_ok=True)
            distribution.rename(target)
            # Only explicitly known archive files and empty staging directories are removed.
            for file in stage.iterdir():
                if file.is_file(): file.unlink()
            if not any(stage.iterdir()):
                stage.rmdir()
            godot = resolve_godot()
        result = {"ready": True, "godot": godot, "godot_version": VERSION, "csharp": True,
                  "dotnet": dotnet, "project_local_godot": Path(godot).is_relative_to(LOCAL),
                  "python": sys.executable, "python_version": platform.python_version(), "actions": actions}
        if with_blender:
            result["blender"] = prepare_blender()
        result["campaign_assets"] = asset_bundle.ensure()
        LOCAL.mkdir(exist_ok=True)
        (LOCAL / "environment.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
        return result
