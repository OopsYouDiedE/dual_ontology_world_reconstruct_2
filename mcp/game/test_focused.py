"""Contract regression for focused MCP runs; real middleware smoke is separate."""
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

import focused
import server


class FocusedTests(unittest.TestCase):
    def setUp(self):
        self.run = {"test_id": "0123456789abcdef", "tester": "Only Tester", "scope": "room", "target": "B-P",
                    "checks": focused.RUBRICS["room"], "status": "running", "_session": "host",
                    "acceptance_eligible": False, "steps": [dict(id="step-0001", room="B-P"),
                    dict(id="step-0002", room="R05"), dict(id="step-0003", room="B-P", error="invalid action")]}
        self.verdicts = {name: dict(outcome="pass", reason="Observed scoped result", steps=["step-0001"])
                         for name in self.run["checks"]}

    def test_scope_catalog_and_nominal_entries(self):
        catalog = focused.catalog()
        self.assertEqual(set(catalog["targets"]), {"room", "interaction", "ui", "design", "story"})
        self.assertEqual(focused.target_spec("room", "B-P")["expected_room"], "B-P")
        self.assertIsNone(focused.target_spec("ui", "title")["scenario"])
        self.assertIsNotNone(focused.target_spec("interaction", "wardrobe")["workbench"])
        self.assertIsNotNone(focused.target_spec("design", "expressions")["workbench"])
        with self.assertRaises(ValueError):
            focused.target_spec("story", "../wake")
        with self.assertRaises(ValueError):
            focused.target_spec("ui", "kitchen-evidence")

    def test_motion_requires_distinct_offsets_and_real_input(self):
        focused.validate_frames([8, 20, 40], "input_action")
        for offsets, operation in [([8], "click"), ([8, 8], "click"), ([8, 9], "click"),
                                   ([8, 121], "click"), ([8, 10], "observe"), ([True, 10], "click")]:
            with self.subTest(offsets=offsets), self.assertRaises(ValueError):
                focused.validate_frames(offsets, operation)

    def test_no_credits_for_failed_or_out_of_scope_steps(self):
        for bad in ([], ["step-0002"], ["step-0003"], ["step-9999"]):
            self.verdicts["layout"]["steps"] = bad
            with self.assertRaises(ValueError):
                focused.validate_verdicts(self.run, self.verdicts)

    def test_immutable_attributed_batch_and_retry(self):
        with patch.object(focused, "close_host", return_value=True) as close, patch.object(focused, "publish"):
            first = focused.finish_run(self.run, self.verdicts)
            second = focused.finish_run(self.run, json.loads(json.dumps(self.verdicts)))
            self.assertEqual(first, second)
            self.assertEqual(first["tester"], "Only Tester")
            self.assertEqual(first["status"], "passed")
            close.assert_called_once()
            updated = dict(self.verdicts, layout=dict(outcome="blocked", reason="sample missing"))
            with self.assertRaisesRegex(ValueError, "immutable"):
                focused.finish_run(self.run, updated)

    def test_missing_is_distinct_from_failure(self):
        self.verdicts["layout"] = dict(outcome="blocked", reason="missing evidence")
        with patch.object(focused, "close_host", return_value=True), patch.object(focused, "publish"):
            self.assertEqual(focused.finish_run(self.run, self.verdicts)["status"], "incomplete")

    def test_live_publish_never_writes_session_secrets(self):
        (focused.ROOT / ".runtime").mkdir(exist_ok=True)
        base = Path(tempfile.mkdtemp(prefix="focused-unit-", dir=focused.ROOT / ".runtime"))
        self.addCleanup(shutil.rmtree, base)
        self.run["started_at"] = "2026-11-18T00:00:00+00:00"
        self.run["tester"] = "<script>"
        with patch.object(focused, "directory", return_value=base):
            focused.publish(self.run)
            second = dict(self.run, test_id="0123456789abcdea", tester="Other", status="starting")
            focused.publish(second)
            focused.publish(dict(self.run, status="failed"))
        raw = (base / "live.js").read_text(encoding="utf-8")
        self.assertNotIn("<script>", raw)
        data = json.loads(raw.removeprefix("window.FOCUSED_TESTS=").strip().removesuffix(";"))
        self.assertEqual(len(data), 2)
        record = next(item for item in data if item["test_id"] == self.run["test_id"])
        self.assertEqual(record["status"], "failed")
        self.assertNotIn("_session", record)

    def test_day_one_route_requires_chapter_end_and_day_two_in_order(self):
        target = focused.DAY_ONE_TARGET
        self.assertTrue(focused.catalog()["targets"]["story"][target]["ready"])
        self.assertIsNone(focused.target_spec("story", target)["scenario"])
        checks = focused.DAY_ONE_RUBRIC
        run = dict(self.run, scope="story", target=target, checks=checks,
                   steps=[dict(id="step-0001"), dict(id="step-0002")])
        verdicts = {name: dict(outcome="pass", reason="Observed", steps=["step-0001", "step-0002"])
                    for name in checks}
        with self.assertRaisesRegex(ValueError, "Chapter 1 complete"):
            focused.validate_verdicts(run, verdicts)
        end = dict(step="step-0001", state=dict(chapter=1, day=1, chapter_complete=True, room="R05"))
        day_two = dict(step="step-0002", state=dict(chapter=2, day=2, chapter_complete=False, room="R05"))
        for trail in ([day_two, end], [end], [day_two]):
            with self.assertRaisesRegex(ValueError, "Chapter 1 complete"):
                focused.validate_verdicts(dict(run, route=trail), verdicts)
        focused.validate_verdicts(dict(run, route=[end, day_two]), verdicts)
        with self.assertRaisesRegex(ValueError, "uninterrupted"):
            focused.validate_verdicts(dict(run, route=[end, day_two], route_interrupted=True), verdicts)
        verdicts["completion"] = dict(outcome="not_applicable", reason="not played")
        with self.assertRaisesRegex(ValueError, "Completion is required"):
            focused.validate_verdicts(run, verdicts)
        verdicts["completion"] = dict(outcome="blocked", reason="not played")
        focused.validate_verdicts(run, verdicts)

    def test_day_one_uses_production_title_button(self):
        run = dict(self.run, scope="story", target=focused.DAY_ONE_TARGET)
        with self.assertRaisesRegex(ValueError, "visible New Game"):
            focused.step_run(run, {"operation": {"type": "start"}})
        run["route_interrupted"] = True
        with self.assertRaisesRegex(ValueError, "route has ended"):
            focused.step_run(run, {"operation": {"type": "click", "x": 20, "y": 20}})

    def test_legacy_input_cannot_address_focused_ownership_token(self):
        with self.assertRaisesRegex(ValueError, "Unknown focused session"):
            focused.execute("focus_finish", {"session_id": "some-other-connection"})
        self.assertFalse(server.FOCUS_TOOLS[-1].inputSchema["additionalProperties"])
        self.assertNotIn("tester", server.FOCUS_TOOLS[-1].inputSchema["properties"])


if __name__ == "__main__":
    unittest.main()
