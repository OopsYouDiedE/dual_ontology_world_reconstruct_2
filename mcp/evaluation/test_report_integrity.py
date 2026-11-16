"""Regression tests for honest, link-safe publication of progress evidence.

All fixtures are synthetic and stay inside this project's test sandbox. They do
not create an independent player review or contribute any acceptance score.
"""
from __future__ import annotations

import hashlib
from html.parser import HTMLParser
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/testing"))
import export_review_site as site


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.hrefs = []

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            self.hrefs.append(dict(attrs).get("href"))


class HistoryEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        (ROOT / ".runtime/review-tests").mkdir(parents=True, exist_ok=True)

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="integrity-", dir=ROOT / ".runtime/review-tests")
        self.directory = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def rel(self, value: Path) -> str:
        return value.relative_to(ROOT).as_posix()

    def test_audit_distinguishes_missing_changed_and_unverified(self):
        good = self.directory / "good file.txt"
        changed = self.directory / "changed.txt"
        no_hash = self.directory / "unverified.txt"
        missing = self.directory / "missing.txt"
        good.write_text("original", encoding="utf-8")
        changed.write_text("new contents", encoding="utf-8")
        no_hash.write_text("no hash", encoding="utf-8")
        digest = hashlib.sha256(b"original").hexdigest()
        event = {"event_id": "fixture", "evidence": [self.rel(x) for x in (good, changed, no_hash, missing)],
                 "evidence_sha256": [{"path": self.rel(x), "sha256": digest} for x in (good, changed, missing)]}
        audit = site.audit_progress({"events": [event]})
        self.assertFalse(audit["complete"])
        self.assertEqual(audit["counts"], {"valid": 1, "missing": 1, "changed": 1, "unverified": 1})
        states = {x["path"]: x["status"] for x in audit["events"]["fixture"]}
        self.assertEqual(states[self.rel(good)], "valid")
        self.assertEqual(states[self.rel(changed)], "changed")
        self.assertEqual(states[self.rel(no_hash)], "unverified")
        self.assertEqual(states[self.rel(missing)], "missing")
        self.assertEqual(event["evidence"][0], self.rel(good), "audit must not mutate immutable events")
        html = site.progress_evidence(event, ROOT / "artifacts/review/index.html", audit)
        doc = Links()
        doc.feed(html)
        self.assertEqual(len(doc.hrefs), 1, "only an existing, hash-matched evidence file is linked")
        self.assertIn("good%20file.txt", doc.hrefs[0])
        self.assertIn("证据缺失", html)
        self.assertIn("内容已变化", html)
        self.assertIn("缺少校验值", html)
        self.assertIn(digest, html, "retain the expected historical digest for forensic comparison")

    def test_fresh_audit_detects_modification_after_first_export(self):
        path = self.directory / "mutable.txt"
        path.write_bytes(b"v1")
        event = {"event_id": "mutable", "evidence": [self.rel(path)],
                 "evidence_sha256": [{"path": self.rel(path), "sha256": hashlib.sha256(b"v1").hexdigest()}]}
        self.assertTrue(site.audit_progress({"events": [event]})["complete"])
        path.write_bytes(b"v2")
        self.assertEqual(site.audit_progress({"events": [event]})["counts"]["changed"], 1)

    def test_external_paths_and_escaping_symlinks_are_rejected(self):
        for value in ("../../forbidden-evidence", "https://example.invalid/file"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                site.audit_progress({"events": [{"event_id": "external", "evidence": [value]}]})
        link = self.directory / "outside"
        try:
            link.symlink_to(Path(ROOT.anchor), target_is_directory=True)
        except OSError as error:
            if getattr(error, "winerror", None) == 1314:
                self.skipTest("Windows requires symbolic-link creation privileges")
            raise
        with self.assertRaises(ValueError):
            site.audit_progress({"events": [{"event_id": "symlink", "evidence": [self.rel(link) + "/tmp/no-file"]}]})

    def test_unverified_history_prevents_overall_pass(self):
        entries = [{"status": "合格"}, {"status": "合格"}]
        self.assertTrue(site.overall_passed(entries, {"complete": True}))
        self.assertFalse(site.overall_passed(entries, {"complete": False}))
        self.assertFalse(site.overall_passed([], {"complete": True}))
        self.assertFalse(site.overall_passed([{"status": "待评"}], {"complete": True}))

    def test_markdown_extracts_normal_links_and_images(self):
        text = '[report](<relative/report.html>) ![image](<relative/a.png>) [site](https://example.invalid)'
        self.assertEqual(site.markdown_links(text), ["relative/report.html", "relative/a.png", "https://example.invalid"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
