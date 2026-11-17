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


def audio_score(audio: dict, background: dict | None = None) -> tuple[int | None, str]:
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
    if background and background.get("complete") and background.get("signal_present"):
        measured = background.get("measured_peak_dbtp")
        if _valid_gain(measured) and measured >= -20:
            return 6, "Measured isolated background true peak is not below -20 dBTP"
    if peak < -20:
        return 8, "Integrated loudness and the entire mix peak are below -20"
    if background and background.get("complete") and background.get("signal_present"):
        bound = background.get("peak_upper_bound_dbtp")
        if isinstance(bound, (int, float)) and not isinstance(bound, bool) and math.isfinite(bound) and bound < -20:
            return 8, "Integrated loudness and isolated background peak upper bound are below -20"
    return None, "Ambient-only peak is not isolated from dialogue or effects"


def summarize(directory: Path, *, incomplete: bool = False, snapshot_path: Path | None = None, scenario_path: Path | None = None) -> dict:
    provenance.assert_runtime_root(ROOT)
    directory = provenance.project_path(directory, ROOT)
    timeline = directory / "timeline.yaml"
    header, samples, summary_lines = [], [], []
    in_timeline, finalized = False, False
    with timeline.open(encoding="utf-8-sig") as stream:
        for line in stream:
            if line.startswith("timeline:"):
                in_timeline = True
            elif line.startswith(("summary:", '"summary":')):
                finalized = True
                summary_lines.append(line)
                continue
            elif finalized:
                summary_lines.append(line)
                continue
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
    summary = (yaml.safe_load("".join(summary_lines)) or {}).get("summary", {}) if finalized else {}
    source = metadata.get("source_identity", {})
    provenance.validate_source(source, provenance.project_identity(ROOT))
    if not isinstance(source.get("process_id"), int) or source["process_id"] <= 0:
        raise ValueError("Recorded actual host PID is required")
    if snapshot_path is not None and scenario_path is not None:
        raise ValueError("Scenario and snapshot modes are mutually exclusive")
    if snapshot_path is None and scenario_path is None:
        if metadata.get("mock") is not False or metadata.get("entry") != "production_title" or metadata.get("acceptance_eligible") is False:
            raise ValueError("Only production title/new-game capture enters mainline metrics")
    elif snapshot_path is not None:
        snapshot_path = provenance.project_path(snapshot_path, ROOT)
        recorded_snapshot = metadata.get("snapshot_path")
        if (metadata.get("mock") is not True or metadata.get("entry") != "snapshot"
                or metadata.get("acceptance_eligible") is not False
                or not isinstance(recorded_snapshot, str) or not recorded_snapshot
                or provenance.project_path(recorded_snapshot, ROOT) != snapshot_path):
            raise ValueError("Snapshot metadata does not match the development session")
    else:
        scenario_path = provenance.project_path(scenario_path, ROOT)
        recorded_scenario = metadata.get("scenario_path")
        if (not scenario_path.is_file() or metadata.get("mock") is not True or metadata.get("entry") != "scenario"
                or not isinstance(recorded_scenario, str) or not recorded_scenario
                or provenance.project_path(recorded_scenario, ROOT) != scenario_path):
            raise ValueError("Scenario metadata does not match the rendered session")
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
    audio_complete = finalized and audio.get("status") == "complete" and not (summary.get("audio_discarded_frames", 0) or summary.get("audio_writer", {}).get("error", 0)) and not any(s.get("audio_discarded_frames", 0) or s.get("audio_writer", {}).get("error", 0) for s in samples)
    route = summary.get("audio_route", {})
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
            segment_route = route_for_intervals(route, segment["intervals_s"])
            snapshot = segment_route.get("snapshot", {})
            buses = snapshot.get("buses", {})
            master = buses.get("Master", {})
            route_valid = segment_route.get("stable") is True and snapshot.get("any_solo") is False and master.get("muted") is False and master.get("bypass") is False and master.get("capture_active") is True and _valid_gain(master.get("volume_db"))
            if not route_valid:
                segment["audio_score_reason"] = "Audio route changed during this scene or capture was muted or unavailable"
                continue
            master_offset = summary.get("master_start_offset_s")
            if not _valid_gain(master_offset):
                segment["audio_score_reason"] = "Master capture time offset is unavailable"
                continue
            master_intervals = shift_intervals(segment["intervals_s"], master_offset)
            segment["audio"] = analyze_audio(directory, name, master_intervals, int(audio["sample_rate"]), ffmpeg, gain_db=master["volume_db"])
            background = analyze_background(directory, name, segment["intervals_s"], int(audio["sample_rate"]), ffmpeg, metadata, dict(summary, audio_route=segment_route))
            segment["background_audio"] = background
            segment["measured_scores"][3], segment["audio_score_reason"] = audio_score(segment["audio"], background)
    return {"schema_version": 1, "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
            "finalized": finalized, "source_directory": str(directory), "source_identity": metadata.get("source_identity"),
            "entry": metadata.get("entry"), "measurement_context": metadata.get("measurement_context"),
            "snapshot_path": str(snapshot_path) if snapshot_path is not None else None,
            "scenario_path": str(scenario_path) if scenario_path is not None else None,
            "acceptance_eligible": False if snapshot_path is not None or scenario_path is not None else metadata.get("acceptance_eligible", True),
            "acceptance_scored": False,
            "frame_clock": metadata.get("frame_clock"), "audio_alignment": "Frame intervals shifted by each capture start offset; audio mix-block timing uncertainty remains; capture loss makes audio pending",
            "source_sha256": {path.name: file_hash(path) for path in [timeline, directory / "frames.csv"]},
            "segments": segments}


def _valid_gain(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def route_for_intervals(route, intervals):
    """Choose one unchanged route for the scene; nearby transitions fail closed."""
    if not isinstance(route, dict) or not intervals:
        return {}
    changes = route.get("changes")
    if changes is None:
        return route if route.get("stable") is True else {}
    if not isinstance(changes, list) or not changes:
        return {}
    previous = -1.0
    for change in changes:
        if not isinstance(change, dict) or not _valid_gain(change.get("elapsed_s")) or change["elapsed_s"] < previous or not isinstance(change.get("snapshot"), dict):
            return {}
        previous = change["elapsed_s"]
    if changes[0]["elapsed_s"] != 0:
        return {}
    selected = None
    for start, end in intervals:
        if not _valid_gain(start) or not _valid_gain(end) or start < 0 or end <= start:
            return {}
        # Route is sampled once per frame; leave a 50 ms margin around changes.
        if any(start - .05 <= change["elapsed_s"] <= end + .05 for change in changes[1:]):
            return {}
        candidates = [change for change in changes if change["elapsed_s"] < start or change["elapsed_s"] == 0]
        if not candidates:
            return {}
        current = candidates[-1]["snapshot"]
        if selected is not None and current != selected:
            return {}
        selected = current
    return {"stable": True, "snapshot": selected}


def shift_intervals(intervals, offset):
    if not _valid_gain(offset): raise ValueError("Capture timing offset unavailable")
    result = [[start + offset, end + offset] for start, end in intervals]
    if any(start < 0 or end <= start for start, end in result): raise ValueError("Invalid capture interval")
    return result


def analyze_background(directory: Path, name: str, intervals: list, rate: int, ffmpeg: str, metadata: dict, summary: dict) -> dict:
    """Bound simultaneous pre-fader captures after bus and master gains.

    The linear sum of individual peak amplitudes is conservative even when
    tracks peak at different times. An unknown route or missing channel fails closed.
    """
    out = {"complete": False, "signal_present": False, "tracks": {}, "peak_upper_bound_dbtp": None}
    route = summary.get("audio_route", {})
    snap = route.get("snapshot", {})
    buses = snap.get("buses", {})
    master = buses.get("Master", {})
    inventory = metadata.get("background_bus_inventory", [])
    statuses = summary.get("background_audio", {})
    if not inventory or route.get("stable") is not True or snap.get("any_solo") is not False or master.get("muted") is not False or master.get("bypass") is not False or master.get("capture_active") is not True or master.get("other_effects") or not _valid_gain(master.get("volume_db")):
        out["reason"] = "Background route, master effects, or source inventory is not verifiable"
        return out
    peaks = []
    for bus in inventory:
        if bus not in ("Music", "Ambient"):
            out["reason"] = "Unrecognized background bus"
            return out
        info, status = buses.get(bus, {}), statuses.get(bus, {})
        stem = "background-" + bus.lower()
        path = directory / (stem + ".json")
        try:
            channel = json.loads(path.read_text(encoding="utf-8-sig"))
            valid = (info.get("muted") is False and info.get("bypass") is False and info.get("capture_active") is True and info.get("send") == "Master" and _valid_gain(info.get("volume_db")) and status.get("worker_pid", -1) > 0 and status.get("discarded_frames") == 0 and status.get("writer", {}).get("error") == 0 and status.get("writer", {}).get("bytes_queued") == 0 and _valid_gain(status.get("start_offset_s")) and channel.get("status") == "complete" and channel.get("ffmpeg_exit_code") == 0 and (directory / (stem + ".f32le")).is_file() and status.get("writer", {}).get("bytes_written", 0) > 0 and status["writer"]["bytes_written"] == (directory / (stem + ".f32le")).stat().st_size)
            if not valid:
                raise ValueError("channel incomplete or route invalid")
            state = analyze_audio(directory, name, shift_intervals(intervals, status["start_offset_s"]), rate, ffmpeg, stem=stem, gain_db=info["volume_db"] + master["volume_db"])
            if state.get("status") != "complete": raise ValueError("segment analysis failed")
            out["tracks"][bus] = state
            if state.get("signal_present"):
                peak = state.get("true_peak_dbtp")
                if not _valid_gain(peak): raise ValueError("peak unavailable")
                peaks.append(float(peak))
        except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError) as exc:
            out["reason"] = str(exc)
            return out
    out["complete"] = True
    if peaks:
        out["signal_present"] = True
        # A single non-silent track has a measured background peak. With two
        # or more tracks, summing magnitudes gives only a conservative bound.
        if len(peaks) == 1:
            out["measured_peak_dbtp"] = peaks[0]
        out["peak_upper_bound_dbtp"] = 20 * math.log10(sum(10 ** (p / 20) for p in peaks))
    else:
        out["reason"] = "No verified background audio signal in this scene interval"
    return out


def analyze_audio(directory: Path, name: str, intervals: list, rate: int, ffmpeg: str, *, stem: str = "mix", gain_db: float = 0.0) -> dict:
    """Seek each selected raw-PCM interval and analyze them as one stream."""
    if not isinstance(rate, int) or isinstance(rate, bool) or rate <= 0 or not _valid_gain(gain_db):
        raise ValueError("Invalid audio rate or gain")
    source = directory / (stem + ".f32le")
    size = source.stat().st_size
    if size % 8:
        raise ValueError("Incomplete stereo float audio frame")
    duration = size / (8 * rate)
    if not intervals:
        raise ValueError("Audio intervals are empty")
    ranges = []
    previous_end = 0.0
    for interval in intervals:
        if not isinstance(interval, (list, tuple)) or len(interval) != 2:
            raise ValueError("Invalid audio interval")
        start, end = interval
        if not _valid_gain(start) or not _valid_gain(end) or start < 0 or end <= start or start < previous_end:
            raise ValueError("Invalid or overlapping audio interval")
        # Capture and frame clocks can differ by one audio mixer block at shutdown.
        if end > duration + 0.05 or start >= duration:
            raise ValueError("Audio capture does not cover the scene interval")
        ranges.append((start, min(end, duration)))
        previous_end = end
    command = [ffmpeg, "-hide_banner", "-nostats"]
    for start, end in ranges:
        command.extend(["-ss", "%.9f" % start, "-t", "%.9f" % (end - start), "-f", "f32le", "-ar", str(rate), "-ac", "2", "-i", str(source)])
    filters = "volume=" + str(gain_db) + "dB,ebur128=metadata=1:peak=sample+true,ametadata=mode=print:direct=1:file='pipe\\:1'"
    if len(ranges) == 1:
        command.extend(["-af", filters])
    else:
        inputs = "".join("[%d:a]" % i for i in range(len(ranges)))
        command.extend(["-filter_complex", inputs + "concat=n=" + str(len(ranges)) + ":v=0:a=1," + filters])
    command.extend(["-f", "null", "-"])
    result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace",
                            timeout=180, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    state = {"status": "complete" if result.returncode == 0 else "error", "ffmpeg_exit_code": result.returncode,
             "method": "FFmpeg EBU R128 / ITU BS.1770 on selected PCM intervals", "intervals_s": intervals,
             "analyzed_intervals_s": ranges, "capture_tail_clipped_s": max(0.0, intervals[-1][1] - duration)}
    for line in result.stdout.splitlines():
        update_metadata(state, line)
    log = directory / ("segment-" + name + "-" + stem + "-audio.log")
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
