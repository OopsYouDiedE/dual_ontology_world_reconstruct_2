"""Evaluate the acceptance gate, independently of gameplay or the artist's claims."""
from datetime import datetime, timedelta, timezone
import argparse
import hashlib
import json
from pathlib import Path
import re

WINDOW = timedelta(hours=20)
ROUND = timedelta(minutes=20)
REQUIRED_EVIDENCE = {"brief", "contact", "golden", "live_trace", "frame_manifest", "source_manifest", "render_receipt"}
ADMISSIBLE_CLEAR = {"normal-input", "authoritative-model"}


def instant(text):
    date = datetime.fromisoformat(text)
    if date.tzinfo is None or date.utcoffset() is None:
        raise ValueError(f"Timezone required: {text}")
    return date


def artifact_valid(record, folder):
    if not isinstance(record, dict) or not isinstance(record.get("file"), str):
        return False
    target = (folder / record["file"]).resolve()
    if not target.is_relative_to(folder.resolve()) or not target.is_file():
        return False
    with target.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest() if hasattr(hashlib, "file_digest") else None
        if digest is None:
            h = hashlib.sha256()
            for chunk in iter(lambda: stream.read(128 * 1024), b""):
                h.update(chunk)
            digest = h.hexdigest()
    return digest == record.get("sha256")


def evaluate(ledger, folder, now):
    freeze = instant(ledger["generated_at"])
    deadline = freeze + WINDOW
    rev = ledger["revision"]
    if not re.fullmatch(r"[0-9a-f]{40}", rev):
        raise ValueError("Freeze revision must be the full commit hash")
    if now < freeze:
        raise ValueError("Evaluation time predates generation")
    missing = []
    result = {"candidate": ledger["candidate"], "revision": rev, "deadline": deadline.isoformat(),
              "eligible_to_send": False, "accepted": False, "status": "awaiting-window", "missing": missing}
    # Clearing within the frozen observation window takes precedence over any art or golden quality.
    counts = {"medium": set(), "high": set()}
    for report in ledger.get("red_reports", []):
        if report.get("revision") != rev or not report.get("independent"):
            continue
        start, end = instant(report["started_at"]), instant(report["ended_at"])
        if not freeze <= start <= end <= min(now, deadline):
            continue
        if not artifact_valid(report.get("receipt"), folder):
            continue
        if report.get("outcome") == "cleared" and report.get("surface") in ADMISSIBLE_CLEAR:
            result.update(status="disqualified", defeating_agent=report["agent"], cleared_at=end.isoformat())
            return result
        if report.get("outcome") == "undefeated" and end - start == ROUND:
            if report.get("role") in counts:
                counts[report["role"]].add(report["agent"])
    if now < deadline:
        return result
    golden = ledger.get("golden", {})
    if golden.get("revision") != rev or golden.get("passed_live") is not True:
        missing.append("verified golden walk on the frozen revision")
    for name in sorted(REQUIRED_EVIDENCE):
        if not artifact_valid(ledger.get("evidence", {}).get(name), folder):
            missing.append(f"valid artifact: {name}")
    if len(counts["medium"]) < 2 or not (counts["high"] - counts["medium"]):
        missing.append("20-minute sealed receipts from two independent medium and one separate high red-team sessions")
    if missing:
        result["status"] = "evidence-incomplete"
        return result
    result.update(status="eligible-for-astra", eligible_to_send=True)
    judge = ledger.get("judge", {})
    if not judge:
        return result
    reviewed = instant(judge["reviewed_at"])
    if (judge.get("revision") != rev or judge.get("model") != "gpt-6.2-astra"
            or judge.get("passive_review") is not True or not deadline <= reviewed <= now
            or not artifact_valid(judge.get("receipt"), folder)):
        result.update(status="judge-receipt-invalid", eligible_to_send=False)
    elif judge.get("solution") == judge.get("art") == "pass":
        result.update(status="accepted", eligible_to_send=False, accepted=True)
    else:
        result.update(status="vetoed", eligible_to_send=False)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ledger", type=Path)
    parser.add_argument("--at", type=instant, help="Audit at a specified timestamp; defaults to now")
    args = parser.parse_args()
    ledger = json.loads(args.ledger.read_text(encoding="utf-8-sig"))
    status = evaluate(ledger, args.ledger.parent, args.at or datetime.now(timezone.utc))
    print(json.dumps(status, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
