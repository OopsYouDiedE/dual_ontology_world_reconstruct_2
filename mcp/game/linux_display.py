"""A private software-rendered X11 display owned by this MCP process on Linux."""
import atexit
import os
from pathlib import Path
import secrets
import shutil
import sys
import socket
import struct
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
LOCAL = ROOT / ".runtime/linux-display"
LOCK = threading.Lock()
_process = None
_settings = None
_log = None


def close():
    global _process, _log
    if _process is not None and _process.poll() is None:
        _process.terminate()
        try:
            _process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            _process.kill()
    if _log:
        _log.close()
    _process = None
    _log = None


atexit.register(close)


def display_available(driver, env):
    """Check that the inherited display can actually be opened."""
    variable = "WAYLAND_DISPLAY" if driver == "wayland" else "DISPLAY"
    if not env.get(variable):
        return False
    code = """import ctypes, ctypes.util, os, sys
name = sys.argv[1]
lib = ctypes.CDLL(ctypes.util.find_library('wayland-client' if name == 'wayland' else 'X11'))
open_name, close_name = (('wl_display_connect', 'wl_display_disconnect') if name == 'wayland' else ('XOpenDisplay', 'XCloseDisplay'))
connect, close = getattr(lib, open_name), getattr(lib, close_name)
connect.argtypes, connect.restype, close.argtypes = [ctypes.c_char_p], ctypes.c_void_p, [ctypes.c_void_p]
handle = connect(os.environ['WAYLAND_DISPLAY' if name == 'wayland' else 'DISPLAY'].encode())
if not handle: sys.exit(1)
close(handle)
"""
    try:
        return subprocess.run([sys.executable, "-c", code, driver], env=env,
                              stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, timeout=5).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def environment(parent):
    global _process, _settings, _log
    if os.name == "nt":
        return parent
    parent = dict(parent)
    for driver, variable in (("wayland", "WAYLAND_DISPLAY"), ("x11", "DISPLAY")):
        if display_available(driver, parent):
            return parent
        parent.pop(variable, None)
    with LOCK:
        if _process is not None and _process.poll() is None:
            return dict(parent, **_settings)
        executable = LOCAL / "usr/bin/Xvfb"
        library = LOCAL / "usr/lib/x86_64-linux-gnu"
        icd = LOCAL / "usr/share/vulkan/icd.d/lvp_icd.json"
        bundled = executable.is_file() and icd.is_file()
        if not bundled:
            executable = shutil.which("Xvfb")
        if not executable:
            raise RuntimeError("Linux graphical host needs a working native display or Xvfb; provision Xvfb before retrying")
        directory = ROOT / ".runtime/displays" / secrets.token_hex(8)
        directory.mkdir(parents=True)
        # TCP loopback also works in containers that do not expose Unix sockets.
        for number in range(90, 190):
            # Display locks are shared across process/network namespaces. A free
            # TCP port does not imply an available X display, especially after
            # an interrupted host; leave foreign or stale locks untouched.
            if Path(f"/tmp/.X{number}-lock").exists() or Path(f"/tmp/.X11-unix/X{number}").exists():
                continue
            with socket.socket() as reservation:
                try:
                    reservation.bind(("127.0.0.1", 6000 + number))
                except OSError:
                    continue
            break
        else:
            raise RuntimeError("No free local display port")
        authority = directory / "Xauthority"
        fields = (b"", str(number).encode(), b"MIT-MAGIC-COOKIE-1", secrets.token_bytes(16))
        authority.write_bytes(struct.pack("!H", 65535) + b"".join(struct.pack("!H", len(field)) + field for field in fields))
        authority.chmod(0o600)
        _settings = {"DISPLAY": f"127.0.0.1:{number}", "XAUTHORITY": str(authority), "DV_CLOUD_DISPLAY": "1"}
        if bundled:
            _settings.update(LD_LIBRARY_PATH=str(library) + (":" + parent["LD_LIBRARY_PATH"] if parent.get("LD_LIBRARY_PATH") else ""),
                             VK_ICD_FILENAMES=str(icd), LIBGL_ALWAYS_SOFTWARE="1")
        child = dict(parent, **_settings)
        _log = (directory / "xvfb.log").open("w", encoding="utf-8")
        _process = subprocess.Popen([str(executable), f":{number}", "-screen", "0", "1440x900x24",
            "-auth", str(authority), "-noreset", "-listen", "tcp", "-nolisten", "unix", "-nolisten", "local"],
            env=child, stdout=_log, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            if _process.poll() is not None:
                raise RuntimeError("Cloud display failed: " + (directory / "xvfb.log").read_text()[-2000:])
            try:
                with socket.create_connection(("127.0.0.1", 6000 + number), timeout=.2):
                    return child
            except OSError:
                time.sleep(.1)
        raise RuntimeError("Cloud display did not become ready")
