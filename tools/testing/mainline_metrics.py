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

import yaml
from audio_watch import find_ffmpeg, update_metadata


def file_hash(path: Path) -> str:
    digest = sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1048576), b""):
            digest.update(chunk)
    return digest.hexdigest()


def summarize(directory: Path, *, incomplete: bool = False) -> dict:
    directory = directory.resolve()
    timeline = directory / "timeline.yaml"
    header, samples = [], []
    in_timeline, finalized = False, False
    with timeline.open(encoding="utf-8-sig") as stream:
        for line in stream:
            if line.startswith("timeline:"):
                in_timeline = True
            elif line.startswith("summary:"):
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
    if metadata.get("mock") is not False or metadata.get("entry") != "production_title":
        raise ValueError("Only production title/new-game capture enters mainline metrics")
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
            if not math.isfinite(frame) or frame <= 0 or elapsed < previous_time:
                raise ValueError("Invalid wall-clock frame sample")
            segment = segments.setdefault(name, {"frames": [], "intervals_s": [], "text_samples": []})
            segment["frames"].append(frame)
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
    audio_complete = finalized and audio.get("status") == "complete" and not any(s.get("audio_discarded_frames", 0) for s in samples)
    ffmpeg = find_ffmpeg() if audio_complete else None
    for name, segment in segments.items():
        frames = sorted(segment.pop("frames"))
        text = [n for n in segment.pop("text_samples") if isinstance(n, (int, float))]
        spikes = sum(value > 33.3 for value in frames)
        percentile = lambda p: frames[max(0, math.ceil(len(frames) * p) - 1)]
        low = lambda p: 1000 / (sum(frames[-max(1, math.ceil(len(frames) * p)):]) / max(1, math.ceil(len(frames) * p)))
        segment.update(frame_samples=len(frames), avg_fps=1000 * len(frames) / sum(frames),
                       low_5_fps=low(.05), low_1_fps=low(.01), frame_p95_ms=percentile(.95),
                       frame_p99_ms=percentile(.99), max_frame_ms=frames[-1], spikes_over_33_3_ms=spikes,
                       max_recorded_visible_characters=max(text) if text else None,
                       text_visibility_policy=metadata.get("content_text_policy", "legacy_visibility_requires_screenshot_audit"))
        # Threshold scores describe observed data. Subjective and missing items stay pending.
        segment["measured_scores"] = [6 if spikes else 8 if finalized else None, None, None, None, None, None, None]
        if text and metadata.get("content_text_policy") == "visible_active_viewports":
            segment["measured_scores"][1] = 6 if max(text) > 25 else 10 if max(text) == 0 else 8 if finalized else None
        segment["audio"] = {"status": "pending", "reason": "Final complete audio and FFmpeg are required"}
        if ffmpeg and name not in ("boot", "title"):
            segment["audio"] = analyze_audio(directory, name, segment["intervals_s"], int(audio["sample_rate"]), ffmpeg)
            loudness = segment["audio"].get("integrated_lufs")
            peak = segment["audio"].get("true_peak_dbtp")
            if loudness is not None and peak is not None:
                segment["measured_scores"][3] = 8 if loudness <= -20 and peak < 0 else 6
    return {"schema_version": 1, "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
            "finalized": finalized, "source_directory": str(directory), "source_identity": metadata.get("source_identity"),
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
