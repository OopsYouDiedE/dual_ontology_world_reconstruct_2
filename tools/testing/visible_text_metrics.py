"""Score recorded visible dialogue and prompts from one synchronized session.

The monitor writes one JSONL record whenever visible text or scene node changes.
A caller must supply a truthful collection-complete flag and any observer-verified
classifications / language checks for the exact (node path, displayed text) pair.
"""
from __future__ import annotations

import json
import math
import re
from pathlib import Path
import unicodedata


COUNTED_CATEGORIES = frozenset({"dialogue", "spoken_dialogue", "speech", "prompt", "interaction_prompt"})
EXCLUDED_CATEGORIES = frozenset({"nameplate", "single_key_icon", "action_key_icon", "hud", "menu", "other_ui"})
_WORDS = re.compile(r"[^\W\d_]+(?:['\u2019-][^\W\d_]+)*", re.UNICODE)


def _foreign_letters(text: str) -> bool:
    """Flag non-Latin letter scripts while accepting ordinary Unicode punctuation."""
    for character in text:
        if unicodedata.category(character).startswith("L"):
            if "LATIN" not in unicodedata.name(character, ""):
                return True
    return False


def analyze_visible_text(path: str | Path, *, segment_id: str, collection_complete: bool,
                         reviews: dict[tuple[str, str], dict] | None = None) -> dict:
    """Return a score, an auditable rationale and sampled timeline information.

    ``reviews`` may contain an observer's classification and English verification
    for an exact (visible node path, displayed text) pair. It never changes the
    underlying record. An ``unknown`` category and an unverified Latin string
    remain unresolved until a qualified observer confirms them. A known failure
    may be reported from partial evidence; partial evidence can never grant a pass.
    """
    path = Path(path)
    base = {"score": None, "reason": "", "complete": False, "collection_complete": collection_complete, "records": 0,
            "max_words": 0, "max_characters": 0, "worst_words_at_s": None,
            "worst_characters_at_s": None, "first_frame": None, "last_frame": None,
            "unclassified": [], "unverified_english": [], "non_english": [],
            "evidence": str(path)}
    if not isinstance(segment_id, str) or not segment_id:
        raise ValueError("A segment ID is required")
    if not isinstance(collection_complete, bool):
        raise ValueError("collection_complete must be a boolean")
    if reviews is None:
        reviews = {}
    if not isinstance(reviews, dict):
        raise ValueError("reviews must be keyed by (node path, displayed text)")
    try:
        lines = path.read_text(encoding="utf-8-sig").splitlines()
    except (OSError, UnicodeError) as error:
        base["reason"] = "Visible-text timeline unavailable: " + str(error)
        return base
    records = []
    previous_frame, previous_time = -1, -1.0
    try:
        for number, line in enumerate(lines, 1):
            if not line.strip():
                continue
            record = json.loads(line)
            if not isinstance(record, dict):
                raise ValueError(f"line {number} is not an object")
            frame, elapsed = record.get("frame"), record.get("elapsed_s")
            if (isinstance(frame, bool) or not isinstance(frame, int) or frame < 0
                    or isinstance(elapsed, bool) or not isinstance(elapsed, (int, float))
                    or not math.isfinite(elapsed) or elapsed < 0
                    or frame < previous_frame or elapsed < previous_time):
                raise ValueError(f"line {number} has invalid or out-of-order time")
            if not isinstance(record.get("scene_node"), str) or not isinstance(record.get("entries"), list):
                raise ValueError(f"line {number} lacks scene node or visible entries")
            previous_frame, previous_time = frame, elapsed
            if record["scene_node"].split("/", 1)[0] == segment_id:
                records.append(record)
    except (ValueError, TypeError, json.JSONDecodeError) as error:
        base["reason"] = "Visible-text timeline invalid: " + str(error)
        return base
    if not records:
        base["reason"] = "No visible-text timeline samples were recorded for this segment."
        return base

    unresolved, language_pending, foreign = set(), set(), set()
    base["records"] = len(records)
    base["first_frame"], base["last_frame"] = records[0]["frame"], records[-1]["frame"]
    for record in records:
        words = characters = 0
        for entry in record["entries"]:
            if not isinstance(entry, dict) or not isinstance(entry.get("text"), str) or not isinstance(entry.get("path"), str):
                base["reason"] = "Visible-text timeline contains an entry without a node path and string text."
                return base
            text = entry["text"].strip()
            if not text:
                continue
            key = (entry["path"], entry["text"])
            review = reviews.get(key, {})
            if not isinstance(review, dict):
                raise ValueError("Each visible-text review must be an object")
            category = review.get("category", entry.get("category", "unknown"))
            if not isinstance(category, str):
                base["reason"] = "Visible-text timeline contains an invalid classification."
                return base
            english_verified = review.get("english_verified", entry.get("english_verified", False)) is True
            identifier = entry["path"] + ": " + text
            if _foreign_letters(text):
                foreign.add(identifier)
            elif any(unicodedata.category(char).startswith("L") for char in text) and not english_verified:
                language_pending.add(identifier)
            if category in COUNTED_CATEGORIES:
                words += len(_WORDS.findall(text))
                characters += len(text)
            elif category not in EXCLUDED_CATEGORIES:
                # The monitor's single_key_or_text tag deliberately remains
                # ambiguous: a one-character text is not automatically a key.
                unresolved.add(identifier)
        if base["worst_words_at_s"] is None or words > base["max_words"]:
            base["max_words"], base["worst_words_at_s"] = words, record["elapsed_s"]
        if base["worst_characters_at_s"] is None or characters > base["max_characters"]:
            base["max_characters"], base["worst_characters_at_s"] = characters, record["elapsed_s"]

    base["unclassified"] = sorted(unresolved)
    base["unverified_english"] = sorted(language_pending)
    base["non_english"] = sorted(foreign)
    base["complete"] = collection_complete and not unresolved and not language_pending
    metrics = (f"{base['records']} visible-text changes; maximum {base['max_words']} words "
               f"and {base['max_characters']} characters in one frame")
    incomplete = " Collection was incomplete." if not collection_complete else ""
    if foreign:
        base["score"] = 6
        base["reason"] = "Non-English script was visible: " + "; ".join(sorted(foreign)[:5]) + ". " + metrics + "." + incomplete
    elif base["max_words"] > 12 or base["max_characters"] > 60:
        base["score"] = 6
        base["reason"] = "Visible dialogue or prompts exceeded the rubric limit. " + metrics + "." + incomplete
    elif not collection_complete:
        base["reason"] = "Visible-text collection was interrupted or coverage was not verified. " + metrics + "."
    elif unresolved or language_pending:
        reasons = []
        if unresolved: reasons.append(f"{len(unresolved)} visible strings lack a verified text classification")
        if language_pending: reasons.append(f"{len(language_pending)} visible strings lack English verification")
        base["reason"] = "; ".join(reasons) + ". " + metrics + "."
    else:
        base["score"] = 10 if base["max_characters"] == 0 else 8
        base["reason"] = ("No visible dialogue or prompts. " if base["score"] == 10 else "Visible dialogue and prompts meet both limits and English checks. ") + metrics + "."
    return base
