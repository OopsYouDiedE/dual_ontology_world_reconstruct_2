"""Meter actual Godot post-mix float PCM with FFmpeg's EBU R128 implementation.

Only stdlib and ffmpeg are required. Atomic JSON is read by the live monitor;
the final WAV and complete FFmpeg log are retained as independently checkable evidence.
"""
from __future__ import annotations

import argparse
import ctypes
import json
import math
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import threading
import time


def resident_mb(pid: int) -> float | None:
    if os.name == "nt":
        class Counters(ctypes.Structure):
            _fields_ = [("cb", ctypes.c_ulong), ("PageFaultCount", ctypes.c_ulong)] + [
                (key, ctypes.c_size_t) for key in ("PeakWorkingSetSize", "WorkingSetSize", "QuotaPeakPagedPoolUsage", "QuotaPagedPoolUsage", "QuotaPeakNonPagedPoolUsage", "QuotaNonPagedPoolUsage", "PagefileUsage", "PeakPagefileUsage")
            ]
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.OpenProcess.restype = ctypes.c_void_p
        kernel.CloseHandle.argtypes = [ctypes.c_void_p]
        handle = kernel.OpenProcess(0x410, False, pid)
        if not handle:
            return None
        try:
            counters = Counters()
            counters.cb = ctypes.sizeof(counters)
            get_info = ctypes.WinDLL("psapi").GetProcessMemoryInfo
            get_info.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_ulong]
            if get_info(handle, ctypes.byref(counters), counters.cb):
                return counters.WorkingSetSize / 1048576
        finally:
            kernel.CloseHandle(handle)
    else:
        try:
            return int(Path(f"/proc/{pid}/statm").read_text().split()[1]) * os.sysconf("SC_PAGE_SIZE") / 1048576
        except (OSError, ValueError):
            pass
    return None


def find_ffmpeg() -> str | None:
    candidates = [os.environ.get("FFMPEG"), shutil.which("ffmpeg"), str(Path.home() / "Documents/ffmpeg/bin/ffmpeg.exe")]
    return next((value for value in candidates if value and Path(value).is_file()), None)


def update_metadata(state: dict, line: str) -> bool:
    match = re.search(r"lavfi\.r128\.(\S+)=(\S+)", line)
    if not match:
        return False
    name, raw = match.groups()
    try:
        value = float(raw)
    except ValueError:
        return False
    if not math.isfinite(value):
        return False
    if name == "I":
        state["integrated_lufs"] = value if value > -70 else None
    elif name == "M":
        state["momentary_lufs"] = value if value > -120 else None
        if value > -120:
            state["max_momentary_lufs"] = max(value, state.get("max_momentary_lufs") or -160)
    elif name == "S":
        state["short_term_lufs"] = value if value > -120 else None
    elif name == "true_peak":
        peak = 20 * math.log10(value) if value > 0 else None
        if peak is not None:
            state["true_peak_dbtp"] = max(peak, state.get("true_peak_dbtp") or -160)
    elif name == "sample_peak":
        peak = 20 * math.log10(value) if value > 0 else None
        if peak is not None:
            state["sample_peak_dbfs"] = max(peak, state.get("sample_peak_dbfs") or -160)
    state["signal_present"] = state.get("sample_peak_dbfs") is not None
    return True


def write_float_wav(source: Path, destination: Path, rate: int) -> None:
    length = source.stat().st_size
    with source.open("rb") as raw, destination.open("wb") as wav:
        wav.write(b"RIFF" + struct.pack("<I", min(0xFFFFFFFF, 36 + length)) + b"WAVEfmt ")
        wav.write(struct.pack("<IHHIIHH", 16, 3, 2, rate, rate * 8, 8, 32))
        wav.write(b"data" + struct.pack("<I", min(0xFFFFFFFF, length)))
        shutil.copyfileobj(raw, wav)


def run(args: argparse.Namespace) -> int:
    import sys
    root = Path(__file__).resolve().parents[2]
    sys.path.insert(0, str(root / "mcp"))
    import capture_provenance as provenance
    args.pcm = str(provenance.project_path(args.pcm, root))
    args.stop = str(provenance.project_path(args.stop, root))
    output = provenance.project_path(args.out, root)
    output.parent.mkdir(parents=True, exist_ok=True)
    state = {"status": "starting", "method": "FFmpeg EBU R128 / ITU BS.1770", "sample_rate": args.rate, "integrated_lufs": None, "max_momentary_lufs": None, "true_peak_dbtp": None, "sample_peak_dbfs": None, "dba": None, "signal_present": False}
    lock = threading.Lock()

    def publish():
        state["ram_mb"] = resident_mb(args.owner)
        state["updated_unix"] = time.time()
        temporary = output.with_suffix(".json.tmp")
        temporary.write_text(json.dumps(state, ensure_ascii=False, allow_nan=False), encoding="utf-8")
        try:
            os.replace(temporary, output)
        except PermissionError:
            pass  # Windows may hold the previous snapshot open for one frame.

    ffmpeg = find_ffmpeg()
    if not ffmpeg:
        state.update(status="unavailable", reason="FFmpeg executable not found; set FFMPEG")
        publish()
        return 2
    command = [ffmpeg, "-hide_banner", "-nostats", "-f", "f32le", "-ar", str(args.rate), "-ac", "2", "-i", "pipe:0", "-af", "ebur128=metadata=1:peak=sample+true,ametadata=mode=print:direct=1:file='pipe\\:1'", "-f", "null", "-"]
    state["command"] = command
    log = output.with_name("audio-ffmpeg.log").open("w", encoding="utf-8")
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    state["status"] = "measuring"
    publish()

    def read_metadata():
        assert process.stdout
        for line in iter(process.stdout.readline, b""):
            with lock:
                if update_metadata(state, line.decode("utf-8", errors="replace")):
                    publish()

    reader = threading.Thread(target=read_metadata, daemon=True)
    reader.start()
    source = Path(args.pcm)
    last_change = time.monotonic()
    with source.open("rb") as pcm:
        while process.poll() is None:
            data = pcm.read(65536)
            if data:
                try:
                    process.stdin.write(data)
                    process.stdin.flush()
                except BrokenPipeError:
                    break
                last_change = time.monotonic()
            elif Path(args.stop).exists() or time.monotonic() - last_change > 30:
                break
            else:
                time.sleep(0.03)
    if process.stdin:
        try:
            process.stdin.close()
        except BrokenPipeError:
            pass
    try:
        code = process.wait(timeout=20)
    except subprocess.TimeoutExpired:
        process.kill()
        code = process.wait()
    reader.join(timeout=3)
    log.close()
    with lock:
        state.update(status="complete" if code == 0 else "error", ffmpeg_exit_code=code, duration_s=source.stat().st_size / (8 * args.rate))
        publish()
    write_float_wav(source, output.with_name("mix.wav"), args.rate)
    return 0 if code == 0 else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--pcm", required=True)
    parser.add_argument("--rate", type=int, required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--stop", required=True)
    parser.add_argument("--owner", type=int, required=True)
    raise SystemExit(run(parser.parse_args()))
