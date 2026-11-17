"""Append live, source-bound blind observations to the current monitored run.

The caller owns the session lock and resolves the session ID through its own
session registry before invoking this module. Observations are timestamped
against the Godot monitor when received; they are not proof of what was seen.
"""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import time
import unicodedata


KINDS = {"event_script": "event", "character_script": "character",
         "charactor_script": "character"}


def _english_text(value):
    if not isinstance(value, str) or not value.strip() or len(value) > 4096:
        raise ValueError("Observation must contain 1 to 4096 characters")
    value = value.strip()
    has_latin = False
    for char in value:
        category = unicodedata.category(char)
        if category.startswith("L"):
            if "LATIN" not in unicodedata.name(char, ""):
                raise ValueError("Observation letters must use the Latin script; write in English")
            has_latin = True
        elif category.startswith("C") and char not in "\n\t":
            raise ValueError("Observation contains an unsupported control character")
    if not has_latin:
        raise ValueError("Observation must contain English words")
    return value


def append_observation(endpoint, session_id, name, text, root):
    """Record a note after querying the owned live host for current case/time.

    ``elapsed_s`` is the latest monitor sample; ``received_at_utc`` records the
    receipt time. No natural language classification or independent-observer
    identity verification is inferred from submitted text.
    """
    if name not in KINDS:
        raise ValueError("Unsupported observation category")
    text = _english_text(text)
    if not isinstance(session_id, str) or not session_id:
        raise ValueError("A valid owned session ID is required")
    if getattr(endpoint, "closed", True) or getattr(endpoint, "backend", None) != "godot":
        raise ValueError("A live monitored Godot session is required")
    process = getattr(endpoint, "process", None)
    if process is None or process.poll() is not None:
        raise ValueError("The owned Godot host is not running")
    plan = getattr(endpoint, "assessment_plan", None)
    if not isinstance(plan, dict) or not plan.get("test_id") or not plan.get("revision"):
        raise ValueError("A validated assessment plan is required")
    root = Path(root).resolve()
    plan_path = Path(plan.get("plan_path", "")).resolve()
    if not plan_path.is_relative_to(root) or not plan_path.is_file():
        raise ValueError("Assessment plan must remain inside the project")
    if hashlib.sha256(plan_path.read_bytes()).hexdigest() != plan.get("plan_sha256"):
        raise ValueError("Assessment plan changed during the session")

    observed = endpoint.request({"type": "observe", "wait_ms": 0, "capture_image": False})
    if not isinstance(observed, dict) or observed.get("assessment_test_id") != plan["test_id"]:
        raise ValueError("Host assessment test ID mismatch")
    cases = plan.get("cases")
    index = observed.get("assessment_case_index")
    if not isinstance(cases, list) or isinstance(index, bool) or not isinstance(index, int) or not 0 <= index < len(cases):
        raise ValueError("Host assessment case index is unavailable or invalid")
    case = cases[index]
    if not isinstance(case, dict) or not case.get("id") or not case.get("segment_id"):
        raise ValueError("Assessment case is invalid")
    metrics = observed.get("metrics")
    if not isinstance(metrics, dict) or not isinstance(metrics.get("elapsed_s"), (int, float)) or isinstance(metrics.get("elapsed_s"), bool):
        raise ValueError("The host has not produced a timestamped monitor sample")
    elapsed = metrics["elapsed_s"]
    if not 0 <= elapsed < float("inf"):
        raise ValueError("The monitor timestamp is invalid")
    directory = Path(getattr(endpoint, "metrics_directory", "") or "").resolve()
    reported = Path(observed.get("metrics_directory") or "").resolve()
    if (not directory.is_relative_to(root) or not directory.is_dir() or directory != reported
            or not directory.name.endswith("-" + str(process.pid))):
        raise ValueError("Monitor directory does not match this project and host PID")
    log_path = (directory / "blind-observations.jsonl").resolve()
    if log_path.parent != directory:
        raise ValueError("Observation log must remain within the monitor directory")
    row = {
        "schema_version": 1, "kind": KINDS[name], "text": text,
        "test_id": plan["test_id"], "revision": plan["revision"],
        "session_id": session_id, "host_pid": process.pid,
        "observer": plan.get("blind_observer", {}).get("identity"),
        "assessment_plan_sha256": plan["plan_sha256"],
        "case_id": case["id"], "case_index": index, "segment_id": case["segment_id"],
        "scene_node": observed.get("assessment_segment"),
        "monitor_elapsed_s": elapsed,
        "received_at_utc": datetime.now(timezone.utc).isoformat(),
        "received_monotonic_ns": time.monotonic_ns(),
    }
    with log_path.open("a", encoding="utf-8", newline="\n") as output:
        output.write(json.dumps(row, ensure_ascii=False, allow_nan=False) + "\n")
        output.flush()
        os.fsync(output.fileno())
    return {"recorded": True, "kind": row["kind"], "test_id": row["test_id"],
            "case_id": row["case_id"], "monitor_elapsed_s": elapsed, "evidence_path": str(log_path)}
