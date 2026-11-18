"""Run a project-bound workbench fixture and assemble independently verifiable contact sheets."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from datetime import datetime

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "mcp"))
import capture_provenance as provenance
from review_refresh import start_review_watcher


def make_sheets(directory: Path) -> list[dict]:
    from PIL import Image, ImageDraw
    records_path = directory / "captures.json"
    if not records_path.is_file():
        return []
    captures = json.loads(records_path.read_text(encoding="utf-8-sig"))
    groups: dict[str, list[dict]] = {}
    for record in captures:
        verified = provenance.verify_image(record["path"], ROOT, allow_fixture=True)
        record = dict(record, provenance=verified)
        tag = record["tag"]
        group = tag.rsplit("_", 1)[0] if tag.endswith(("_start", "_process", "_end")) else "lighting" if tag.startswith("lighting_") else "building_" + str(int(tag.split("_")[-1]) // 12) if tag.startswith("building_") else "manual"
        groups.setdefault(group, []).append(record)
    output = []
    for name, records in groups.items():
        columns = min(3, len(records))
        width, height, caption = 480, 300, 28
        sheet = Image.new("RGB", (columns * width, ((len(records) + columns - 1) // columns) * (height + caption)), "#172025")
        draw = ImageDraw.Draw(sheet)
        for index, record in enumerate(records):
            with Image.open(record["path"]) as source:
                frame = source.convert("RGB")
                frame.thumbnail((width, height))
            left = index % columns * width
            top = index // columns * (height + caption)
            sheet.paste(frame, (left + (width - frame.width) // 2, top + (height - frame.height) // 2))
            draw.text((left + 8, top + height + 5), record["tag"], fill="#ded7bf")
        path = directory / "sheets" / (name + ".jpg")
        path.parent.mkdir(parents=True, exist_ok=True)
        sheet.save(path, quality=88)
        metadata = {"capture_kind": "derived-contact-sheet", "acceptance_eligible": False,
                    "source_identity": records[0]["provenance"]["source_identity"],
                    "image_path": str(path), "image_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                    "sources": records}
        path.with_suffix(path.suffix + ".json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
        output.append({"path": str(path), "sources": len(records), "sha256": metadata["image_sha256"]})
    (directory / "contact-sheets.json").write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    return output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default="res://assets/data/test_scenarios/interaction.yaml")
    parser.add_argument("--suite", choices=["interactions", "lighting", "building"])
    parser.add_argument("--duration", type=float, default=0)
    parser.add_argument("--output")
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--assemble-only", action="store_true")
    args = parser.parse_args()
    start_review_watcher()
    directory = provenance.project_path(args.output or ".runtime/test-runs/" + datetime.now().strftime("%Y%m%d-%H%M%S-%f"), ROOT)
    if args.assemble_only:
        print(json.dumps({"sheets": make_sheets(directory)}, ensure_ascii=False))
        return 0
    if directory.exists() and any(directory.iterdir()):
        parser.error("Output directory must be new or empty; evidence is never overwritten")
    directory.mkdir(parents=True, exist_ok=True)
    config = provenance.project_path(args.config, ROOT)
    if not config.is_file():
        parser.error("Config file does not exist")
    if args.duration <= 0 and not args.suite:
        parser.error("Supply a positive --duration or a --suite")
    executable = provenance.host_executable(ROOT / ".runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64.exe")
    command = [executable, "--path", str(ROOT), "--headless" if args.headless else "--minimized",
               "--", "--dv-workbench", "--scenario=" + str(config),
               "--test-output=" + str(directory), "--test-auto-quit=true"]
    if args.suite:
        command += ["--test-suite=" + args.suite]
    if args.duration > 0:
        command += ["--test-duration=" + str(args.duration)]
    identity = provenance.project_identity(ROOT)
    with (directory / "godot.log").open("w", encoding="utf-8") as log:
        process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                   creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        try:
            code = process.wait(timeout=max(args.duration + 45, 180))
        except subprocess.TimeoutExpired:
            process.terminate()
            code = process.wait(timeout=10)
            code = code or 124
    log_text = (directory / "godot.log").read_text(encoding="utf-8-sig", errors="replace")
    errors = [line for line in log_text.splitlines() if "ERROR:" in line or "SCRIPT ERROR" in line]
    if errors and code == 0:
        code = 1
    result = {"source_identity": identity, "host_pid": process.pid, "command": command, "exit_code": code,
              "errors": errors, "headless": args.headless, "acceptance_scored": False,
              "sheets": make_sheets(directory) if code == 0 and not args.headless else []}
    (directory / "launch-receipt.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
