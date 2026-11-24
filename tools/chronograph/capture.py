"""Replay the reviewed action tape through the real project Game MCP and produce a contact sheet."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "mcp" / "game"))
from server import Run  # noqa: E402


def verify(state, expected):
    differences = {k: (state.get(k), v) for k, v in expected.items() if state.get(k) != v}
    if differences:
        raise AssertionError(differences)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def contact_sheet(out, frames, basename, heading):
    width, height = 640, 360
    pad, margin, title, caption = 16, 24, 65, 28
    n = (len(frames) + 1) // 2
    canvas = Image.new("RGB", (margin * 2 + pad + width * 2, title + n * (height + caption + pad)), "#17242d")
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default(size=19)
    draw.text((margin, 21), heading.replace("—", " / "), fill="#ffe6c3", font=ImageFont.load_default(size=26))
    for i, frame in enumerate(frames):
        x = margin + i % 2 * (width + pad)
        y = title + i // 2 * (height + caption + pad)
        with Image.open(out / frame["file"]) as image:
            canvas.paste(image.convert("RGB").resize((width, height), Image.Resampling.LANCZOS), (x, y))
        draw.text((x + 4, y + height + 3), frame["label"].replace("-", " ").upper(), fill="#c4e9e3", font=font)
    canvas.save(out / (basename + ".jpg"), quality=92, subsampling=0)


def run_review(out, case):
    run = Run(case["seed"], scene_key="chronograph")
    frames, trace = [], []

    def key(action):
        payload = run.request("action", action="chrono_" + action, frames=1, timeout=45)
        state = payload["state"]["state"]
        trace.append({"action": action, "state": state})
        return state

    def shot(label, kind):
        payload = json.loads(run.request("observe", screenshot=True, timeout=60)[0])
        assert payload["viewport_size"] == [1280, 720], payload["viewport_size"]
        dest = out / (label + ".png")
        shutil.copyfile(payload["screenshot"], dest)
        state = payload["state"]
        verify(state["render"], {"native_scale": 1.0, "msaa": 1, "sdfgi": True})
        assert abs(state["render"]["ink_opacity"] - 0.40) < 1e-5
        frames.append({"label": label, "kind": kind, "file": dest.name, "sha256": digest(dest),
                       "renderer": payload["renderer"], "viewport": payload["viewport_size"], **state})
        print(label, state["state"]["tick"], flush=True)
        return state

    try:
        run.request("observe", timeout=90)
        for action in ["south", "use", "east", "north"]:
            key(action)
        verify(shot("control-raw-ore-rejected", "controls")["state"], {"player": "Kiln", "item": "RAW"})
        key("reset")
        for action in ["south", "east", "north", "east", "east"]:
            key(action)
        verify(shot("control-parked-deck-rejects", "controls")["state"], {"player": "Bridge landing", "span": "PARKED"})
        key("reset")
        shot("look-slate-copper", "look")
        key("look")
        shot("look-ivory-patina", "look")
        key("look")
        shot("look-midnight-registry", "look")
        key("look")
        key("view")
        shot("look-reverse-section", "look")
        key("view")
        shot("look-higher-section", "look")
        key("view")
        trace.clear()
        for beat in case["beats"]:
            for action in beat["actions"]:
                key(action)
            verify(shot(beat["label"], "golden")["state"], beat["expect"])
        assert frames[-1]["state"]["won"]
        (out / "manifest.json").write_text(json.dumps({"room": case["room"], "session_id": run.id,
                                                       "frames": frames}, indent=2, ensure_ascii=False), encoding="utf-8")
        (out / "golden-trace.json").write_text(json.dumps(trace, indent=2, ensure_ascii=False), encoding="utf-8")
        contact_sheet(out, [f for f in frames if f["kind"] == "golden" and f["label"] not in
                           {"02-tape", "04-echo-restored"}], "golden-contact", "A01 / THE CHRONOGRAPH WORKS — GOLDEN WALK")
        contact_sheet(out, [f for f in frames if f["kind"] != "golden"], "look-and-controls",
                      "A01 / CONTROLS, MATERIAL STUDIES & SECTION ANGLES")
    finally:
        run.close()
        shutil.copyfile(run.log, out / "godot-process.log")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / ".runtime" / "academy-mechanisms" / "chronograph")
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    case = json.loads(Path(__file__).with_name("golden.json").read_text(encoding="utf-8"))
    run_review(out, case)


if __name__ == "__main__":
    main()
