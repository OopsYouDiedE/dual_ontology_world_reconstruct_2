"""Collect seven evidence-backed scores for each scene in a completed survey run.

The metrics describe the actual concurrent, capped capture. Unknown measurements
remain null, and no score is published by this utility.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
import sys
import yaml

from mainline_metrics import audio_score, frame_statistics
from visible_text_metrics import analyze_visible_text

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "mcp"))
import capture_provenance as provenance  # noqa: E402

CATEGORIES = ("fluidity", "text_density", "action_sfx_integrity", "audio_loudness",
              "blind_narrative_match", "aesthetic_similarity", "narrative_flow")
HUMAN_CATEGORIES = {"action_sfx_integrity", "blind_narrative_match",
                    "aesthetic_similarity", "narrative_flow"}
DEFAULT_REASONS = {
    "fluidity": "No validated, finalized steady-state frame data for this case.",
    "text_density": "Complete visible-text capture was not available.",
    "action_sfx_integrity": "No complete independent physical action review was supplied.",
    "audio_loudness": "No complete, loss-free audio measurement with verified signal was supplied.",
    "blind_narrative_match": "No independent blind observation and canonical comparison was supplied.",
    "aesthetic_similarity": "No independently assessed reference-image comparison was supplied.",
    "narrative_flow": "No independent end-to-end player pacing review was supplied.",
}


def relative(path: Path) -> str:
    return provenance.project_path(path, ROOT).relative_to(ROOT).as_posix()


def validated_evidence(paths, *, case_dir, required):
    if paths is None and not required:
        paths = []
    if not isinstance(paths, list) or (required and not paths):
        raise ValueError("A reviewed score requires project-local evidence")
    result = []
    has_case_evidence = False
    run_root = ROOT / "artifacts/evaluation/runs"
    current_run = case_dir.parent.parent.resolve()
    for value in paths:
        p = provenance.project_path(value, ROOT)
        if not p.is_file():
            raise ValueError("Missing score evidence: " + str(value))
        if p.is_relative_to(run_root) and not p.is_relative_to(current_run):
            raise ValueError("Score evidence belongs to a different test run: " + str(value))
        if p.is_relative_to(case_dir.resolve()):
            has_case_evidence = True
        result.append(relative(p))
    if required and not has_case_evidence:
        raise ValueError("A reviewed score requires evidence from its own case")
    return list(dict.fromkeys(result))


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def score_case(run_dir: Path, job: str, job_row: dict, revision: str, assessments=None):
    case_id = job.removeprefix("survey-")
    case_dir = run_dir / job / case_id
    metrics = case_dir / "metrics"
    result = {"case_id": case_id, "segment_id": job_row.get("segment_id"), "source_revision": revision,
              "status": job_row.get("state"), "room": (job_row.get("detail") or {}).get("room"),
              "scores": dict.fromkeys(CATEGORIES), "reasons": DEFAULT_REASONS.copy(), "evidence": [],
              "measurement_context": "Up to three concurrent rendered hosts, capped at 60 FPS; not an isolated baseline.",
              "metrics": {}, "assessment_errors": []}
    add = lambda path: result["evidence"].append(relative(path)) if path.is_file() else None
    add(run_dir / "status.json")
    add(run_dir / job / "launch.json")
    add(run_dir / job / "concurrency-observation.json")
    add(case_dir / "report.json")
    add(case_dir / "progress.json")
    pid = job_row.get("host_pid")
    source_ok = False
    document = {}
    timeline = metrics / "timeline.yaml"
    try:
        document = yaml.safe_load(timeline.read_text(encoding="utf-8-sig"))
        if not isinstance(document, dict) or not isinstance(document.get("summary"), dict):
            raise ValueError("final timeline summary missing")
        meta = document.get("metadata", {})
        if not isinstance(pid, int) or pid <= 0:
            raise ValueError("host PID missing from job receipt")
        provenance.validate_source(meta.get("source_identity"), provenance.project_identity(ROOT), pid=pid)
        if meta.get("case_id") != case_id or meta.get("measurement_context") != "rendered_runtime":
            raise ValueError("case or rendered context mismatch")
        source_ok = True
        add(timeline)
    except (OSError, ValueError, TypeError, yaml.YAMLError) as exc:
        result["reasons"]["fluidity"] = "Timeline unavailable or provenance invalid: " + str(exc)
        result["reasons"]["audio_loudness"] = "Timeline unavailable or provenance invalid: " + str(exc)

    frames_path = metrics / "frames.csv"
    if source_ok:
        try:
            steady = []
            with frames_path.open(encoding="utf-8-sig", newline="") as stream:
                for row in csv.DictReader(stream):
                    phase = row.get("measurement_phase")
                    frame = float(row["frame_ms"])
                    if not math.isfinite(frame) or frame <= 0 or phase not in ("steady", "loading_warmup"):
                        raise ValueError("invalid frame duration or warmup classification")
                    if phase == "steady": steady.append(frame)
            stats = frame_statistics(steady)
            add(frames_path)
            result["metrics"]["steady_frames"] = stats
            spikes = stats["spikes_over_33_3_ms"]
            if stats["frame_samples"] and spikes:
                result["scores"]["fluidity"] = 6
                result["reasons"]["fluidity"] = f"{spikes} steady frames exceeded 33.3 ms; concurrent 60 FPS capture."
            elif stats["frame_samples"] and job_row.get("state") == "passed":
                result["scores"]["fluidity"] = 8
                result["reasons"]["fluidity"] = f"No frame exceeded 33.3 ms in {stats['frame_samples']} recorded steady frames; concurrent 60 FPS capture."
            elif stats["frame_samples"]:
                result["reasons"]["fluidity"] = "No spike observed in partial scene; the complete scene was not captured."
        except (OSError, ValueError, TypeError, KeyError, csv.Error) as exc:
            result["reasons"]["fluidity"] = "Frame data unavailable or invalid: " + str(exc)

    if source_ok:
        summary = document["summary"]
        coverage = summary.get("visible_text_collection", {})
        complete = (job_row.get("state") == "passed" and isinstance(coverage, dict)
                    and coverage.get("complete") is True and coverage.get("write_errors") == 0
                    and isinstance(summary.get("frames"), int) and summary["frames"] > 0
                    and coverage.get("checked_frames") == summary["frames"])
        text_path = metrics / "visible-text-changes.jsonl"
        text = analyze_visible_text(text_path, segment_id=str(job_row.get("segment_id", "")),
                                    collection_complete=complete)
        result["scores"]["text_density"] = text["score"]
        result["reasons"]["text_density"] = text["reason"]
        result["metrics"]["visible_text"] = text
        add(text_path)

    audio_path = metrics / "audio.json"
    if source_ok:
        try:
            audio = read_json(audio_path)
            add(audio_path)
            summary = document["summary"]
            samples = document.get("timeline", [])
            if not isinstance(samples, list): raise ValueError("invalid timeline sample list")
            loss = bool(summary.get("audio_discarded_frames", 0) or summary.get("audio_writer", {}).get("error", 0))
            loss = loss or any(row.get("audio_discarded_frames", 0) or row.get("audio_writer", {}).get("error", 0) for row in samples)
            if loss:
                result["reasons"]["audio_loudness"] = "Audio capture reports dropped frames or writer errors."
            else:
                value, reason = audio_score(audio)
                if value == 8 and job_row.get("state") != "passed":
                    value, reason = None, "Audio passed its recorded interval, but the scene did not complete."
                result["scores"]["audio_loudness"] = value
                result["reasons"]["audio_loudness"] = reason
            result["metrics"]["audio"] = {key: audio.get(key) for key in ("status", "signal_present", "integrated_lufs", "true_peak_dbtp", "duration_s")}
        except (OSError, ValueError, TypeError, AttributeError) as exc:
            result["reasons"]["audio_loudness"] = "Audio measurement unavailable or invalid: " + str(exc)

    captures = []
    for image in sorted(case_dir.glob("*.png")):
        try:
            verified = provenance.verify_image(image, ROOT, allow_fixture=True)
            provenance.validate_source(verified["source_identity"], provenance.project_identity(ROOT), pid=pid)
            sidecar = Path(verified["sidecar_path"])
            text = read_json(sidecar).get("visible_text")
            captures.append({"image": relative(image), "visible_text": text})
            add(image)
            add(sidecar)
        except (OSError, ValueError, TypeError) as exc:
            result["assessment_errors"].append("Capture verification: " + str(exc))
    result["metrics"]["verified_captures"] = captures

    for category, review in (assessments or {}).items():
        if category not in HUMAN_CATEGORIES or not isinstance(review, dict):
            raise ValueError("Unsupported human assessment category: " + str(category))
        value, reason = review.get("score"), review.get("reason")
        if value is not None and (isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not 0 <= value <= 10):
            raise ValueError("Human score must be null or a number from zero to ten")
        if not isinstance(reason, str) or not reason.strip():
            raise ValueError("Human score requires a concrete reason")
        evidence = validated_evidence(review.get("evidence"), case_dir=case_dir, required=value is not None)
        result["scores"][category] = value
        result["reasons"][category] = reason.strip()
        result["evidence"].extend(evidence)
    result["evidence"] = list(dict.fromkeys(result["evidence"]))
    return result


def aggregate(cases):
    groups = {}
    for case in cases:
        segment = case["segment_id"]
        if not segment: raise ValueError("Scene segment missing")
        group = groups.setdefault(segment, {"scores": {}, "reasons": {}, "evidence": [], "case_ids": []})
        group["case_ids"].append(case["case_id"])
        group["evidence"].extend(case["evidence"])
    for segment, group in groups.items():
        rows = [case for case in cases if case["segment_id"] == segment]
        group["status"] = ("incomplete" if any(row.get("status") != "passed" or
                                                  any(row["scores"][key] is None for key in CATEGORIES)
                                                  for row in rows) else "complete")
        for category in CATEGORIES:
            present = [(row["case_id"], row["scores"][category]) for row in rows if row["scores"][category] is not None]
            absent_rows = [row for row in rows if row["scores"][category] is None]
            absent = [row["case_id"] for row in absent_rows]
            missing_detail = "; ".join(f"{row['case_id']} ({row['reasons'][category]})" for row in absent_rows)
            failing = [(case_id, value) for case_id, value in present if value < 8]
            if failing:
                value = min(value for _, value in failing)
                reason = "Observed failing score in " + ", ".join(f"{name}={score}" for name, score in failing)
                if absent: reason += "; missing measurements: " + missing_detail
            elif absent:
                value = None
                reason = "Missing measurements: " + missing_detail
            elif present:
                value = min(value for _, value in present)
                reason = "Lowest case score from this run: " + ", ".join(f"{name}={score}" for name, score in present)
            else:
                value, reason = None, "No cases measured."
            group["scores"][category] = value
            group["reasons"][category] = reason
        group["evidence"] = list(dict.fromkeys(group["evidence"]))
    return groups


def collect(run_dir: Path, assessments=None):
    run_dir = provenance.project_path(run_dir, ROOT)
    status = read_json(run_dir / "status.json")
    if status.get("profile") != "scene_survey" or status.get("state") in ("starting", "running"):
        raise ValueError("A completed scene_survey run is required")
    if status.get("source_changed_during_run"):
        raise ValueError("Source changed during the run; results require a consistent captured source")
    revision = status.get("revision")
    if not isinstance(revision, str) or not revision:
        raise ValueError("Source revision missing")
    if assessments is not None and not isinstance(assessments, dict):
        raise ValueError("Human assessments must be an object")
    assessments = assessments or {}
    if assessments and (assessments.get("run_id") != status.get("run_id") or assessments.get("source_revision") != revision):
        raise ValueError("Human assessment run or revision does not match")
    reviewed = assessments.get("cases", {})
    if not isinstance(reviewed, dict): raise ValueError("Human assessments must be keyed by case ID")
    jobs = [(name, row) for name, row in status.get("jobs", {}).items() if name.startswith("survey-")]
    if not jobs: raise ValueError("No scene survey jobs in run")
    unexpected = set(reviewed) - {name.removeprefix("survey-") for name, _ in jobs}
    if unexpected: raise ValueError("Unknown reviewed case: " + ", ".join(sorted(unexpected)))
    cases = [score_case(run_dir, name, row, revision, reviewed.get(name.removeprefix("survey-"))) for name, row in jobs]
    return {"schema_version": 1, "run_id": status["run_id"], "source_revision": revision,
            "working_tree_changes": status.get("working_tree_changes"),
            "source_fingerprint": status.get("source_fingerprint_before"),
            "measurement_context": "Concurrent rendered scene captures capped at 60 FPS",
            "cases": cases, "segments": aggregate(cases)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_directory", type=Path)
    parser.add_argument("--assessments", type=Path, help="Project-local JSON of independently reviewed case scores")
    args = parser.parse_args()
    reviews = read_json(provenance.project_path(args.assessments, ROOT)) if args.assessments else None
    result = collect(args.run_directory, reviews)
    output = provenance.project_path(args.run_directory, ROOT) / "scene-scores.json"
    temp = output.with_suffix(".json.tmp")
    try:
        temp.write_text(json.dumps(result, ensure_ascii=False, allow_nan=False, indent=2) + "\n", encoding="utf-8")
        temp.replace(output)
    finally:
        if temp.exists(): temp.unlink()
    print(output)


if __name__ == "__main__":
    main()
