"""Assemble review-only, locally verified frozen evidence; never dispatch an Astra review."""
from datetime import datetime, timezone
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

from gate import evaluate, artifact_valid

ROOT = Path(__file__).resolve().parents[2]


def write_json(path, data):
    path.write_bytes((json.dumps(data, indent=2, ensure_ascii=False) + "\n").encode("utf-8"))


def receipt(path, out):
    return {"file": path.relative_to(out).as_posix(), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def inside(root, name):
    relative = Path(name)
    result = (root / relative).resolve()
    if relative.is_absolute() or not result.is_relative_to(root.resolve()):
        raise ValueError(f"Unsafe relative evidence path: {name}")
    return result


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def scene_sources(revision, names, out):
    paths = sorted(set(git("ls-tree", "-rz", "--name-only", revision, "--", *names).decode("utf-8").split("\0")) - {""})
    if not paths:
        raise ValueError("No sources from frozen revision match --source")
    subprocess.run(["git", "diff", "--quiet", revision, "--", *names], cwd=ROOT, check=True)
    records = []
    for name in paths:
        path = inside(out / "source", name)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(git("show", f"{revision}:{name}"))
        records.append({"path_at_revision": name, **receipt(path, out)})
    return records


def readings(frame):
    return frame.get("render") or frame["state"]["render"]


def validate_render(frame):
    r = readings(frame)
    if frame["renderer"] != "forward_plus" or frame["viewport"] != [1280, 720]:
        raise ValueError(f"Wrong game renderer/viewport: {frame['file']}")
    actual = (r.get("scaling_3d_scale", r.get("native_scale")), r.get("msaa_samples", 2 ** r.get("msaa", -1)),
              r.get("sdfgi_enabled", r.get("sdfgi")))
    if actual != (1.0, 2, True) or abs(r.get("ink_opacity", 0.0) - 0.40) > 1e-5:
        raise ValueError(f"Mainline render parameters differ: {frame['file']}")
    return {"file": frame["file"], "renderer": frame["renderer"], "viewport": frame["viewport"], **r}


def field(data, key):
    for name in key.split("."):
        if not isinstance(data, dict): return None
        data = data.get(name)
    return data


def assemble(args):
    out, capture_dir = args.out.resolve(), args.capture.resolve()
    if out.exists():
        raise ValueError("Review packages are immutable; use a new --out directory")
    ledger = json.loads(args.ledger.read_text(encoding="utf-8-sig"))
    evidence = json.loads((capture_dir / "manifest.json").read_text(encoding="utf-8-sig"))
    revision = ledger["revision"]
    final = json.loads(args.terminal_value)
    if evidence.get("room") != ledger["candidate"] or not any(field(frame, args.terminal_field) == final for frame in evidence["frames"]):
        raise ValueError("Frozen candidate needs a captured terminal win")
    if not ledger.get("golden", {}).get("passed_live") or ledger["golden"].get("revision") != revision:
        raise ValueError("Frozen revision is missing a live golden receipt")
    render = [validate_render(f) for f in evidence["frames"]]
    for f in evidence["frames"]:
        if not artifact_valid({"file": f["file"], "sha256": f["sha256"]}, capture_dir):
            raise ValueError(f"Frame hash failed: {f['file']}")
    out.mkdir(parents=True)
    (out / "frames").mkdir()
    for f in evidence["frames"]:
        src = inside(capture_dir, f["file"])
        dest = inside(out / "frames", f["file"])
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dest)
    paths = {"brief": (args.brief, "brief.md"), "contact": (inside(capture_dir, args.contact), "contact.jpg"),
             "golden": (args.golden, "golden.json"), "live_trace": (inside(capture_dir, args.trace), "live-trace.json"),
             "frame_manifest": (capture_dir / "manifest.json", "frame-manifest.json")}
    artifacts = {}
    for name, (original, basename) in paths.items():
        artifacts[name] = receipt(Path(shutil.copyfile(original, out / basename)), out)
    artifacts["render_receipt"] = receipt_file(out, "render-receipt.json", {"revision": revision, "frames": render})
    artifacts["source_manifest"] = receipt_file(out, "source-manifest.json", {"revision": revision, "files": scene_sources(revision, args.source, out)})
    ledger["evidence"] = artifacts
    for r in ledger.get("red_reports", []) + ([ledger["judge"]] if ledger.get("judge") else []):
        rec = r["receipt"]
        if artifact_valid(rec, args.ledger.parent):
            saved = inside(out / "receipts", rec["file"])
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(inside(args.ledger.parent, rec["file"]), saved)
            r["receipt"] = receipt(saved, out)
    write_json(out / "gate.json", ledger)
    result = evaluate(ledger, out, datetime.now(timezone.utc))
    write_json(out / "decision.json", result)
    return result


def receipt_file(out, name, value):
    artifact = out / name
    write_json(artifact, value)
    return receipt(artifact, out)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for param in ["ledger", "capture", "brief", "golden", "out"]:
        parser.add_argument("--" + param, type=Path, required=True)
    parser.add_argument("--contact", default="golden-contact.jpg")
    parser.add_argument("--trace", default="live-trace.json")
    parser.add_argument("--source", action="append", required=True, help="Project relative Git path; repeat as needed")
    parser.add_argument("--terminal-field", required=True, help="Dot-separated winning field relative to a frame record")
    parser.add_argument("--terminal-value", required=True, help="Winning value in JSON, e.g. true or \'\"won\"\'")
    print(json.dumps(assemble(parser.parse_args()), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
