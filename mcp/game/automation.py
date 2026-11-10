"""Deadline-bounded engine-AI runs owned entirely by one automatic MCP call."""
import base64
from datetime import datetime, timezone
from pathlib import Path
import json
import os
import secrets
import threading
import time

import runtime

RUNS = runtime.ROOT / ".runtime/runs"


def publish(pending, path):
    # Windows readers/virus scanners can briefly hold the destination without
    # delete sharing. Keep the last complete observation until replacement works.
    for attempt in range(11):
        try:
            pending.replace(path)
            return
        except PermissionError:
            if attempt == 10:
                raise
            time.sleep(0.02 * (attempt + 1))


def save(path, value):
    pending = path.with_suffix(path.suffix + ".tmp")
    pending.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
    publish(pending, path)


def save_yaml(path, value):
    # JSON-encoded values are a YAML subset. Keys are fixed by this module;
    # strings and nested values need no hand-written escaping or dependency.
    pending = path.with_suffix(path.suffix + ".tmp")
    pending.write_text("".join(key + ": " + json.dumps(item, ensure_ascii=False, separators=(",", ":")) + "\n"
                               for key, item in value.items()), encoding="utf-8")
    publish(pending, path)


def persist_report(report):
    path = Path(report["report_path"])
    if report["backend"] != "cli":
        save(path, report)
        return
    # The JSON MCP result stays machine readable; disk keeps only the small
    # start/end cut. Full screens, plans and performance snapshots are omitted.
    keys = ("run_id", "backend", "seed", "viewer", "status", "detail", "deadline",
            "created_epoch", "started_epoch", "finished_epoch", "host_stopped", "graceful_exit",
            "content", "initial_state", "final_state", "final_state_source", "audit_persistence",
            "observations", "completed_actions", "total_action_receipts", "recoverable_cancellations", "rejected_action_receipts", "blocked_action_attempts", "unexpected_action_failures", "flushed_execution_receipts",
            "in_budget_execution_receipts", "out_of_budget_execution_receipts",
            "receipt_outcomes", "receipt_categories", "progress", "receipt_path", "transcript_path", "detail_log_path", "receipt_read_detail", "last_fault_attempt", "close_error", "coverage", "performance")
    value = {"format": "dv-cli-story-v1", "controller": "engine-ai", "execution": "formal-model",
             "story_scope": "All actual action completions; narrative text is visible to the named viewer.",
             "game_time_unit": "minute"}
    value.update({key: report[key] for key in keys if key in report})
    save_yaml(path, value)


def execution_receipts(path, report):
    """Read only complete blocks written/flushed by the production CLI host."""
    required = {"receipt_index", "version", "chapter", "start_time", "duration", "actor", "action", "outcome"}
    fault_required = {"kind", "completion_confirmed", "failed_epoch", "version_before", "game_time",
                      "actor", "action", "action_event", "exception_type", "message"}
    record = {}
    with path.open(encoding="utf-8") as receipts:
        for line in receipts:
            if not line.endswith("\n"):
                report["receipt_read_detail"] = "Incomplete final YAML execution receipt excluded after host stop."
                return
            if not line.strip():
                if record:
                    if record.get("kind") == "fault":
                        if not fault_required.issubset(record) or record["completion_confirmed"] is not False:
                            report["receipt_read_detail"] = "Incomplete YAML fault attempt excluded after host stop."
                            return
                        report["last_fault_attempt"] = record
                        record = {}
                        continue
                    if not required.issubset(record):
                        report["receipt_read_detail"] = "Incomplete YAML execution receipt excluded after host stop."
                        return
                    yield record
                    record = {}
                continue
            if line.startswith("#"): continue
            if line.startswith(("- receipt_index:", "- kind:")) and not record:
                text = line[2:]
            elif line.startswith("  ") and record:
                text = line[2:]
            else:
                report["receipt_read_detail"] = "Invalid YAML execution receipt excluded after host stop."
                return
            key, separator, encoded = text.partition(": ")
            try:
                if not separator or key in record: raise ValueError("Invalid field")
                record[key] = json.loads(encoded)
            except ValueError:
                report["receipt_read_detail"] = "Partial YAML execution receipt excluded after host stop."
                return
    if record:
        report["receipt_read_detail"] = "Unterminated final YAML execution receipt excluded after host stop."


def tool(backend, arguments):
    if "deadline" in arguments and "duration_seconds" in arguments:
        raise ValueError("Choose deadline OR duration_seconds")
    created = time.time()
    if arguments.get("deadline"):
        target = datetime.fromisoformat(arguments["deadline"].replace("Z", "+00:00"))
        if target.tzinfo is None:
            raise ValueError("deadline must include a timezone, for example +08:00 or Z")
        deadline = target.timestamp()
    else:
        deadline = created + arguments.get("duration_seconds", 60)
    if not 0 < deadline - created <= 86400:
        raise ValueError("Deadline must be in the next 24 hours")
    identity = backend + "-" + secrets.token_hex(12)
    directory = RUNS / identity
    directory.mkdir(parents=True)
    spec = {"run_id": identity, "backend": backend, "created_epoch": created,
            "deadline_epoch": deadline, "seed": arguments.get("seed", 1),
            "viewer": arguments.get("viewer", "detective")}
    if arguments.get("content_path"): spec["content_path"] = arguments["content_path"]
    if backend != "cli": save(directory / "request.json", spec)
    report = dict(spec, status="queued", deadline=datetime.fromtimestamp(deadline, timezone.utc).isoformat(),
                  report_path=str(directory / ("report.yaml" if backend == "cli" else "report.json")), agent_required=False,
                  clock_policy="wall-clock-including-build-and-startup", observation=None,
                  observation_policy="last-successfully-received-before-stop", observations=0,
                  completed_actions=0 if backend == "cli" else None)
    if backend == "cli":
        report.update(advance_batch_steps=32, receipt_path=str(directory / "actions.yaml"),
                      receipt_format="dv-cli-actions-yaml-v1",
                      observation_policy="last-successfully-received-batch-observation-before-stop")
    persist_report(report)
    # One MCP call owns the full run. No independent Agent, second call or
    # detached process is required to advance actions or enforce the cutoff.
    run(spec, report)
    return report


def run(spec, report):
    directory = Path(report["report_path"]).parent
    report.update(status="running", started_epoch=time.time(), worker_pid=os.getpid())
    persist_report(report)
    deadline = time.monotonic() + max(0, spec["deadline_epoch"] - time.time())
    endpoint = None
    timer = None

    def record(observation):
        if spec["backend"] == "cli" and time.monotonic() > deadline:
            return  # A late batch cannot extend the in-budget observation cut.
        observation = dict(observation)
        png = observation.pop("image_base64", None)
        if png:
            pending = directory / "latest.png.tmp"
            pending.write_bytes(base64.b64decode(png))
            publish(pending, directory / "latest.png")
            report["screenshot_path"] = str(directory / "latest.png")
            report["screenshot_updated_epoch"] = time.time()
        report["observation"] = observation
        report["observations"] += 1
        if spec["backend"] == "cli":
            report["audit_persistence"] = observation.get("audit_persistence")
            totals = observation.get("receipt_totals")
            if isinstance(totals, dict):
                report["completed_actions"] = int(totals["successful"])
                report["total_action_receipts"] = int(totals["total"])
                report["recoverable_cancellations"] = int(totals["recoverable_cancellations"])
                report["rejected_action_receipts"] = int(totals["rejected"])
                report["blocked_action_attempts"] = int(totals.get("blocked",0))
                report["unexpected_action_failures"] = int(totals["unexpected_failures"])
            else:
                report["completed_actions"] += int(observation.get("completed", 0))
            report["transcript_path"] = observation.get("transcript_path")
            report["detail_log_path"] = observation.get("detail_log_path")
            state = observation.get("runtime", observation.get("status", {}))
            report.setdefault("initial_state", state)
            report["final_state"] = state
            report["final_state_source"] = "last-successfully-received-batch-observation"
            report["content"] = {key: observation.get("content", {}).get(key) for key in ("hash", "schema")}
            if isinstance(observation.get("performance"), dict):
                # These counters are cumulative. Replace the last cut; summing
                # successive observations would count earlier work again.
                report["performance"] = dict(observation["performance"],
                                             state_version=observation.get("version"),
                                             receipts_flushed=observation.get("receipts_flushed"))
        else:
            audit = (observation.get("state") or {}).get("audit_status") or {}
            if "successful_count" in audit:
                report["completed_actions"] = int(audit["successful_count"])
                report["total_action_receipts"] = int(audit["receipt_count"])
                report["recoverable_cancellations"] = int(audit["recoverable_cancellations"])
                report["rejected_action_receipts"] = int(audit["rejected_count"])
                report["blocked_action_attempts"] = int(audit.get("blocked_attempt_count",0))
                report["unexpected_action_failures"] = int(audit["unexpected_failure_count"])
        report["updated_epoch"] = time.time()
        persist_report(report)

    try:
        options = {"mode": spec["backend"] + "_auto", "controller": "ai", "seed": spec["seed"], "viewer": spec["viewer"]}
        if spec["backend"] == "cli": options["receipt_path"] = report["receipt_path"]
        if spec.get("content_path"): options["content_path"] = spec["content_path"]
        observation = runtime.start(options, deadline=deadline)
        endpoint = runtime.SESSIONS[observation["session_id"]]
        timer = threading.Timer(max(0, deadline - time.monotonic()), endpoint.stop)
        timer.daemon = True
        timer.start()
        record(observation)
        if spec["backend"] == "godot":
            observation = endpoint.request({"type": "start", "wait_ms": 200, "capture_image": False})
            record(observation)
        next_image = time.monotonic() + 5
        while True:
            runtime.remaining(deadline, 1)
            if observation.get("faulted") or observation.get("host_errors"):
                raise RuntimeError("Live host reported a fault; see the last observation")
            if spec["backend"] == "cli":
                if not observation.get("active", True):
                    acceptance = observation.get("acceptance", {})
                    if acceptance.get("passed") is False:
                        raise RuntimeError("Campaign stopped without satisfying its authored completion and acceptance conditions")
                    report["status"] = "completed"
                    break
                if observation.get("status", {}).get("status") == "awaiting_input":
                    raise RuntimeError("Engine-AI run unexpectedly requested a player decision")
                observation = endpoint.request({"type": "advance", "steps": report["advance_batch_steps"]},
                                               timeout=runtime.remaining(deadline, 86400))
            else:
                if observation.get("state", {}).get("active") is False:
                    if observation.get("state", {}).get("campaign_completed") is not True:
                        raise RuntimeError("Godot stopped before the authored five-day completion conditions were met")
                    report["status"] = "completed"
                    break
                # Advance only visible dialogue through the normal input path.
                # Campaign choices remain owned by the real engine AI.
                operation = {"type": "input_action", "action": "dialogue_continue", "frames": 1} \
                    if observation.get("reading") else {"type": "observe"}
                operation.update(wait_ms=200, capture_image=time.monotonic() >= next_image)
                if operation["capture_image"]: next_image = time.monotonic() + 5
                observation = endpoint.request(operation)
            record(observation)
    except Exception as error:
        report["status"] = "deadline_reached" if time.monotonic() >= deadline else "failed"
        report["detail"] = "Configured wall-clock deadline reached; live host stopped." \
            if report["status"] == "deadline_reached" else str(error)
    finally:
        if timer: timer.cancel()
        if endpoint:
            report["graceful_exit"] = False
            if time.monotonic() < deadline and not endpoint.closed:
                try:
                    # The close reply precedes Godot's tree teardown. Reuse the
                    # formal input lifecycle, which waits for the real process
                    # exit before releasing it, so its audit footer can flush.
                    identity = next(key for key, value in runtime.SESSIONS.items() if value is endpoint)
                    closed = runtime.execute("close", {"session_id": identity})
                    report["graceful_exit"] = closed.get("graceful_exit", False)
                except Exception as error: report["close_error"] = str(error)
            endpoint.stop()
            if spec["backend"] != "cli": report["host_log"] = list(endpoint.logs)
            for key, value in list(runtime.SESSIONS.items()):
                if value is endpoint: runtime.SESSIONS.pop(key, None)
        report.update(finished_epoch=time.time(), agent_required=False,
                      host_stopped=endpoint is None or endpoint.process.poll() is not None)
        if spec["backend"] == "cli":
            receipt_path = Path(report["receipt_path"])
            count, in_budget, latest, outcomes, categories = 0, 0, None, {}, {}
            receipt_state = dict(report.get("initial_state", {}))
            summary = receipt_state.get("chapter_summary", False)
            chapter_transitions = []
            previous_chapter = receipt_state.get("chapter")
            if receipt_path.is_file():
                for receipt in execution_receipts(receipt_path, report):
                    count += 1
                    if receipt["version"] > report.get("final_state", {}).get("version", -1):
                        continue
                    in_budget += 1
                    latest = receipt
                    if previous_chapter is not None and receipt["chapter"] != previous_chapter:
                        chapter_transitions.append({"from": previous_chapter, "to": receipt["chapter"],
                                                    "receipt_index": receipt["receipt_index"],
                                                    "version": receipt["version"]})
                    previous_chapter = receipt["chapter"]
                    summary = receipt.get("chapter_summary", summary)
                    receipt_state.update(receipt.get("run_bounds", {}))
                    receipt_state.update(receipt.get("state", {}))
                    receipt_state.update(version=receipt["version"], chapter=receipt["chapter"],
                                         game_time=receipt.get("state", {}).get("game_time", receipt["start_time"] + receipt["duration"]),
                                         chapter_summary=summary)
                    outcome = receipt.get("outcome", "unreported")
                    outcomes[outcome] = outcomes.get(outcome, 0) + 1
                    category = receipt.get("outcome_category", "unclassified")
                    categories[category] = categories.get(category, 0) + 1
            if latest and latest["version"] > report.get("final_state", {}).get("version", -1):
                report["final_state"] = receipt_state
                report["final_state_source"] = "last-in-budget-flushed-execution-receipt"
            report.update(flushed_execution_receipts=count, in_budget_execution_receipts=in_budget,
                          out_of_budget_execution_receipts=count - in_budget, last_execution_receipt=latest,
                          receipt_outcomes=outcomes, receipt_categories=categories,
                          receipt_coverage="Only complete Core action rows confirmed by an in-budget live observation are counted; timestamps are start_time plus duration in game minutes. "
                                           "completed_actions sums successful batch observations; receipts additionally cover a final interrupted batch. "
                                           "last_execution_receipt and outcome counts exclude receipts timestamped after the configured deadline.")
            report["progress"] = {
                "run_end": {"status": report["status"], "host_stopped": report["host_stopped"]},
                "chapter_progress": {"last_observed_chapter": report.get("final_state", {}).get("chapter"),
                                     "transitions": chapter_transitions,
                                     "completion_assessment": "not-assessed"},
                "key_nodes": {"assessment": "not-assessed", "chapter_summary": report.get("final_state", {}).get("chapter_summary", False)},
                "failure_branches": {"assessment": "not-assessed",
                                     "session_stop_reason": report.get("final_state", {}).get("stop_reason", "")}
            }
        else:
            # Godot's live state remains the evidence source. A stopped host is
            # not a chapter completion, and missing evidence is never a pass.
            report["progress"] = {
                "run_end": {"status": report["status"], "host_stopped": report["host_stopped"]},
                "chapter_progress": {"completion_assessment": "not-assessed"},
                "key_nodes": {"assessment": "not-assessed"},
                "failure_branches": {"assessment": "not-assessed"}
            }
        report["coverage"] = ("Only recorded live observations and flushed CLI execution receipts completed within the configured deadline; "
                              "batch observations and per-action receipt coverage are reported separately. "
                              "Narrative text is the viewer's actual presentation. The final session stop_reason and chapter_summary "
                              "must be reviewed; deadline_reached or budget-exhausted does not mean campaign passed.") if spec["backend"] == "cli" else \
                             "Only recorded live observations; deadline_reached does not mean campaign passed."
        persist_report(report)

