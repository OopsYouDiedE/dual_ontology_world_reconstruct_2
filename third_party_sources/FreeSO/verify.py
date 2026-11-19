"""Verify the vendored upstream source excerpt without a network connection."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent
manifest = json.loads((root / "sources.json").read_text())
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--checkout", type=Path)
args = parser.parse_args()
for path, expected in manifest["blobs"].items():
    data = (root / path).read_bytes()
    actual = hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()
    if actual != expected:
        raise SystemExit(f"Upstream blob mismatch: {path}")
    if args.checkout:
        oid = subprocess.check_output(["git", "-C", str(args.checkout), "rev-parse",
                                       manifest["revision"] + ":" + path], text=True).strip()
        if oid != expected or not (args.checkout / path).is_file():
            raise SystemExit(f"Missing or different upstream entry: {path}")
print(f"Verified {len(manifest['blobs'])} blobs from FreeSO {manifest['revision']}")
