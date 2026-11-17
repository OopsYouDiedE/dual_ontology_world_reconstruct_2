"""Collect observer classifications for text visible in the owned Godot session."""
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path

CATEGORIES = {"dialogue", "spoken_dialogue", "speech", "prompt", "interaction_prompt",
              "nameplate", "single_key_icon", "action_key_icon", "hud", "menu", "other_ui"}


def append_text_observation(endpoint, session_id, path, text, category, english_verified, root):
    """Append one observer judgement, bound to a text actually visible on screen."""
    if not isinstance(session_id, str) or not session_id:
        raise ValueError("A valid owned session ID is required")
    if not isinstance(path, str) or not path or not isinstance(text, str) or not text:
        raise ValueError("A visible node path and exact text are required")
    if category not in CATEGORIES or not isinstance(english_verified, bool):
        raise ValueError("A supported classification and explicit English check are required")
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
    if (not plan_path.is_relative_to(root) or not plan_path.is_file()
            or hashlib.sha256(plan_path.read_bytes()).hexdigest() != plan.get("plan_sha256")):
        raise ValueError("Assessment plan is unavailable or changed during the session")
    observed = endpoint.request({"type": "observe", "wait_ms": 0, "capture_image": False})
    if not isinstance(observed, dict) or observed.get("assessment_test_id") != plan["test_id"]:
        raise ValueError("Host assessment test ID mismatch")
    entries = observed.get("controls")
    if not isinstance(entries, list) or not any(isinstance(entry, dict) and entry.get("path") == path
                                                 and entry.get("text") == text for entry in entries):
        raise ValueError("Exact node path and text were not visible in the current observation")
    cases = plan.get("cases")
    index = observed.get("assessment_case_index")
    if not isinstance(cases, list) or isinstance(index, bool) or not isinstance(index, int) or not 0 <= index < len(cases):
        raise ValueError("Host assessment case index is unavailable or invalid")
    case = cases[index]
    if not isinstance(case, dict) or not case.get("id") or not case.get("segment_id"):
        raise ValueError("Assessment case is invalid")
    metrics = observed.get("metrics")
    elapsed = metrics.get("elapsed_s") if isinstance(metrics, dict) else None
    if isinstance(elapsed, bool) or not isinstance(elapsed, (int, float)) or not math.isfinite(elapsed) or elapsed < 0:
        raise ValueError("The host has not produced a timestamped monitor sample")
    directory = Path(getattr(endpoint, "metrics_directory", "") or "").resolve()
    reported = Path(observed.get("metrics_directory") or "").resolve()
    if (not directory.is_relative_to(root) or not directory.is_dir() or directory != reported
            or not directory.name.endswith("-" + str(process.pid))):
        raise ValueError("Monitor directory does not match this project and host PID")
    reviewer = plan.get("blind_observer", {}).get("identity")
    if not isinstance(reviewer, str) or not reviewer:
        raise ValueError("The plan does not identify the reviewer")
    log_path = directory / "visible-text-reviews.jsonl"
    row = {"schema_version": 1, "test_id": plan["test_id"], "revision": plan["revision"],
           "session_id": session_id, "host_pid": process.pid, "reviewer": reviewer,
           "assessment_plan_sha256": plan["plan_sha256"], "case_id": case["id"],
           "segment_id": case["segment_id"], "scene_node": observed.get("assessment_segment"),
           "monitor_elapsed_s": elapsed, "received_at_utc": datetime.now(timezone.utc).isoformat(),
           "path": path, "text": text, "category": category, "english_verified": english_verified}
    with log_path.open("a", encoding="utf-8", newline="\n") as output:
        output.write(json.dumps(row, ensure_ascii=False, allow_nan=False) + "\n")
        output.flush()
        os.fsync(output.fileno())
    return {"recorded": True, "test_id": plan["test_id"], "case_id": case["id"],
            "monitor_elapsed_s": elapsed, "evidence_path": str(log_path)}
