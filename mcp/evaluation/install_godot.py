"""Install the official Linux Godot 4.7.2 standard build inside this project.

Downloads and the extracted executable are hash-checked; --import additionally
runs the real project editor headlessly under its existing absolute goal cutoff.
This is a development setup step, never a gameplay or acceptance result.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
import urllib.request
import zipfile

import common as c

RELEASE = "https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/"
EXECUTABLE = "Godot_v4.7.2-stable_linux.x86_64"
ARCHIVE = EXECUTABLE + ".zip"
MANIFEST = "SHA512-SUMS.txt"
DOWNLOADS = c.ROOT / ".runtime/downloads"
INSTALL = c.ROOT / ".runtime/godot/4.7.2"
MAX_DOWNLOAD = 512 * 1024 * 1024


def remaining_goal() -> float:
    from server import _goal
    return _goal()[1]


def download(url: str, destination: Path, limit: int) -> None:
    remaining = remaining_goal()
    destination = c.project_path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".download-", dir=destination.parent)
    try:
        request = urllib.request.Request(url, headers={"User-Agent": "dual-ontology-evaluation/1.0"})
        with os.fdopen(fd, "wb") as target, urllib.request.urlopen(request, timeout=min(90.0, remaining)) as source:
            total = 0
            while chunk := source.read(1024 * 1024):
                remaining_goal()
                total += len(chunk)
                if total > limit:
                    raise ValueError("Official download exceeds the safety limit")
                target.write(chunk)
            target.flush()
            os.fsync(target.fileno())
        remaining_goal()
        os.replace(name, destination)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def hash_file(path: Path, algorithm: str) -> str:
    digest = hashlib.new(algorithm)
    with c.project_path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def expected_hash(manifest: Path) -> str:
    matches = []
    for line in c.project_path(manifest).read_text(encoding="utf-8").splitlines():
        match = re.fullmatch(r"([0-9a-fA-F]{128})\s+\*?(.+)", line.strip())
        if match and match.group(2) == ARCHIVE:
            matches.append(match.group(1).lower())
    if len(matches) != 1:
        raise ValueError("Official checksum manifest must contain exactly one archive entry")
    return matches[0]


def install(offline: bool = False) -> dict:
    c.assert_project()
    remaining_goal()
    if os.name != "posix" or os.uname().sysname != "Linux" or os.uname().machine not in ("x86_64", "amd64"):
        raise RuntimeError("This installer covers Linux x86-64 standard Godot only; use the appropriate official build for other systems")
    DOWNLOADS.mkdir(parents=True, exist_ok=True)
    INSTALL.mkdir(parents=True, exist_ok=True)
    manifest, archive = DOWNLOADS / MANIFEST, DOWNLOADS / ARCHIVE
    if not offline:
        download(RELEASE + MANIFEST, manifest, 1024 * 1024)
    if not manifest.is_file():
        raise ValueError("Cached official checksum manifest missing; omit --offline to download it")
    expected = expected_hash(manifest)
    if not archive.is_file() or hash_file(archive, "sha512") != expected:
        if offline:
            raise ValueError("Cached Godot archive is missing or does not match the manifest")
        download(RELEASE + ARCHIVE, archive, MAX_DOWNLOAD)
    if hash_file(archive, "sha512") != expected:
        raise ValueError("Godot archive SHA-512 mismatch; no executable was installed")
    with zipfile.ZipFile(archive) as package:
        members = [entry for entry in package.infolist() if entry.filename == EXECUTABLE]
        if len(members) != 1 or members[0].is_dir() or members[0].file_size > MAX_DOWNLOAD:
            raise ValueError("Unexpected Godot archive layout")
        binary = c.project_path(INSTALL / EXECUTABLE)
        fd, temporary = tempfile.mkstemp(prefix=".godot-", dir=INSTALL)
        try:
            with os.fdopen(fd, "wb") as target, package.open(members[0]) as source:
                shutil.copyfileobj(source, target, length=1024 * 1024)
                target.flush()
                os.fsync(target.fileno())
            expected_binary = hash_file(Path(temporary), "sha256")
            remaining_goal()
            if not binary.is_file() or hash_file(binary, "sha256") != expected_binary:
                os.chmod(temporary, 0o755)
                os.replace(temporary, binary)
            else:
                binary.chmod(binary.stat().st_mode | 0o100)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
    receipt = {"project": c.provenance.project_identity(c.ROOT), "release_url": RELEASE,
               "archive": str(archive), "archive_sha512": expected,
               "manifest_sha256": c.sha256(manifest), "executable": str(binary),
               "executable_sha256": c.sha256(binary), "installed_at": c.now(),
               "edition": "standard, Linux x86-64", "acceptance_eligible": False}
    c.write_json(INSTALL / "install-receipt.json", receipt)
    return receipt


def import_project(binary: Path) -> dict:
    # Import is also a launched test process: inherit the existing task cutoff.
    from server import _goal
    _, remaining = _goal()
    directory = c.project_path(c.ROOT / ".runtime/import")
    directory.mkdir(parents=True, exist_ok=True)
    command = [str(binary), "--headless", "--path", str(c.ROOT), "--editor", "--import"]
    started = time.monotonic()
    log_path = directory / "godot-import.log"
    with c.exclusive_run_lock(), log_path.open("w", encoding="utf-8") as log:
        process = subprocess.Popen(command, cwd=c.ROOT, stdin=subprocess.DEVNULL, stdout=log,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            identity = c.inspect_process(process.pid, expected_exe=binary, required=["--path", str(c.ROOT)])
            try:
                process.wait(timeout=min(600.0, remaining))
                timed_out = False
            except subprocess.TimeoutExpired:
                timed_out = True
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
        except BaseException:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
            raise
    lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
    errors = [line for line in lines if line.startswith(("ERROR:", "SCRIPT ERROR:"))]
    version_ok = any(line.startswith("Godot Engine v4.7.2.") for line in lines)
    receipt = {"identity": c.provenance.project_identity(c.ROOT), "pid": process.pid,
               "process": identity, "command": command, "exit_code": process.returncode,
               "timed_out": timed_out, "wall_seconds": round(time.monotonic() - started, 3),
               "version_ok": version_ok, "errors": errors, "log": str(log_path),
               "development_only": True, "acceptance_scored": False}
    c.write_json(directory / "receipt.json", receipt)
    if timed_out or process.returncode != 0 or not version_ok or errors:
        raise RuntimeError("Godot import failed; inspect " + str(directory / "receipt.json"))
    return receipt


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline", action="store_true", help="use previously downloaded and SHA-512-verified files")
    parser.add_argument("--import", dest="run_import", action="store_true", help="run the real headless project import")
    args = parser.parse_args()
    result = {"install": install(args.offline)}
    if args.run_import:
        result["import"] = import_project(Path(result["install"]["executable"]))
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
