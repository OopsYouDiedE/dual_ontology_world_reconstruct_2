"""Contract checks for project-local named survey cases."""
from pathlib import Path
import hashlib
import json
import unittest

from survey_plan import resolve_case


ROOT = Path(__file__).resolve().parents[2]
SCENARIOS = ROOT / "assets/data/test_scenarios"


class SurveyPlanTests(unittest.TestCase):
    def test_checked_in_plan_uses_resolvable_named_cases(self):
        data = json.loads((SCENARIOS / "mainline_survey.json").read_text(encoding="utf-8-sig"))
        cases = data
        self.assertTrue(cases)
        for case in cases:
            with self.subTest(case=case["id"]):
                resolved = resolve_case(case, ROOT)
                self.assertEqual(resolved["fixture"]["id"], case["id"])
                self.assertNotIn("fixture", case)
                path = ROOT / resolved["scenario_source"].removeprefix("res://")
                self.assertEqual(resolved["scenario_sha256"], hashlib.sha256(path.read_bytes()).hexdigest())
                self.assertIn("before_beat", resolved["fixture"])

    def test_mixed_input_and_cross_directory_reference_are_rejected(self):
        case = {"id": "wake-bedroom", "scenario_path": "res://assets/data/test_scenarios/segments/wake-bedroom.json"}
        with self.assertRaisesRegex(ValueError, "Choose a named scenario"):
            resolve_case({**case, "fixture": {}}, ROOT)
        with self.assertRaisesRegex(ValueError, "project segment JSON"):
            resolve_case({**case, "scenario_path": "res://assets/data/test_scenarios/mainline_survey.json"}, ROOT)
        with self.assertRaisesRegex(ValueError, "ID must match"):
            resolve_case({**case, "id": "wrong"}, ROOT)
