"""Capture the B-series whitebox review frames in a real Forward+ window via the Game MCP bridge.

    .runtime/python/Scripts/python.exe tools/b_series/capture_review.py [--out .runtime/b-series/review] [--publish]

--publish also writes downsized JPG contact sheets to docs/design/b-series/media/.
"""
import argparse
import json
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools' / 'chronograph'))
from capture import Run, contact_sheet, digest  # noqa: E402
from PIL import Image  # noqa: E402

ROOMS = ("b01", "b02", "b03")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=str(ROOT / ".runtime" / "b-series" / "review"))
    parser.add_argument("--publish", action="store_true")
    parser.add_argument("--settle", type=int, default=90, help="frames to let SDFGI settle per shot")
    args = parser.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    run = Run(0, scene_key="b_series", scene_args=("--b-room=b01",))
    frames = []
    try:
        state = run.request("observe", timeout=120)["state"]
        for room in ROOMS:
            assert state["room"] == room, state
            for index in range(state["views"]):
                run.request("wait", frames=args.settle, timeout=60)
                packet = json.loads(run.request("observe", screenshot=True, timeout=60)[0]) \
                    if isinstance(run.request, type(None)) else None
                packet = run.request("observe", screenshot=True, timeout=60)
                if isinstance(packet, (list, tuple)):
                    packet = json.loads(packet[0])
                s = packet["state"]
                r = s["render"]
                assert packet["viewport_size"] == [1280, 720] and packet["renderer"] == "forward_plus", packet
                assert r["msaa_samples"] == 2 and r["sdfgi_enabled"] and abs(r["ink_opacity"] - 0.40) < 1e-5, r
                label = f"{room}-{index}-{s['view_name'].lower().replace(' ', '-')}"
                file = out / f"{label}.png"
                shutil.copyfile(packet["screenshot"], file)
                frames.append({"room": room, "label": label, "file": file.name, "sha256": digest(file),
                               "view": s["view_name"], "renderer": packet["renderer"], "render": r})
                print(label, flush=True)
                state = run.request("action", action="b_next_view", frames=1, timeout=30)["state"]
            state = run.request("action", action="b_next_room", frames=1, timeout=60)["state"]
    finally:
        run.close()
    (out / "manifest.json").write_text(json.dumps(frames, indent=2), encoding="utf-8")
    for room in ROOMS:
        subset = [f for f in frames if f["room"] == room]
        contact_sheet(out, subset, f"{room}-contact", f"{room.upper()} whitebox — Forward+ 1280x720, HallFinish, Hall04, Ink 0.40")
    if args.publish:
        media = ROOT / "docs" / "design" / "b-series" / "media"
        media.mkdir(parents=True, exist_ok=True)
        for f in frames:
            with Image.open(out / f["file"]) as image:
                image.convert("RGB").save(media / (Path(f["file"]).stem + ".jpg"), quality=86)
        for room in ROOMS:
            shutil.copyfile(out / f"{room}-contact.jpg", media / f"{room}-contact.jpg")


if __name__ == "__main__":
    main()
