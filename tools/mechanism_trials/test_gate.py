import hashlib
from pathlib import Path
import tempfile
import unittest

from gate import REQUIRED_EVIDENCE, evaluate, instant


class GateTest(unittest.TestCase):
    start = "2026-11-25T05:39:04+08:00"
    deadline = "2026-11-26T01:39:04+08:00"
    rev = "f" * 40

    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        (self.root / "receipt").write_bytes(b"fixture")
        self.receipt = {"file": "receipt", "sha256": hashlib.sha256(b"fixture").hexdigest()}
        self.ledger = {"candidate": "fixture", "revision": self.rev, "generated_at": self.start}

    def at(self, time=None):
        return evaluate(self.ledger, self.root, instant(time or self.deadline))

    def report(self, agent, role="medium", outcome="undefeated", **kw):
        return {"agent": agent, "role": role, "started_at": self.start, "ended_at": "2026-11-25T05:59:04+08:00",
                "revision": self.rev, "outcome": outcome, "independent": True,
                "receipt": self.receipt, "surface": "authoritative-model", **kw}

    def test_dotnet_seventh_fractional_digit(self):
        self.assertEqual(instant("2026-11-25T06:24:42.0704538+08:00").microsecond, 70453)

    def test_passage_of_time_is_not_a_receipt(self):
        self.assertEqual(self.at("2026-11-25T13:27:09+08:00")["status"], "awaiting-window")
        self.assertEqual(self.at()["status"], "evidence-incomplete")

    def test_reproduced_redteam_clear_immediately_disqualifies(self):
        self.ledger["red_reports"] = [self.report("a", outcome="cleared")]
        self.assertEqual(self.at("2026-11-25T06:00:00+08:00")["status"], "disqualified")
        self.assertFalse(self.at()["eligible_to_send"])

    def test_time_revision_separation_and_judge(self):
        self.ledger["golden"] = {"passed_live": True, "revision": self.rev}
        self.ledger["evidence"] = {name: self.receipt for name in REQUIRED_EVIDENCE}
        self.ledger["red_reports"] = [self.report("a"), self.report("b"), self.report("c", "high")]
        self.assertEqual(self.at("2026-11-26T01:39:03+08:00")["status"], "awaiting-window")
        self.assertEqual(self.at()["status"], "eligible-for-astra")
        self.ledger["judge"] = {"revision": self.rev, "model": "gpt-6.2-astra", "passive_review": True,
                                "reviewed_at": self.deadline, "solution": "pass", "art": "fail", "receipt": self.receipt}
        self.assertEqual(self.at()["status"], "vetoed")
        self.ledger["judge"]["art"] = "pass"
        self.assertTrue(self.at()["accepted"])
        self.ledger["red_reports"][0]["revision"] = "0" * 40
        self.assertEqual(self.at()["status"], "evidence-incomplete")
        self.ledger["red_reports"].append(self.report("c"))
        self.assertEqual(self.at()["status"], "evidence-incomplete")

    def test_tampering_never_certifies_or_disqualifies(self):
        self.ledger["red_reports"] = [self.report("a", outcome="cleared")]
        (self.root / "receipt").write_bytes(b"edited")
        self.assertEqual(self.at()["status"], "evidence-incomplete")


if __name__ == "__main__":
    unittest.main()
