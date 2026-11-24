"""Capture the two causal reconstructions of Afterimage through normal Game MCP inputs."""
import argparse
import json
import shutil
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "chronograph"))
from capture import Run, contact_sheet, digest  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / ".runtime" / "academy-mechanisms" / "afterimage")
    out = parser.parse_args().out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    case = json.loads((ROOT / "tools" / "afterimage" / "golden.json").read_text(encoding="utf-8"))
    run = Run(1, scene_key="afterimage")
    frames, trace = [], []

    def advance(command):
        name = command.removeprefix("move ")
        run.request("action", action="afterimage_" + name, frames=1, timeout=20)
        limit = time.monotonic() + 10
        while time.monotonic() < limit:
            payload = run.request("observe", timeout=20)["state"]
            if not payload["advance"]:
                trace.append({"action": command, **payload})
                return payload["state"]
        raise AssertionError(payload)

    def shot(label, kind):
        payload = json.loads(run.request("observe", screenshot=True, timeout=50)[0])
        packet = payload["state"]
        r = packet["render"]
        assert payload["viewport_size"] == [1280, 720]
        assert r["scaling_3d_scale"] == 1.0 and r["msaa_samples"] == 2 and r["sdfgi_enabled"]
        assert abs(r["ink_opacity"] - 0.40) < 1e-5
        assert r["opaque_shader"].endswith("/HallFinish.gdshader") and r["atmosphere_baseline"].endswith("/Hall04.tres")
        file = out / (label + ".png")
        shutil.copyfile(payload["screenshot"], file)
        frames.append({"label": label, "kind": kind, "file": file.name, "sha256": digest(file), "renderer": payload["renderer"],
                       "viewport": payload["viewport_size"], **packet})
        print(label, packet["state"]["tick"], flush=True)
        return packet["state"]

    labels = {0: "entry", 40: "first-wired-pulse", 160: "reel-armed", 180: "rewind-warning", 220: "splice",
              260: "paired-west", 300: "west-crossing-and-spring", 320: "prism-warning", 340: "presilver", 360: "paired-east", 400: "exit"}
    try:
        run.request("observe", timeout=90)
        assert advance("move carriage")["last_action"]["reason"] == "no_gangway"
        shot("control-unpowered-bridge", "control")
        advance("reset")
        for i, variant in enumerate(["from_lamp", "from_bell"], start=1):
            shot(f"{i}-entry", variant)
            inputs = case[variant]["record"] + ["rewind", "wait", "wait"] + case[variant]["play"]
            for k, action in enumerate(inputs, start=1):
                s = advance(action)
                tick = k * 20
                assert s["tick"] == tick
                if tick == case["clock"]["west_pair"] or tick == case["clock"]["east_pair"]:
                    side = "west" if tick == case["clock"]["west_pair"] else "east"
                    assert s["pair"]["accepted"] and s["pair"]["receiver"] == side
                    assert {x["source"] for x in s["signals"]} == set(case[variant][side + "_pair"])
                if tick in labels:
                    shot(f"{i}-{tick:03d}-{labels[tick]}", variant)
            assert s["won"] and s["player"] == "exit"
            if i == 1: advance("reset")
        (out / "manifest.json").write_text(json.dumps({"room": "A05 / The Afterimage Carriage", "session": run.id,
                                                       "frames": frames}, ensure_ascii=False, indent=2), encoding="utf-8")
        (out / "live-trace.json").write_text(json.dumps(trace, ensure_ascii=False, indent=2), encoding="utf-8")
        for variant, title in [("from_lamp", "A05 / AFTERIMAGE CARRIAGE: THE LAMP REMEMBERS"),
                               ("from_bell", "A05 / AFTERIMAGE CARRIAGE: THE BELL REMEMBERS")]:
            contact_sheet(out, [f for f in frames if f["kind"] == variant and not f["label"].startswith(("1-040", "2-040", "1-340", "2-340", "1-220", "2-220"))], variant, title)
    finally:
        run.close()
        shutil.copyfile(run.log, out / "godot-process.log")


if __name__ == "__main__":
    main()
