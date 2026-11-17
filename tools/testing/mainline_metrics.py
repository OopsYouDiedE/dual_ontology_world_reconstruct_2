"""Summarize recorded real-mainline segments without starting or controlling Godot."""
from __future__ import annotations

import argparse
import csv
from datetime import datetime
from hashlib import sha256
import json
import math
from pathlib import Path
import subprocess
import sys

import yaml
from audio_watch import find_ffmpeg, update_metadata

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "mcp"))
import capture_provenance as provenance


def file_hash(path: Path) -> str:
    digest = sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1048576), b""):
            digest.update(chunk)
    return digest.hexdigest()


def frame_statistics(values: list[float]) -> dict:
    frames = sorted(values)
    if not frames:
        return {"frame_samples": 0, "spikes_over_33_3_ms": 0}
    percentile = lambda p: frames[max(0, math.ceil(len(frames) * p) - 1)]
    low = lambda p: 1000 / (sum(frames[-max(1, math.ceil(len(frames) * p)):]) / max(1, math.ceil(len(frames) * p)))
    return dict(frame_samples=len(frames), avg_fps=1000 * len(frames) / sum(frames),
                low_5_fps=low(.05), low_1_fps=low(.01), frame_p95_ms=percentile(.95),
                frame_p99_ms=percentile(.99), max_frame_ms=frames[-1],
                spikes_over_33_3_ms=sum(value > 33.3 for value in frames))


def audio_score(audio: dict) -> tuple[int | None, str]:
    """Score only evidence that supports the documented loudness thresholds."""
    if audio.get("status") != "complete" or not audio.get("signal_present"):
        return None, "Segment audio is incomplete or contains no verified signal"
    loudness, peak = audio.get("integrated_lufs"), audio.get("true_peak_dbtp")
    peak_valid = isinstance(peak, (int, float)) and not isinstance(peak, bool) and math.isfinite(peak)
    if peak_valid and peak >= 0:
        return 6, "Digital true-peak clipping"
    loudness_valid = isinstance(loudness, (int, float)) and not isinstance(loudness, bool) and math.isfinite(loudness)
    if not peak_valid or not loudness_valid:
        return None, "Integrated loudness and true peak are both required"
    if loudness >= -20:
        return 6, "Integrated loudness is not below -20 LUFS"
    if peak < -20:
        return 8, "Integrated loudness and the entire mix peak are below -20"
    return None, "Ambient-only peak is not isolated from dialogue or effects"


def summarize(directory: Path, *, incomplete: bool = False, snapshot_path: Path | None = None) -> dict:
    provenance.assert_runtime_root(ROOT)
    directory = provenance.project_path(directory, ROOT)
    timeline = directory / "timeline.yaml"
    header, samples = [], []
    in_timeline, finalized = False, False
    with timeline.open(encoding="utf-8-sig") as stream:
        for line in stream:
            if line.startswith("timeline:"):
                in_timeline = True
            elif line.startswith(("summary:", '"summary":')):
                finalized = True
                break
            elif in_timeline and line.startswith("  - "):
                try:
                    samples.append(json.loads(line[4:]))
                except json.JSONDecodeError:
                    if not incomplete:
                        raise
            elif not in_timeline:
                header.append(line)
    if not finalized and not incomplete:
        raise ValueError("Close the real session before final segment analysis")
    metadata = yaml.safe_load("".join(header))["metadata"]
    source = metadata.get("source_identity", {})
    provenance.validate_source(source, provenance.project_identity(ROOT))
    if not isinstance(source.get("process_id"), int) or source["process_id"] <= 0:
        raise ValueError("Recorded actual host PID is required")
    if snapshot_path is None:
        if metadata.get("mock") is not False or metadata.get("entry") != "production_title" or metadata.get("acceptance_eligible") is False:
            raise ValueError("Only production title/new-game capture enters mainline metrics")
    else:
        snapshot_path = provenance.project_path(snapshot_path, ROOT)
        recorded_snapshot = metadata.get("snapshot_path")
        if (metadata.get("mock") is not True or metadata.get("entry") != "snapshot"
                or metadata.get("acceptance_eligible") is not False
                or not isinstance(recorded_snapshot, str) or not recorded_snapshot
                or provenance.project_path(recorded_snapshot, ROOT) != snapshot_path):
            raise ValueError("Snapshot metadata does not match the development session")
    if metadata.get("measurement_context") != "rendered_runtime":
        raise ValueError("A rendered real-time session is required")
    segments = {}
    previous_time = 0.0
    previous_segment = None
    with (directory / "frames.csv").open(encoding="utf-8-sig", newline="") as stream:
        for row in csv.DictReader(stream):
            try:
                name = row["node"].split("/", 1)[0]
                elapsed, frame = float(row["elapsed_s"]), float(row["frame_ms"])
            except (TypeError, ValueError, AttributeError):
                if incomplete:
                    continue
                raise
            if not math.isfinite(frame) or not math.isfinite(elapsed) or frame <= 0 or elapsed < previous_time:
                raise ValueError("Invalid wall-clock frame sample")
            segment = segments.setdefault(name, {"frames": [], "steady_frames": [], "warmup_frames": [], "intervals_s": [], "text_samples": []})
            segment["frames"].append(frame)
            phase = row.get("measurement_phase", "steady")
            if phase not in ("steady", "loading_warmup"):
                raise ValueError("Unknown frame measurement phase")
            segment["warmup_frames" if phase == "loading_warmup" else "steady_frames"].append(frame)
            if name != previous_segment:
                segment["intervals_s"].append([previous_time, elapsed])
            else:
                segment["intervals_s"][-1][1] = elapsed
            previous_segment, previous_time = name, elapsed
    for sample in samples:
        name = sample.get("gameplay_segment")
        if name in segments and not sample.get("text_exempt", False):
            segments[name]["text_samples"].append(sample.get("total_visible_characters"))
    audio_path = directory / "audio.json"
    audio = json.loads(audio_path.read_text(encoding="utf-8-sig")) if audio_path.is_file() else {}
    audio_complete = finalized and audio.get("status") == "complete" and not any(s.get("audio_discarded_frames", 0) or s.get("audio_writer", {}).get("error", 0) for s in samples)
    ffmpeg = find_ffmpeg() if audio_complete else None
    for name, segment in segments.items():
        all_frames = frame_statistics(segment.pop("frames"))
        steady = frame_statistics(segment.pop("steady_frames"))
        warmup = frame_statistics(segment.pop("warmup_frames"))
        text = [n for n in segment.pop("text_samples") if isinstance(n, (int, float))]
        spikes = steady["spikes_over_33_3_ms"]
        segment.update(all_frames)
        segment.update(steady=steady, loading_warmup=warmup,
                       raw_spikes_over_33_3_ms=all_frames["spikes_over_33_3_ms"], spikes_over_33_3_ms=spikes,
                       max_recorded_visible_characters=max(text) if text else None,
                       text_visibility_policy=metadata.get("content_text_policy", "legacy_visibility_requires_screenshot_audit"))
        # Threshold scores describe observed data. Subjective and missing items stay pending.
        segment["measured_scores"] = [6 if spikes else 8 if finalized and steady["frame_samples"] else None, None, None, None, None, None, None]
        # The old count includes nameplates, controls and the monitor, and has
        # neither word count nor English checks. Retain it as evidence, but do
        # not convert it to the dialogue/prompt score.
        segment["text_score_reason"] = "Visible aggregate lacks prompt classification, word count and English coverage"
        segment["audio"] = {"status": "pending", "reason": "Final complete audio and FFmpeg are required"}
        if ffmpeg and name not in ("boot", "title"):
            segment["audio"] = analyze_audio(directory, name, segment["intervals_s"], int(audio["sample_rate"]), ffmpeg)
            segment["measured_scores"][3], segment["audio_score_reason"] = audio_score(segment["audio"])
    return {"schema_version": 1, "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
            "finalized": finalized, "source_directory": str(directory), "source_identity": metadata.get("source_identity"),
            "entry": metadata.get("entry"), "measurement_context": metadata.get("measurement_context"),
            "snapshot_path": str(snapshot_path) if snapshot_path is not None else None,
            "acceptance_eligible": False if snapshot_path is not None else metadata.get("acceptance_eligible", True),
            "acceptance_scored": False,
            "frame_clock": metadata.get("frame_clock"), "audio_alignment": "PCM sample time from recording start; contiguous frame segment intervals; capture loss makes audio pending",
            "source_sha256": {path.name: file_hash(path) for path in [timeline, directory / "frames.csv"]},
            "segments": segments}


def analyze_audio(directory: Path, name: str, intervals: list, rate: int, ffmpeg: str) -> dict:
    # Select only this observed segment, so title music cannot determine room LUFS.
    expression = "+".join("between(t,%.6f,%.6f)" % (start, end) for start, end in intervals)
    filters = "aselect='" + expression + "',asetpts=N/SR/TB,ebur128=metadata=1:peak=sample+true,ametadata=mode=print:direct=1:file='pipe\\:1'"
    command = [ffmpeg, "-hide_banner", "-nostats", "-f", "f32le", "-ar", str(rate), "-ac", "2",
               "-i", str(directory / "mix.f32le"), "-af", filters, "-f", "null", "-"]
    result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace",
                            timeout=180, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    state = {"status": "complete" if result.returncode == 0 else "error", "ffmpeg_exit_code": result.returncode,
             "method": "FFmpeg EBU R128 / ITU BS.1770 on this segment only", "intervals_s": intervals}
    for line in result.stdout.splitlines():
        update_metadata(state, line)
    log = directory / ("segment-" + name + "-audio.log")
    log.write_text("COMMAND " + json.dumps(command, ensure_ascii=False) + "\n" + result.stderr, encoding="utf-8")
    return state


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--incomplete", action="store_true")
    args = parser.parse_args()
    result = summarize(args.directory, incomplete=args.incomplete)
    output = args.directory / ("segment-metrics-partial.json" if args.incomplete else "segment-metrics.json")
    output.write_text(json.dumps(result, ensure_ascii=False, allow_nan=False, indent=2) + "\n", encoding="utf-8")
    print(output)
