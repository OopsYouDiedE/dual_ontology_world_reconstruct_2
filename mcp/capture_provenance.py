"""Project-bound capture identity shared by the MCP servers and local clients."""
import hashlib
import json
import os
from pathlib import Path
import re
import time


def project_path(value, root, *, allow_external=False):
    root = Path(root).resolve()
    text = str(value)
    if text.startswith("res://"):
        text = text[6:]
    elif "://" in text:
        raise ValueError("Unsupported capture path scheme")
    path = Path(text)
    if os.name == "nt" and (bool(path.drive) != bool(path.root)):
        raise ValueError("Capture paths need a project-relative path or a complete absolute path")
    path = (path if path.is_absolute() else root / path).resolve()
    if not allow_external and not path.is_relative_to(root):
        raise ValueError("Capture path escapes the expected project: " + str(path))
    return path


def assert_root(root, expected=None):
    root = Path(root).resolve()
    expected = expected or os.environ.get("DV_EXPECTED_PROJECT_ROOT")
    if expected and Path(expected).resolve() != root:
        raise ValueError("MCP project root mismatch: expected " + str(Path(expected).resolve()) + "; server uses " + str(root))
    if not (root / "project.godot").is_file():
        raise ValueError("Expected project.godot is missing: " + str(root))
    return root


def project_identity(root):
    root = assert_root(root)
    content = (root / "project.godot").read_bytes()
    match = re.search(r'^run/main_scene="([^"]+)"', content.decode("utf-8-sig"), re.MULTILINE)
    return {"project_root": str(root), "project_sha256": hashlib.sha256(content).hexdigest(),
            "configured_main_scene": match.group(1) if match else ""}


def server_identity(root, server):
    return dict(project_identity(root), server_path=str(Path(server).resolve()),
                server_pid=os.getpid(), python_executable=str(Path(os.sys.executable).resolve()))


def host_executable(executable):
    """Launch the actual Windows host, so Popen owns the PID Godot reports."""
    executable = Path(executable).resolve()
    if os.name == "nt" and executable.name.lower().endswith("_console.exe"):
        direct = executable.with_name(executable.name[:-len("_console.exe")] + ".exe")
        if not direct.is_file():
            raise ValueError("Godot host executable beside console launcher is missing: " + str(direct))
        return str(direct)
    return str(executable)


def validate_source(source, expected, *, pid=None, executable=None, launch_scene=None):
    if not isinstance(source, dict):
        raise ValueError("Host source_identity is missing; capture rejected")
    if not source.get("project_root") or not Path(source["project_root"]).is_absolute():
        raise ValueError("Host absolute project root is missing; capture rejected")
    if Path(source.get("project_root", "")).resolve() != Path(expected["project_root"]).resolve():
        raise ValueError("Host project root mismatch; capture rejected")
    for key in ("project_sha256", "configured_main_scene"):
        if source.get(key) != expected[key]:
            raise ValueError("Host " + key + " mismatch; capture rejected")
    if project_identity(expected["project_root"]) != {key: expected[key] for key in
            ("project_root", "project_sha256", "configured_main_scene")}:
        raise ValueError("Project identity changed during capture; open a new session")
    if pid is not None and source.get("process_id") != pid:
        raise ValueError("Host process ID mismatch; capture rejected")
    if executable is not None and Path(source.get("executable_path", "")).resolve() != Path(executable).resolve():
        raise ValueError("Host executable mismatch; capture rejected")
    if launch_scene is not None and source.get("launch_scene") != launch_scene:
        raise ValueError("Host launch scene mismatch; capture rejected")
    return source


def save_image_sidecar(path, data):
    path = Path(path)
    metadata = {key: data[key] for key in ("source_identity", "server_identity", "session_id",
                "scene", "observation_id", "capture_kind") if key in data}
    metadata.update(image_path=str(path.resolve()), image_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                    captured_epoch=time.time())
    path.with_suffix(path.suffix + ".json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")


def verify_image(path, root, *, allow_fixture=False):
    path = project_path(path, root)
    candidates = (path.with_suffix(path.suffix + ".json"), path.with_suffix(".json"))
    sidecar = next((candidate for candidate in candidates if candidate.is_file()), None)
    if sidecar is None:
        raise ValueError("Capture source sidecar is missing: " + str(path))
    metadata = json.loads(sidecar.read_text(encoding="utf-8-sig"))
    validate_source(metadata.get("source_identity"), project_identity(root))
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if metadata.get("image_sha256") != digest:
        raise ValueError("Capture image hash mismatch: " + str(path))
    if metadata.get("acceptance_eligible") is False and not allow_fixture:
        raise ValueError("Development fixture capture requires --allow-fixture")
    return {"provenance_valid": True, "image_path": str(path), "sidecar_path": str(sidecar),
            "image_sha256": digest, "source_identity": metadata["source_identity"],
            "capture_kind": metadata.get("capture_kind", "live-mcp"), "acceptance_scored": False}
