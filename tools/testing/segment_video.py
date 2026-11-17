"""Export one completed MCP segment recording to a timestamped review video.

The monitor's PNG sequence is sampled video, not a performance benchmark. Frame
holds are explicitly documented in the sidecar; the original timestamps, PCM,
manifest and telemetry remain the measurement sources. Export only after the
owned Godot session has closed and the recording has been finalized.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import sys
import tempfile

import yaml

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "mcp"))
import capture_provenance as provenance
from audio_watch import find_ffmpeg


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def finite_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def inspect_recording(directory: Path, segment: str) -> dict:
    """Validate finalized evidence and find one contiguous segment interval."""
    provenance.assert_runtime_root(ROOT)
    directory = provenance.project_path(directory, ROOT)
    if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,63}", segment):
        raise ValueError("Invalid segment identifier")
    timeline = directory / "timeline.yaml"
    manifest = directory / "dynamic" / "frames.jsonl"
    audio_metadata = directory / "audio.json"
    pcm = directory / "mix.f32le"
    frame_log = directory / "frames.csv"
    if not all(path.is_file() for path in (timeline, manifest, audio_metadata, pcm, frame_log)):
        raise ValueError("Finalized timeline, frame manifest, frame timing, audio metadata and PCM are required")
    document = yaml.safe_load(timeline.read_text(encoding="utf-8-sig"))
    if not isinstance(document, dict) or not isinstance(document.get("metadata"), dict) or not isinstance(document.get("summary"), dict):
        raise ValueError("Timeline is not finalized")
    metadata, summary = document["metadata"], document["summary"]
    identity = metadata.get("source_identity", {})
    provenance.validate_source(identity, provenance.project_identity(ROOT))
    pid = identity.get("process_id")
    if isinstance(pid, bool) or not isinstance(pid, int) or pid <= 0 or not directory.name.endswith("-" + str(pid)):
        raise ValueError("Recording directory and host PID do not match")
    test_id, revision = metadata.get("test_id"), metadata.get("revision")
    if not isinstance(test_id, str) or not test_id or not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{7,40}", revision):
        raise ValueError("Recording test ID and source revision are required")
    plan = provenance.project_path(metadata.get("assessment_plan", ""), ROOT)
    if not plan.is_file() or digest(plan) != metadata.get("assessment_plan_sha256"):
        raise ValueError("Assessment plan is missing or changed")
    plan_data = json.loads(plan.read_text(encoding="utf-8-sig"))
    if plan_data.get("test_id") != test_id or plan_data.get("revision") != revision or plan_data.get("segment_id") != segment:
        raise ValueError("Assessment plan identity or segment does not match")
    audio = json.loads(audio_metadata.read_text(encoding="utf-8-sig"))
    rate = audio.get("sample_rate")
    writer = summary.get("audio_writer", {})
    offset = summary.get("master_start_offset_s")
    if (audio.get("status") != "complete" or not finite_number(rate) or int(rate) != rate or not 8000 <= rate <= 192000
            or not isinstance(writer, dict) or writer.get("error") != 0 or writer.get("bytes_queued") != 0
            or writer.get("bytes_written") != pcm.stat().st_size or pcm.stat().st_size == 0 or pcm.stat().st_size % 8
            or summary.get("audio_discarded_frames") != 0 or not finite_number(offset)):
        raise ValueError("Audio capture is incomplete, unaligned or has dropped frames")
    rows = [json.loads(line) for line in manifest.read_text(encoding="utf-8-sig").splitlines() if line.strip()]
    if not rows or rows[0].get("type") != "configuration" or rows[-1].get("type") != "summary":
        raise ValueError("Frame capture is not finalized")
    config, result = rows[0], rows[-1]
    missed = [row for row in rows[1:-1] if row.get("type") == "missed_sample"]
    if (config.get("timebase") != "RuntimeMonitor elapsed_s" or config.get("fixed_timestep") is not False
            or result.get("write_failures") != 0 or result.get("skipped_samples") != len(missed)
            or any(not finite_number(row.get("elapsed_s")) for row in missed)
            or any(row.get("type") not in ("frame", "missed_sample") for row in rows[1:-1])):
        raise ValueError("Frame capture has inconsistent gaps or unsupported timing")
    frames = [row for row in rows[1:-1] if row.get("type") == "frame"]
    if len(frames) != result.get("frames"):
        raise ValueError("Frame manifest count or record type is invalid")
    chosen = []
    for index, row in enumerate(frames):
        if row.get("sequence") != index + 1 or row.get("error") != 0 or not finite_number(row.get("elapsed_s")):
            raise ValueError("Frame sequence or timestamp is invalid")
        if index and row["elapsed_s"] <= frames[index-1]["elapsed_s"]:
            raise ValueError("Frame timestamps must be strictly increasing")
        image = provenance.project_path(row.get("path", ""), ROOT)
        if (image.parent != manifest.parent or not re.fullmatch(r"\d{7}\.png", image.name)
                or not image.is_file() or digest(image) != row.get("sha256")):
            raise ValueError("Captured frame is missing, misplaced or has changed")
        if str(row.get("scene_node", "")).split("/", 1)[0] == segment:
            chosen.append((index, row, image))
    if len(chosen) < 2 or chosen[-1][0] - chosen[0][0] + 1 != len(chosen):
        raise ValueError("Segment must have at least two contiguous captured frames")
    start, last = chosen[0][1]["elapsed_s"], chosen[-1][1]["elapsed_s"]
    if chosen[-1][0] + 1 < len(frames):
        end = frames[chosen[-1][0] + 1]["elapsed_s"]
        end_source = "next recorded frame"
    else:
        final_row = None
        with frame_log.open(encoding="utf-8-sig", newline="") as stream:
            for row in csv.DictReader(stream):
                final_row = row
        try:
            end = float(final_row["elapsed_s"])
            last_number = int(final_row["frame"])
        except (TypeError, KeyError, ValueError):
            raise ValueError("Final frame timing is unavailable")
        if last_number != summary.get("frames"):
            raise ValueError("Frame timing does not cover the finalized monitor session")
        end_source = "finalized monitor frame timing"
    if not finite_number(end) or end <= last:
        raise ValueError("A recorded end time after the last segment frame is required")
    audio_start = start + offset
    duration = end - start
    if audio_start < 0 or audio_start + duration > pcm.stat().st_size / (8 * rate):
        raise ValueError("PCM does not cover the captured segment interval")
    return {"test_id": test_id, "revision": revision, "segment_id": segment, "host_pid": pid,
            "start_elapsed_s": start, "end_elapsed_s": end, "duration_s": duration,
            "audio_start_s": audio_start, "audio_offset_s": offset, "sample_rate": int(rate), "end_time_source": end_source,
            "frames": [{"path": str(path), "elapsed_s": row["elapsed_s"], "sha256": row["sha256"]}
                       for _, row, path in chosen],
            "source_sha256": {"timeline.yaml": digest(timeline), "frames.jsonl": digest(manifest),
                              "audio.json": digest(audio_metadata), "frames.csv": digest(frame_log), "mix.f32le": digest(pcm), "assessment_plan": digest(plan)},
            "sampling": {"requested_hz": config.get("sample_hz"), "skipped_samples": result["skipped_samples"],
                         "missed_sample_times_s": [row["elapsed_s"] for row in missed],
                         "frame_holds": "Each captured image is displayed until the next recorded timestamp.",
                         "scope": "First captured segment frame through the next frame or finalized monitor time; the video is not performance telemetry."},
            "pcm_path": str(pcm), "dynamic_directory": str(manifest.parent)}


def export_video(directory: Path, segment: str, output: Path) -> dict:
    info = inspect_recording(directory, segment)
    destination = provenance.project_path(output, ROOT)
    if destination.suffix.lower() != ".mp4":
        raise ValueError("Output must be an MP4 file")
    sidecar = destination.with_suffix(destination.suffix + ".json")
    if destination.exists() or sidecar.exists():
        raise FileExistsError("Video output or provenance sidecar already exists")
    ffmpeg = find_ffmpeg()
    if not ffmpeg:
        raise FileNotFoundError("FFmpeg is unavailable")
    destination.parent.mkdir(parents=True, exist_ok=True)
    frames, dynamic = info["frames"], Path(info["dynamic_directory"])
    lines = ["ffconcat version 1.0"]
    for first, second in zip(frames, frames[1:]):
        lines += [f"file '{Path(first['path']).name}'", "option framerate 1000",
                  f"duration {second['elapsed_s'] - first['elapsed_s']:.9f}"]
    lines += [f"file '{Path(frames[-1]['path']).name}'", "option framerate 1000",
              f"duration {info['end_elapsed_s'] - frames[-1]['elapsed_s']:.9f}",
              f"file '{Path(frames[-1]['path']).name}'", "option framerate 1000"]
    concat = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", newline="\n", suffix=".ffconcat", dir=dynamic, delete=False) as stream:
            stream.write("\n".join(lines) + "\n")
            concat = Path(stream.name)
        command = [ffmpeg, "-hide_banner", "-loglevel", "error", "-n", "-f", "concat", "-safe", "0", "-i", str(concat),
                   "-f", "f32le", "-ar", str(info["sample_rate"]), "-ac", "2", "-ss", f"{info['audio_start_s']:.9f}",
                   "-i", info["pcm_path"], "-t", f"{info['duration_s']:.9f}", "-map", "0:v:0", "-map", "1:a:0",
                   "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2", "-fps_mode", "vfr", "-c:v", "libx264", "-preset", "veryfast",
                   "-pix_fmt", "yuv420p", "-video_track_timescale", "1000000", "-c:a", "aac", "-b:a", "160k",
                   "-movflags", "+faststart", str(destination)]
        completed = subprocess.run(command, cwd=dynamic, capture_output=True, text=True, timeout=3600)
        if completed.returncode or not destination.is_file() or not destination.stat().st_size:
            raise RuntimeError("FFmpeg export failed: " + completed.stderr[-3000:])
        info.update(video=str(destination.relative_to(ROOT)), video_sha256=digest(destination), video_bytes=destination.stat().st_size,
                    video_encoding="Variable-frame-rate H.264/AAC; timestamps derived from observed frames; lossy review copy")
        sidecar.write_text(json.dumps(info, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
        return info
    except BaseException:
        if destination.is_file(): destination.unlink()
        if sidecar.is_file(): sidecar.unlink()
        raise
    finally:
        if concat is not None and concat.exists(): concat.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("session", type=Path)
    parser.add_argument("segment")
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()
    print(json.dumps(export_video(arguments.session, arguments.segment, arguments.output), ensure_ascii=False))


if __name__ == "__main__":
    main()
