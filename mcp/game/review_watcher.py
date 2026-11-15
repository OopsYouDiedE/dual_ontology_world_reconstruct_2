"""Narrow adapter for the optional local review-site refresh service."""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REVIEW_TOOLS = ROOT / "tools/testing"


def ensure_started():
    """Start the existing watcher without exposing review tooling to runtime.py."""
    path = str(REVIEW_TOOLS)
    if path not in sys.path:
        sys.path.insert(0, path)
    from review_refresh import start_review_watcher

    start_review_watcher()
