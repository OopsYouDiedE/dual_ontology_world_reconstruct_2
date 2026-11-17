"""Process spawning and teardown shared by production game entry points."""
import os
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import capture_provenance as provenance

import linux_display

ROOT = Path(__file__).resolve().parents[2]


def terminate(process):
    """Stop one owned process tree and wait until its handles are released."""
    if process.poll() is not None:
        return
    if os.name == "nt":
        try:
            subprocess.run(
                ["taskkill", "/PID", str(process.pid), "/T", "/F"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=5,
                creationflags=subprocess.CREATE_NO_WINDOW,
            )
        except (OSError, subprocess.TimeoutExpired):
            pass
    else:
        process.kill()
    if process.poll() is None:
        process.kill()
    process.wait(timeout=5)


def spawn(command, *, user_data_root=None, **kwargs):
    """Start a project-owned process with the reproducible tool environment."""
    provenance.assert_runtime_root(ROOT)
    if "--path" in command:
        index = command.index("--path")
        if index + 1 >= len(command) or Path(command[index + 1]).resolve() != ROOT.resolve():
            raise ValueError("Host project path mismatch")
    environment = os.environ.copy()
    # MCP stdio clients may intentionally inherit a minimal Windows environment.
    # NuGet resolves its user configuration under APPDATA even for local builds.
    if os.name == "nt":
        environment.setdefault("APPDATA", str(Path.home() / "AppData/Roaming"))
        environment.setdefault("LOCALAPPDATA", str(Path.home() / "AppData/Local"))
        drive = environment.get("SYSTEMDRIVE", "C:")
        folders = {
            "ProgramFiles": "Program Files",
            "ProgramFiles(x86)": "Program Files (x86)",
            "ProgramData": "ProgramData",
            "ALLUSERSPROFILE": "ProgramData",
            "WINDIR": "Windows",
        }
        for key, folder in folders.items():
            environment.setdefault(key, drive + "/" + folder)
    if user_data_root is not None:
        root = provenance.project_path(user_data_root, ROOT)
        local_root = ROOT / ".runtime" / "focused"
        if root == local_root or not root.is_relative_to(local_root):
            raise ValueError("Isolated Godot user data must stay under the focused run directory")
        variables = {"APPDATA": "roaming", "LOCALAPPDATA": "local"} if os.name == "nt" else {
            "XDG_DATA_HOME": "data", "XDG_CONFIG_HOME": "config"}
        for variable, name in variables.items():
            directory = root / name
            directory.mkdir(parents=True, exist_ok=True)
            environment[variable] = str(directory)
    environment.setdefault("DOTNET_ROLL_FORWARD", "Major")
    environment.setdefault("DOTNET_CLI_HOME", str(ROOT / ".runtime/dotnet-home"))
    environment.setdefault("NUGET_PACKAGES", str(ROOT / ".runtime/nuget/packages"))
    environment.setdefault("DOTNET_SKIP_FIRST_TIME_EXPERIENCE", "1")
    environment.setdefault("DOTNET_CLI_TELEMETRY_OPTOUT", "1")
    environment.setdefault("DOTNET_EnableDiagnostics", "0")
    # The checkout may be shared by Windows and WSL. A dotnet directory
    # belonging to the other OS cannot supply this Godot host's hostfxr.
    import environment as game_environment
    dotnet = game_environment.resolve_dotnet(required=False)
    if dotnet:
        dotnet_root = str(Path(dotnet).parent)
        environment["DOTNET_ROOT"] = dotnet_root
        environment["PATH"] = dotnet_root + os.pathsep + environment.get("PATH", "")
    else:
        environment.pop("DOTNET_ROOT", None)
    if "godot" in Path(str(command[0])).name.lower() and "--headless" not in command:
        environment = linux_display.environment(environment)
        if environment.get("DV_CLOUD_DISPLAY") == "1" and "--audio-driver" not in command:
            command = [*command, "--audio-driver", "Dummy"]
    return subprocess.Popen(
        [str(part) for part in command],
        cwd=ROOT,
        encoding="utf-8",
        errors="replace",
        text=True,
        env=environment,
        creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
        **kwargs,
    )
