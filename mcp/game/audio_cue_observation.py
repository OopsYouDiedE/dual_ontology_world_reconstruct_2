"""Read scheduling-only audio cues from an owned monitor directory.

These records contain no asserted sound identity or audibility. The caller is
responsible for validating the session directory before calling this reader.
"""
import json
import math
from pathlib import Path


def read_cues(directory, cursor=0, limit=128):
    path = Path(directory) / "audio-cues.jsonl"
    if not path.is_file():
        return {"available": False, "reason": "Audio cue collection has not started", "events": []}, cursor
    if not isinstance(cursor, int) or cursor < 0:
        raise ValueError("Audio cue cursor must be a nonnegative byte offset")
    if not isinstance(limit, int) or limit < 1:
        raise ValueError("Audio cue limit must be a positive integer")
    events = []
    with path.open("rb") as stream:
        stream.seek(0, 2)
        if cursor > stream.tell():
            return {"available": False, "reason": "Audio cue file was truncated", "events": []}, cursor
        stream.seek(cursor)
        while len(events) < limit:
            start = stream.tell()
            raw = stream.readline()
            if not raw:
                break
            if not raw.endswith(b"\n"):
                stream.seek(start)
                break
            try:
                item = json.loads(raw.decode("utf-8"))
                if not isinstance(item, dict):
                    raise ValueError("record is not an object")
                kind = item.get("type")
                if kind not in {"configuration", "scheduled", "finalized"}:
                    raise ValueError("unknown record type")
                if kind == "scheduled":
                    if item.get("category") not in {"global_effect", "spatial_effect"}:
                        raise ValueError("unknown scheduled category")
                    elapsed = item.get("elapsed_s")
                    if isinstance(elapsed, bool) or not isinstance(elapsed, (int, float)) or not math.isfinite(elapsed) or elapsed < 0:
                        raise ValueError("invalid scheduled elapsed time")
                    if any(isinstance(item.get(key), bool) or not isinstance(item.get(key), int) or item[key] < minimum for key, minimum in (("frame", 0), ("sequence", 1))):
                        raise ValueError("invalid scheduled frame or sequence")
            except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
                return {"available": False, "reason": "Invalid audio cue record: " + str(error), "events": events}, start
            events.append(item)
        next_cursor = stream.tell()
        more = bool(stream.read(1))
    return {"available": True, "events": events, "more": more, "scope": "Scheduling only; audibility and sound identity are not established."}, next_cursor
