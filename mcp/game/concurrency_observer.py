"""Low-frequency observations of system load during a rendered game session."""
import datetime
import json
import os
from pathlib import Path
import threading

import psutil


def _timestamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


class ConcurrencyObserver:
    """Sample visible Godot processes and system load without blocking the host."""
    def __init__(self, host_pid, interval=1.0):
        self.host_pid = host_pid
        self.interval = interval
        self.done = threading.Event()
        self.samples = []
        self.failures = 0
        self.started_at = _timestamp()
        self.thread = threading.Thread(target=self._run, daemon=True, name="game-load-observer")

    def start(self):
        self.thread.start()

    def _sample(self):
        pids = []
        for process in psutil.process_iter(["pid", "name"]):
            try:
                if "godot" in (process.info.get("name") or "").lower():
                    pids.append(process.info["pid"])
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                self.failures += 1
        return {"timestamp": _timestamp(), "godot_pids": sorted(pids),
                "system_cpu_percent": psutil.cpu_percent(interval=None),
                "available_memory_bytes": psutil.virtual_memory().available}

    def _run(self):
        while not self.done.is_set():
            try:
                self.samples.append(self._sample())
            except (psutil.Error, OSError):
                self.failures += 1
            if self.done.wait(self.interval):
                break

    def stop(self, directory):
        self.done.set()
        self.thread.join(timeout=3)
        samples = list(self.samples)
        report = {"host_pid": self.host_pid, "started_at": self.started_at,
                  "ended_at": _timestamp(), "sample_interval_seconds": self.interval,
                  "sample_count": len(samples), "sampling_failures": self.failures,
                  "sampler_stopped": not self.thread.is_alive(),
                  "peak_observed_godot_processes": max((len(s["godot_pids"]) for s in samples), default=None),
                  "observed_godot_pids": sorted({pid for s in samples for pid in s["godot_pids"]}),
                  "coverage": "Periodic visible-process observations; short overlaps and GPU load may be missed.",
                  "samples": samples}
        directory = Path(directory)
        directory.mkdir(parents=True, exist_ok=True)
        output = directory / "concurrency-observation.json"
        temporary = output.with_suffix(".json.tmp")
        try:
            temporary.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
            os.replace(temporary, output)
        finally:
            if temporary.exists():
                temporary.unlink()
        return output
