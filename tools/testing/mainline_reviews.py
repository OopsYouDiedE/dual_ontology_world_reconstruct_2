"""Append and validate immutable reviews of real title/new-game player sessions."""
from __future__ import annotations

import argparse
from datetime import datetime
from hashlib import sha256
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
DIRECTORY = Path("artifacts/acceptance/gameplay-reviews")


def evidence_path(root: Path, value: str) -> Path:
    candidate = (root / value).resolve()
    if not candidate.is_relative_to(root.resolve()) or not candidate.is_file():
        raise ValueError("Review evidence must be an existing project-local file: " + value)
    return candidate


def validate(record: dict, root: Path = ROOT) -> dict:
    if record.get("schema_version") != 1 or not re.fullmatch(r"[a-z0-9][a-z0-9_-]{1,119}", record.get("id", "")):
        raise ValueError("Review schema/id is invalid")
    plan = json.loads((root / "assets/data/test_scenarios/gameplay_review_plan.json").read_text(encoding="utf-8-sig"))
    if record.get("segment_id") not in {scene["id"] for scene in plan["scenes"]}:
        raise ValueError("Unknown mainline segment")
    if not re.fullmatch(r"[0-9a-f]{7,40}", record.get("revision", "")):
        raise ValueError("A reviewed Git revision is required")
    observed = datetime.fromisoformat(record["observed_at"])
    if observed.tzinfo is None:
        raise ValueError("Review timestamp requires a timezone")
    if record.get("status") not in ("blocked", "incomplete", "complete"):
        raise ValueError("Review status must describe the observed segment")
    if "terra" not in record.get("reviewer", "").lower():
        raise ValueError("Independent Terra reviewer identity is required")
    scores = record.get("scores", [])
    if len(scores) != 7 or any(value is not None and (isinstance(value, bool) or not isinstance(value, (int, float)) or not 0 <= value <= 10) for value in scores):
        raise ValueError("Reviews need seven numeric or pending scores")
    reasons = record.get("score_reasons", [])
    if len(reasons) != 7 or any(value is not None and not str(reason).strip() for value, reason in zip(scores, reasons)):
        raise ValueError("Every assigned score needs a source reason")
    source = record.get("source", {})
    if source.get("mode") != "real_mainline" or source.get("entry") != "title_new_game":
        raise ValueError("Only actual title/new-game mainline evidence enters this trajectory")
    receipt_path = evidence_path(root, source["on_receipt"])
    receipt = json.loads(receipt_path.read_text(encoding="utf-8-sig"))
    data = receipt.get("data", {})
    identity = data.get("source_identity", {})
    if receipt.get("tool") != "on" or receipt.get("is_error") or identity.get("launch_scene") != "res://scenes/main/Boot.tscn":
        raise ValueError("The session must have launched the real production title")
    if not source.get("session_id") or data.get("session_id") != source["session_id"]:
        raise ValueError("Review session does not match its original on receipt")
    if not identity.get("project_root") or not identity.get("project_sha256") or not identity.get("process_id"):
        raise ValueError("Original process/project provenance is incomplete")
    start_path = evidence_path(root, source["start_receipt"])
    start = json.loads(start_path.read_text(encoding="utf-8-sig"))
    start_data = start.get("data", {})
    if start.get("tool") != "step" or start.get("is_error") or start_data.get("room") != "R05" or start_data.get("day") != 1:
        raise ValueError("New-game R05 entry receipt is required")
    if start_data.get("session_id") != source["session_id"] or start_data.get("source_identity", {}).get("process_id") != identity["process_id"]:
        raise ValueError("New-game entry must belong to the same actual host")
    evidence_path(root, record["report"])
    if record.get("metrics"):
        evidence_path(root, record["metrics"])
    images = record.get("images", [])
    if not images:
        raise ValueError("Mainline reviews require actual screenshot evidence")
    for image in images:
        path = evidence_path(root, image["path"])
        if sha256(path.read_bytes()).hexdigest() != image["sha256"]:
            raise ValueError("Review screenshot hash mismatch: " + image["path"])
    for path in record.get("receipts", []):
        evidence_path(root, path)
    return record


def capture_time(record: dict, root: Path = ROOT) -> datetime:
    """Order a replay by its captured evidence, preserving the later audit time."""
    captures = record.get("source_capture_at", [])
    if isinstance(captures, str):
        captures = [captures]
    times = [datetime.fromisoformat(value) for value in captures]
    for image in record.get("images", []):
        sidecar = root / (image["path"] + ".json")
        if sidecar.is_file():
            epoch = json.loads(sidecar.read_text(encoding="utf-8-sig")).get("captured_epoch")
            if isinstance(epoch, (int, float)):
                times.append(datetime.fromtimestamp(epoch).astimezone())
    return max(times) if times else datetime.fromisoformat(record["observed_at"])


def load_reviews(root: Path = ROOT) -> list[dict]:
    records = [validate(json.loads(path.read_text(encoding="utf-8-sig")), root) for path in sorted((root / DIRECTORY).glob("*.json"))]
    ids = [record["id"] for record in records]
    if len(ids) != len(set(ids)):
        raise ValueError("Duplicate immutable review IDs")
    by_id = {record["id"]: record for record in records}
    for record in records:
        if record.get("supersedes"):
            original = by_id.get(record["supersedes"])
            if original is None or any(original[key] != record[key] for key in ("revision", "segment_id")):
                raise ValueError("A review audit must reference the same revision and segment")
    return sorted(records, key=lambda record: (capture_time(record, root), record["observed_at"], record["id"]))


def append(record: dict, root: Path = ROOT) -> Path:
    validate(record, root)
    directory = root / DIRECTORY
    directory.mkdir(parents=True, exist_ok=True)
    destination = directory / (record["id"] + ".json")
    content = json.dumps(record, ensure_ascii=False, indent=2) + "\n"
    if destination.exists() and json.loads(destination.read_text(encoding="utf-8-sig")) == record:
        return destination
    # Exclusive creation preserves earlier scores even when a new version improves them.
    with destination.open("x", encoding="utf-8") as stream:
        stream.write(content)
    return destination


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--append", type=Path, nargs="+")
    options = parser.parse_args()
    if options.append:
        for path in options.append:
            print(append(json.loads(path.read_text(encoding="utf-8-sig"))))
    else:
        print(json.dumps(load_reviews(), ensure_ascii=False, indent=2))
