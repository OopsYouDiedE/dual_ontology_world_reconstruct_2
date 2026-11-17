"""Project-bound, locked, immutable review/progress persistence."""
from __future__ import annotations

from contextlib import contextmanager
from datetime import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import threading
import time

import yaml

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "mcp"))
sys.path.insert(0, str(ROOT / "tools/testing"))
import capture_provenance as provenance
import mainline_reviews
import visual_semantic_reviews
import test_results

ID = r"[a-z0-9][a-z0-9_-]{1,119}"
SCORE_CATEGORIES = ("fluidity", "text_density", "action_sfx_integrity", "audio_loudness",
                    "blind_narrative_match", "aesthetic_similarity", "narrative_flow")
_THREAD_LOCK = threading.Lock()
_RENDER_THREAD_LOCK = threading.Lock()


def encoded(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def digest(value):
    return hashlib.sha256(encoded(value)).hexdigest()


def atomic_write(path: Path, content: str, *, exclusive=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".review-", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        if exclusive:
            # A hard link publishes the complete file with create-only semantics.
            os.link(temporary, path)
        else:
            for attempt in range(20):
                try:
                    os.replace(temporary, path)
                    break
                except PermissionError:
                    if attempt == 19:
                        raise
                    time.sleep(0.025)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


class Store:
    def __init__(self, expected_project_root=None, test_sandbox=None, *, server_script=None):
        self.root = provenance.assert_runtime_root(ROOT, expected_project_root)
        # Other project-bound services may reuse the exact same locked ledger.
        # Their actual script/PID, not the review server's path, is recorded.
        self.server_script = provenance.project_path(server_script or Path(__file__).with_name("server.py"), self.root)
        if not self.server_script.is_file():
            raise ValueError("Ledger publisher script must exist inside the project")
        self.base = self.root
        self.testing = test_sandbox is not None
        if self.testing:
            self.base = provenance.project_path(test_sandbox, self.root)
            allowed = self.root / ".runtime/review-tests"
            if self.base == allowed or not self.base.is_relative_to(allowed):
                raise ValueError("Test sandbox must be a child of .runtime/review-tests")
        self.progress = provenance.project_path(self.base / "artifacts/acceptance/mainline_progress.yaml", self.root)
        self.live = provenance.project_path(self.base / "artifacts/review/live-progress.js", self.root)
        self.reviews = provenance.project_path(self.base / mainline_reviews.DIRECTORY, self.root)
        self.lockfile = provenance.project_path(self.base / ".runtime/review.lock", self.root)

    @contextmanager
    def locked(self, *, render=False):
        provenance.assert_runtime_root(self.root)
        thread_lock = _RENDER_THREAD_LOCK if render else _THREAD_LOCK
        lockfile = self.lockfile.with_name("review-render.lock") if render else self.lockfile
        with thread_lock:
            lockfile.parent.mkdir(parents=True, exist_ok=True)
            with lockfile.open("a+b") as lock:
                lock.seek(0, os.SEEK_END)
                if lock.tell() == 0:
                    lock.write(b"\0")
                    lock.flush()
                deadline = time.monotonic() + 30
                while True:
                    try:
                        lock.seek(0)
                        if os.name == "nt":
                            import msvcrt
                            msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
                        else:
                            import fcntl
                            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                        break
                    except OSError:
                        if time.monotonic() >= deadline:
                            raise TimeoutError("Review writer lock timeout")
                        time.sleep(0.02)
                try:
                    yield
                finally:
                    lock.seek(0)
                    if os.name == "nt":
                        msvcrt.locking(lock.fileno(), msvcrt.LK_UNLCK, 1)
                    else:
                        fcntl.flock(lock.fileno(), fcntl.LOCK_UN)

    def identity(self):
        return provenance.server_identity(self.root, self.server_script)

    def load(self):
        data = yaml.safe_load(self.progress.read_text(encoding="utf-8-sig")) if self.progress.exists() else {"schema_version": 1, "events": []}
        if not isinstance(data, dict) or data.get("schema_version") != 1 or not isinstance(data.get("events"), list):
            raise ValueError("Invalid progress document")
        ids = [event["event_id"] for event in data["events"]]
        if len(ids) != len(set(ids)):
            raise ValueError("Duplicate progress event IDs")
        return data

    def project(self, args):
        if args.get("expected_project_root") is not None:
            value = Path(args["expected_project_root"])
            if not value.is_absolute() or value.resolve() != self.root:
                raise ValueError("Project root mismatch")

    def evidence(self, values):
        result = []
        for value in values:
            path = provenance.project_path(value, self.root)
            if not path.is_file():
                raise ValueError("Evidence must be an existing project-local file: " + value)
            result.append({"path": path.relative_to(self.root).as_posix(), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
        return result

    def revision(self, revision):
        if not re.fullmatch(r"[0-9a-f]{7,40}", revision):
            raise ValueError("Revision requires a Git commit ID")
        check = subprocess.run(["git", "cat-file", "-e", revision + "^{commit}"], cwd=self.root, stdin=subprocess.DEVNULL, capture_output=True, timeout=10)
        if check.returncode:
            raise ValueError("Revision does not identify a commit in this project")

    def publish(self, data, *, source=True):
        if source:
            atomic_write(self.progress, yaml.safe_dump(data, allow_unicode=True, sort_keys=False))
        # Script loading works for file:// without fetch/CORS and scans no report links.
        live_data = dict(data, events=[e for e in data["events"] if e.get("test_result") or e.get("development_score")])
        payload = json.dumps(live_data, ensure_ascii=False).replace("<", "\\u003c").replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")
        atomic_write(self.live, "window.MAINLINE_PROGRESS=" + payload + ";\n" + test_results.SCENE_LIVE_BOOTSTRAP)

    def _progress(self, args, data, *, persist=True):
        request = dict(args)
        request.pop("expected_project_root", None)
        event_id = request.get("event_id") or "event-" + digest(request)[:32]
        fingerprint = digest(request)
        previous = next((event for event in data["events"] if event["event_id"] == event_id), None)
        if previous:
            if previous.get("request_sha256") != fingerprint:
                raise ValueError("Immutable event ID already has different content")
            if persist:
                self.publish(data, source=False)
            return {"event": previous, "duplicate": True, "event_count": len(data["events"])}
        for key in ("work_id", "segment_id"):
            if not re.fullmatch(ID, args[key]):
                raise ValueError("Invalid " + key)
        plan = json.loads((self.root / "assets/data/test_scenarios/gameplay_review_plan.json").read_text(encoding="utf-8-sig"))
        if args["segment_id"] not in {row["id"] for row in plan["scenes"]} | {"project"}:
            raise ValueError("Unknown mainline segment (use project for shared infrastructure)")
        self.revision(args["revision"])
        references = args.get("related_event_ids", [])
        work = [event for event in data["events"] if event["work_id"] == args["work_id"]]
        if any(event["kind"] == "complete" for event in work):
            raise ValueError("Completed work is sealed; assign a new work_id")
        if any(event["segment_id"] != args["segment_id"] for event in work):
            raise ValueError("A work_id belongs to one segment")
        known = {event["event_id"]: event for event in work}
        if any(value not in known for value in references):
            raise ValueError("Confirmation references must identify existing events of the same work")
        if args["kind"] == "complete" and (not references or set(references) != set(known)):
            raise ValueError("Complete must confirm every existing change/check event for this work")
        if args["kind"] != "complete" and references:
            raise ValueError("Only complete events carry confirmation references")
        evidence = self.evidence(args["evidence"])
        event = {key: args[key] for key in ("work_id", "segment_id", "kind", "summary", "result", "revision")}
        event.update(event_id=event_id, at=datetime.now().astimezone().isoformat(timespec="microseconds"),
                     evidence=[item["path"] for item in evidence], evidence_sha256=evidence,
                     related_event_ids=references, request_sha256=fingerprint, server_identity=self.identity())
        data["events"].append(event)
        if persist:
            self.publish(data)
        return {"event": event, "duplicate": False, "event_count": len(data["events"])}

    def progress_append(self, **args):
        self.project(args)
        with self.locked():
            return self._progress(args, self.load())

    def add_score(self, trajectory_id, category, score, rationale="", evidence=None, expected_project_root=None):
        """Append a development score to the same live, project-bound event ledger."""
        self.project({"expected_project_root": expected_project_root})
        plan = json.loads((self.root / "assets/data/test_scenarios/gameplay_review_plan.json").read_text(encoding="utf-8-sig"))
        if trajectory_id not in {scene["id"] for scene in plan["scenes"]}:
            raise ValueError("Unknown mainline score trajectory")
        if category not in SCORE_CATEGORIES:
            raise ValueError("Unknown score category")
        if isinstance(score, bool) or not isinstance(score, (int, float)) or not math.isfinite(score) or not 0 <= score <= 10:
            raise ValueError("Score must be a finite number from 0 to 10")
        if not isinstance(rationale, str) or len(rationale) > 8000:
            raise ValueError("Invalid score rationale")
        revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=self.root,
                                           stdin=subprocess.DEVNULL, text=True, timeout=10).strip()
        request = dict(trajectory_id=trajectory_id, category=category, score=score, rationale=rationale, evidence=evidence or [], revision=revision)
        event_args = dict(work_id="score-" + digest(request)[:32], segment_id=trajectory_id,
                          kind="check", summary="Development score: " + category,
                          result=rationale or "No rationale supplied", revision=revision, evidence=evidence or [])
        with self.locked():
            data = self.load()
            result = self._progress(event_args, data, persist=False)
            if not result["duplicate"]:
                result["event"]["development_score"] = dict(category=category, score=score,
                                                               rationale=rationale, acceptance_eligible=False)
            self.publish(data)
            return result

    def add_scores(self, trajectory_id, test_id, scores, reasons, evidence, expected_project_root=None):
        """Record all seven dimensions of one test in a single immutable event."""
        self.project({"expected_project_root": expected_project_root})
        plan = json.loads((self.root / "assets/data/test_scenarios/gameplay_review_plan.json").read_text(encoding="utf-8-sig"))
        if trajectory_id not in {scene["id"] for scene in plan["scenes"]}:
            raise ValueError("Unknown mainline score trajectory")
        if not isinstance(test_id, str) or not re.fullmatch(ID, test_id):
            raise ValueError("Invalid test_id")
        if not isinstance(scores, dict) or set(scores) != set(SCORE_CATEGORIES):
            raise ValueError("Scores must include exactly the seven categories")
        if not isinstance(reasons, dict) or set(reasons) != set(SCORE_CATEGORIES):
            raise ValueError("Reasons must include exactly the seven categories")
        for category in SCORE_CATEGORIES:
            value, reason = scores[category], reasons[category]
            if value is not None and (isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not 0 <= value <= 10):
                raise ValueError("Scores must be finite numbers from 0 to 10 or null")
            if not isinstance(reason, str) or not reason.strip() or len(reason) > 8000:
                raise ValueError("Each score or missing measurement requires a reason")
        if not isinstance(evidence, list) or any(not isinstance(item, str) for item in evidence) or len(evidence) != len(set(evidence)):
            raise ValueError("Evidence must be a list of unique paths")
        request = dict(trajectory_id=trajectory_id, test_id=test_id, scores=scores, reasons=reasons, evidence=evidence)
        fingerprint = digest(request)
        with self.locked():
            data = self.load()
            previous = next((event for event in data["events"] if event.get("test_result", {}).get("test_id") == test_id), None)
            if previous:
                if previous.get("test_request_sha256") != fingerprint:
                    raise ValueError("Test ID already has different content")
                self.publish(data, source=False)
                return {"event": previous, "duplicate": True, "event_count": len(data["events"])}
            revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=self.root,
                                               stdin=subprocess.DEVNULL, text=True, timeout=10).strip()
            event_args = dict(work_id="test-" + digest(test_id)[:32], segment_id=trajectory_id,
                              kind="check", summary="Test scores: " + test_id,
                              result="Seven dimensions recorded", revision=revision, evidence=evidence)
            result = self._progress(event_args, data, persist=False)
            result["event"]["test_result"] = dict(test_id=test_id, scores=scores, reasons=reasons)
            result["event"]["test_request_sha256"] = fingerprint
            self.publish(data)
            return result

    def see_score(self, trajectory_id, expected_project_root=None):
        self.project({"expected_project_root": expected_project_root})
        if not re.fullmatch(ID, trajectory_id):
            raise ValueError("Invalid trajectory_id")
        with self.locked():
            events = self.load()["events"]
            scores = {e["development_score"]["category"]: e for e in events
                      if e.get("segment_id") == trajectory_id and isinstance(e.get("development_score"), dict)}
            latest = next((e for e in reversed(events) if e.get("segment_id") == trajectory_id
                           and isinstance(e.get("test_result"), dict)), None)
        return {"trajectory_id": trajectory_id, "acceptance_eligible": False, "scores": scores,
                "latest_test": latest}

    def review_append(self, **args):
        self.project(args)
        record = args["record"]
        with self.locked():
            if record.get("synthetic_test_fixture") and not self.testing:
                raise ValueError("Synthetic test records are restricted to test sandboxes")
            # Keep the existing seven-score / independent Terra / real title-new-game gate.
            mainline_reviews.validate(record, self.root)
            self.revision(record["revision"])
            on = json.loads(mainline_reviews.evidence_path(self.root, record["source"]["on_receipt"]).read_text(encoding="utf-8-sig"))
            identity = on["data"]["source_identity"]
            if on.get("synthetic_test_fixture") and not self.testing:
                raise ValueError("Synthetic receipt is restricted to test sandboxes")
            pid = identity.get("process_id")
            if isinstance(pid, bool) or not isinstance(pid, int) or pid <= 0:
                raise ValueError("Original host PID must be a positive process identifier")
            if on["data"].get("acceptance_eligible") is False or on["data"].get("snapshot_path"):
                raise ValueError("Development fixture evidence cannot enter mainline reviews")
            if record.get("supersedes"):
                original_path = self.reviews / (record["supersedes"] + ".json")
                if not re.fullmatch(ID, record["supersedes"]) or not original_path.is_file():
                    raise ValueError("Superseded review must exist")
                original = json.loads(original_path.read_text(encoding="utf-8"))
                if any(original[key] != record[key] for key in ("revision", "segment_id")):
                    raise ValueError("Audit must preserve original revision and segment")
            destination = self.reviews / (record["id"] + ".json")
            duplicate = destination.exists()
            if duplicate and json.loads(destination.read_text(encoding="utf-8-sig")) != record:
                raise ValueError("Immutable review ID already has different content")
            event_args = {"event_id": "review-" + digest(record["id"])[:32], "work_id": args["work_id"],
                          "segment_id": record["segment_id"], "kind": "check", "summary": args["summary"],
                          "result": "Terra review " + record["id"] + ": " + record["status"],
                          "revision": record["revision"], "evidence": [record["report"], record["source"]["on_receipt"], record["source"]["start_receipt"]] + [image["path"] for image in record["images"]]}
            data = self.load()
            # Prepare all event validation in memory before publishing either resource.
            progress = self._progress(event_args, data, persist=False)
            if not duplicate:
                atomic_write(destination, json.dumps(record, ensure_ascii=False, indent=2) + "\n", exclusive=True)
            self.publish(data)
            result = {"review_path": str(destination), "duplicate": duplicate, **progress}
        # Release the progress lock before the full exporter; ordinary writers stay responsive.
        result["render"] = self._review_render(record)
        return result

    def semantic_append(self, **args):
        self.project(args)
        record = args['record']
        if record.get('synthetic_test_fixture') and not self.testing:
            raise ValueError('Synthetic semantic fixtures are restricted to test sandboxes')
        if not re.fullmatch(ID, record['id']):
            raise ValueError('Invalid comparison ID')
        validated = visual_semantic_reviews.validate(record, self.root)
        self.revision(record['revision'])
        files = [record[k] for k in ('observations','source_map','input_manifest')]
        files += [s['path'] for c in record['comparisons'] for s in c['truth_sources']]
        files += [f[k] for f in validated['frames'].values() for k in ('original','masked')]
        evidence = self.evidence(list(dict.fromkeys(files)))
        destination = self.base / visual_semantic_reviews.DIRECTORY / (record['id']+'.json')
        with self.locked():
            duplicate = destination.exists()
            if duplicate:
                original = json.loads(destination.read_text(encoding='utf-8'))
                if original['record'] != record or original['evidence_sha256'] != evidence:
                    raise ValueError('Immutable semantic ID already has different content/evidence')
            event_args = dict(work_id=args['work_id'], segment_id=record['segment_id'],kind='check',
                summary=args['summary'], result=record['conclusion'],revision=record['revision'],
                evidence=[record['observations'],record['source_map'],record['input_manifest']],
                event_id='semantic-'+digest(record['id'])[:32])
            data=self.load()
            progress=self._progress(event_args,data,persist=False)
            if not duplicate:
                atomic_write(destination,json.dumps(dict(record=record,evidence_sha256=evidence,
                    appended_at=datetime.now().astimezone().isoformat(),server_identity=self.identity()),
                    ensure_ascii=False,indent=2)+'\n',exclusive=True)
            self.publish(data)
        return dict(record_path=str(destination),record_duplicate=duplicate,**progress)

    def _review_render(self, record):
        if self.testing:
            return {"status": "skipped_test_sandbox", "full_render": False}
        marker = provenance.project_path(self.base / ".runtime/review-export" / ("review-" + record["id"] + ".rendered.json"), self.root)
        fingerprint = digest(record)
        with self.locked(render=True):
            if marker.is_file():
                previous = json.loads(marker.read_text(encoding="utf-8"))
                if previous.get("review_sha256") != fingerprint:
                    raise ValueError("Rendered review marker conflicts with immutable review")
                return dict(previous, duplicate=True)
            rendered = self._render()
            receipt = {"status": "complete", "full_render": True, "review_id": record["id"],
                       "review_sha256": fingerprint, "at": datetime.now().astimezone().isoformat(),
                       "server_identity": self.identity(), "exporter": rendered}
            atomic_write(marker, json.dumps(receipt, ensure_ascii=False, indent=2) + "\n")
            return dict(receipt, duplicate=False)

    def _render(self):
        if self.testing:
            raise ValueError("Full rendering is disabled for test sandboxes")
        result = subprocess.run([sys.executable, str(self.root / "tools/testing/export_review_site.py")], cwd=self.root,
                                stdin=subprocess.DEVNULL, capture_output=True, encoding="utf-8", errors="replace", timeout=180)
        if result.returncode:
            raise RuntimeError("Review site renderer failed: " + result.stderr[-3000:])
        with self.locked():
            self.publish(self.load(), source=False)
        return {"exit_code": 0, "output": result.stdout[-4000:]}

    def flush(self, **args):
        self.project(args)
        full = args.get("full_render", False)
        if full and self.testing:
            raise ValueError("Full rendering is disabled for test sandboxes")
        with self.locked():
            data = self.load()
            self.publish(data)
        if full:
            with self.locked(render=True):
                self._render()
            data = self.load()
        return {"event_count": len(data["events"]), "progress_path": str(self.progress), "live_script": str(self.live),
                "full_render": full, "server_identity": self.identity()}
