"""Real MCP protocol integration; synthetic review fixtures stay in .runtime only."""
from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
import copy
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid
from unittest.mock import patch

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
import yaml

from core import ROOT, Store, atomic_write


async def run():
    sandbox = ROOT / ".runtime/review-tests" / ("run-" + uuid.uuid4().hex)
    sandbox.mkdir(parents=True)
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    results = []
    metadata = {}

    @asynccontextmanager
    async def connection():
        params = StdioServerParameters(command=sys.executable,
                                      args=[str(Path(__file__).with_name("server.py")), "--expected-project-root", str(ROOT), "--test-sandbox", str(sandbox)], cwd=str(ROOT))
        async with stdio_client(params) as streams:
            async with ClientSession(*streams) as session:
                init = await session.initialize()
                listing = await session.list_tools()
                metadata.update(protocol_version=init.protocolVersion, server=init.serverInfo.model_dump(), tools=[t.name for t in listing.tools])
                assert set(metadata["tools"]) == {"progress_append", "review_append", "semantic_append", "flush", "render"}
                yield session

    async def call(session, name, args, *, error=False, label):
        result = await session.call_tool(name, args)
        assert bool(result.isError) == error, (label, result)
        results.append({"check": label, "passed": True, "expected_error": error,
                        "message": result.content[0].text[:500] if error else "ok"})
        return result.structuredContent

    base = {"work_id": "protocol-work", "segment_id": "project", "kind": "change", "summary": "Synthetic protocol fixture change", "result": "test-only", "revision": revision, "evidence": ["mcp/review/server.py"]}
    async with connection() as session:
        first = await call(session, "progress_append", base, label="initialize/list/append")
        event = first["event"]
        pid = event["server_identity"]["server_pid"]
        assert isinstance(pid, int) and pid != os.getpid()
        assert Path(event["server_identity"]["project_root"]).resolve() == ROOT
        # Read process identity from the OS, independently of the MCP response.
        if os.name == "nt":
            command = "Get-CimInstance Win32_Process -Filter 'ProcessId = " + str(pid) + "' | Select-Object ExecutablePath,CommandLine | ConvertTo-Json -Compress"
            process = json.loads(subprocess.check_output(["powershell", "-NoProfile", "-Command", command], stdin=subprocess.DEVNULL, text=True))
            executable, commandline = process["ExecutablePath"], process["CommandLine"]
        else:
            executable = os.readlink("/proc/" + str(pid) + "/exe")
            commandline = Path("/proc/" + str(pid) + "/cmdline").read_text().replace("\0", " ")
        assert Path(executable).resolve() in {Path(sys.executable).resolve(), Path(sys._base_executable).resolve()}
        assert str(Path(__file__).with_name("server.py")) in commandline
        metadata["os_verified_server"] = {"pid": pid, "executable": executable, "command": commandline}
        retry = await call(session, "progress_append", base, label="identical retry deduplicated")
        assert retry["duplicate"] and retry["event_count"] == 1
        changed = dict(base, event_id=event["event_id"], result="overwrite")
        await call(session, "progress_append", changed, error=True, label="immutable event overwrite rejected")
        await call(session, "progress_append", dict(base, work_id="cross-root", expected_project_root=str(ROOT.parent)), error=True, label="foreign project assertion rejected")
        await call(session, "progress_append", dict(base, work_id="path-escape", evidence=["../outside-evidence.txt"]), error=True, label="path traversal rejected")
        await call(session, "progress_append", dict(base, work_id="missing-file", evidence=[".runtime/absent-review-evidence.txt"]), error=True, label="missing evidence rejected")
        await call(session, "progress_append", dict(base, source_identity={"process_id": 1}), error=True, label="caller-supplied PID rejected")
        await call(session, "progress_append", dict(base, revision="0000000", work_id="unknown-revision"), error=True, label="unknown revision rejected")
        await call(session, "progress_append", dict(base, kind="complete", related_event_ids=["unknown-event"]), error=True, label="unknown confirmation rejected")
        checked = await call(session, "progress_append", dict(base, kind="check", summary="Synthetic check"), label="check appended")
        complete = dict(base, kind="complete", summary="Synthetic completion", related_event_ids=[event["event_id"], checked["event"]["event_id"]])
        await call(session, "progress_append", dict(complete, related_event_ids=[event["event_id"]]), error=True, label="partial completion rejected")
        completed = await call(session, "progress_append", complete, label="completion confirmation appended")
        await call(session, "progress_append", dict(base, kind="change", summary="Late change"), error=True, label="completed work is sealed")
        await call(session, "progress_append", complete, label="completion retry deduplicated")
        before = hashlib.sha256((sandbox / "artifacts/acceptance/mainline_progress.yaml").read_bytes()).hexdigest()
        store = Store(test_sandbox=sandbox)
        atomic_write(store.live, "broken projection")
        await call(session, "flush", {}, label="flush repairs projection")
        data = yaml.safe_load(store.progress.read_text(encoding="utf-8"))
        assert json.loads(store.live.read_text(encoding="utf-8").split("=", 1)[1].rstrip(";\n")) == data
        assert hashlib.sha256(store.progress.read_bytes()).hexdigest() == before
        await call(session, "render", {}, error=True, label="test full render isolated from production")

        # Explicit synthetic unit fixtures test validation mechanics only, never acceptance.
        fixture = sandbox / "synthetic-review"
        fixture.mkdir()
        def save(name, value):
            path = fixture / name
            path.write_text(json.dumps(value), encoding="utf-8")
            return path.relative_to(ROOT).as_posix()
        identity = {"project_root": str(ROOT), "project_sha256": "synthetic-test-project-digest", "process_id": pid,
                    "configured_main_scene": "res://scenes/main/Boot.tscn", "launch_scene": "res://scenes/main/Boot.tscn", "executable_path": str(Path(sys.executable))}
        captured = {"session_id": "SYNTHETIC-TEST-ONLY", "source_identity": identity}
        on = save("on.json", {"tool": "on", "data": captured, "synthetic_test_fixture": True})
        start = save("start.json", {"tool": "step", "data": dict(captured, room="R05", day=1), "synthetic_test_fixture": True})
        image = fixture / "image.png"
        image.write_bytes(b"SYNTHETIC NON-IMAGE FIXTURE; NOT ACCEPTANCE EVIDENCE")
        image_hash = hashlib.sha256(image.read_bytes()).hexdigest()
        save("image.png.json", dict(captured, image_sha256=image_hash, synthetic_test_fixture=True))
        report = save("report.json", {"synthetic_test_fixture": True, "meaning": "Validation-only fixture"})
        record = {"schema_version": 1, "synthetic_test_fixture": True, "id": "synthetic-review", "segment_id": "wake", "revision": revision, "observed_at": datetime.now().astimezone().isoformat(),
                  "reviewer": "synthetic-terra-test-fixture", "status": "incomplete", "scores": [None] * 7, "score_reasons": [""] * 7,
                  "source": {"mode": "real_mainline", "entry": "title_new_game", "session_id": captured["session_id"], "on_receipt": on, "start_receipt": start},
                  "report": report, "images": [{"path": image.relative_to(ROOT).as_posix(), "sha256": image_hash}]}
        review_args = {"work_id": "synthetic-review-work", "summary": "Synthetic validator test", "record": record}
        await call(session, "review_append", dict(review_args, record=dict(record, reviewer="sol")), error=True, label="independent Terra gate preserved")
        await call(session, "review_append", dict(review_args, record=dict(record, source=dict(record["source"], mode="fixture"))), error=True, label="real-mainline gate preserved")
        await call(session, "review_append", dict(review_args, record=dict(record, scores=[8] * 7)), error=True, label="per-score reasons preserved")
        bad_start = copy.deepcopy(dict(captured, room="R05", day=1))
        bad_start["source_identity"]["process_id"] += 1
        save("start.json", {"tool": "step", "data": bad_start})
        await call(session, "review_append", review_args, error=True, label="mismatched host PID rejected")
        save("start.json", {"tool": "step", "data": dict(captured, room="R05", day=1)})
        foreign = copy.deepcopy(captured)
        foreign["source_identity"]["project_root"] = str(ROOT.parent)
        save("on.json", {"tool": "on", "data": foreign})
        await call(session, "review_append", review_args, error=True, label="foreign review project rejected before access")
        save("on.json", {"tool": "on", "data": captured})
        await call(session, "review_append", dict(review_args, record=dict(record, images=[{"path": image.relative_to(ROOT).as_posix(), "sha256": "0" * 64}])), error=True, label="image SHA256 gate preserved")
        # Production services must never accept an explicitly synthetic fixture.
        # The test sandbox alone enables the positive fixture path.
        accepted = await call(session, "review_append", review_args, label="sandbox review commit and check event")
        assert accepted["render"] == {"status": "skipped_test_sandbox", "full_render": False}
        try:
            Store().review_append(**review_args)
            raise AssertionError("Production store accepted synthetic review")
        except ValueError as error:
            assert "Synthetic" in str(error)
        results.append({"check": "production refuses synthetic review fixtures", "passed": True})
        review_file = Path(accepted["review_path"])
        assert review_file.is_relative_to(sandbox)
        original = review_file.read_bytes()
        await call(session, "review_append", review_args, label="immutable review retry deduplicated")
        await call(session, "review_append", dict(review_args, record=dict(record, status="blocked")), error=True, label="immutable review overwrite rejected")
        assert review_file.read_bytes() == original
        assert not (ROOT / "artifacts/acceptance/gameplay-reviews/synthetic-review.json").exists()

    # Concurrent independent MCP server processes share the same Windows file lock.
    async def concurrent(index):
        async with connection() as session:
            return await call(session, "progress_append", dict(base, work_id="concurrent-" + str(index), summary="Concurrent append " + str(index)), label="concurrent writer " + str(index))
    await asyncio.gather(*(concurrent(index) for index in range(4)))
    store = Store(test_sandbox=sandbox)
    data = store.load()
    assert len(data["events"]) == 8
    assert len({event["event_id"] for event in data["events"]}) == 8
    assert [row["event_id"] for row in data["events"][:3]] == [event["event_id"], checked["event"]["event_id"], completed["event"]["event_id"]]
    results.append({"check": "four-process writes retain every event and original ordering", "passed": True})
    # Exercise production rendering control flow with the actual exporter subprocess
    # mocked. The store's paths remain in the test sandbox throughout this check.
    plumbing = Store(test_sandbox=sandbox)
    plumbing.testing = False
    successful_export = subprocess.CompletedProcess([], 0, stdout='{"test_exporter":true}', stderr="")
    with patch("core.subprocess.run", return_value=successful_export) as exporter:
        rendered = plumbing._review_render({"id": "render-plumbing-fixture"})
        assert rendered["full_render"] and not rendered["duplicate"]
        same = plumbing._review_render({"id": "render-plumbing-fixture"})
        assert same["duplicate"] and exporter.call_count == 1
        assert exporter.call_args.kwargs["stdin"] == subprocess.DEVNULL
        assert str(ROOT / "tools/testing/export_review_site.py") in exporter.call_args.args[0]
    results.append({"check": "production review render invokes exporter once and deduplicates retries (mocked exporter, isolated files)", "passed": True})
    failed_export = subprocess.CompletedProcess([], 1, stdout="", stderr="synthetic exporter failure")
    with patch("core.subprocess.run", side_effect=[failed_export, successful_export]) as exporter:
        try:
            plumbing._review_render({"id": "render-retry-fixture"})
            raise AssertionError("Failed exporter accepted")
        except RuntimeError as error:
            assert "synthetic exporter failure" in str(error)
        retried = plumbing._review_render({"id": "render-retry-fixture"})
        assert retried["full_render"] and exporter.call_count == 2
    results.append({"check": "failed render leaves retryable immutable review state (mocked exporter, isolated files)", "passed": True})
    output = {"schema_version": 1, "passed": all(row["passed"] for row in results), "checks": len(results), "results": results,
              "protocol": metadata, "sandbox": str(sandbox), "event_count": len(data["events"]), "synthetic_review_fixture_only": True,
              "production_review_written": False, "production_render_plumbing_mocked": True,
              "completed_at": datetime.now().astimezone().isoformat()}
    report = sandbox / "integration-result.json"
    atomic_write(report, json.dumps(output, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"passed": output["passed"], "checks": len(results), "report": str(report), "event_count": len(data["events"])}, ensure_ascii=False))


if __name__ == "__main__":
    asyncio.run(run())
