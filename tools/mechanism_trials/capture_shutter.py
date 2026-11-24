"""Run A04 with the real Game MCP; compare cue lead and winning state to machine golden."""
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
    parser.add_argument("--out", type=Path, default=ROOT / ".runtime" / "academy-mechanisms" / "shutter-loom")
    out = parser.parse_args().out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    case = json.loads((ROOT / "tools" / "shutter_loom" / "golden.json").read_text(encoding="utf-8"))
    run = Run(case["seed"], scene_key="shutter_loom")
    frames, trace = [], []

    def advance(command):
        run.request("action", action="shutter_" + command, frames=1, timeout=20)
        until = time.monotonic() + 10
        while time.monotonic() < until:
            state = run.request("observe", timeout=20)["state"]
            if not state["ticks_left"]:
                trace.append({"action": command, **state})
                return state
        raise AssertionError(state)

    def shot(name):
        packet = json.loads(run.request("observe", screenshot=True, timeout=40)[0])
        state = packet["state"]
        r = state["render"]
        assert packet["viewport_size"] == [1280, 720]
        assert r["scaling_3d_scale"] == 1.0 and r["msaa_samples"] == 2 and r["sdfgi_enabled"]
        assert abs(r["ink_opacity"] - 0.40) < 1e-5
        assert r["opaque_shader"].endswith("/HallFinish.gdshader") and r["atmosphere_baseline"].endswith("/Hall04.tres")
        file = out / (name + ".png")
        shutil.copyfile(packet["screenshot"], file)
        frames.append({"label": name, "file": file.name, "sha256": digest(file),
                       "renderer": packet["renderer"], "viewport": packet["viewport_size"], **state})
        print(name, state["state"]["tick"], flush=True)
        return state

    cuts = {20: "02-steam-before-throw", 100: "03-west-ray-cut-shadow-gone", 580: "04-return-warning",
            720: "05-home-restored", 820: "06-east-ray-cut-ink-remains", 860: "07-west-cross-permit",
            900: "08-crossing-warning", 940: "09-crossing", 1000: "10-exit-lintel", 1020: "11-won"}
    try:
        run.request("observe", timeout=90)
        shot("01-entry")
        actions = [a for a, n in case["actions"] for _ in range(n)]
        tick = 0
        index = 0
        while index < len(actions):
            n = 3 if actions[index:index+3] == ["wait"]*3 and not ({tick + 20, tick + 40} & cuts.keys()) else 1
            state = advance("watch" if n == 3 else actions[index])
            index += n
            tick += n * 20
            assert state["state"]["tick"] == tick
            if tick in cuts:
                shot(cuts[tick])
        assert state["state"]["outcome"] == case["outcome"]
        e = [[x["tick"], x["kind"], x["lane"], x["cue_id"], x.get("due_tick", x.get("lead_ticks"))]
             for x in state["events"]]
        assert e == case["events"], e
        (out / "manifest.json").write_text(json.dumps({"room": "A04 / The Shutter Loom", "session": run.id,
                                                       "frames": frames}, ensure_ascii=False, indent=2), encoding="utf-8")
        (out / "live-trace.json").write_text(json.dumps(trace, ensure_ascii=False, indent=2), encoding="utf-8")
        contact_sheet(out, [f for f in frames if not f["label"].startswith(("05", "09", "10"))], "golden-contact",
                      "A04 / THE SHUTTER LOOM: REAL SHADE, FIXED INK")
    finally:
        run.close()
        shutil.copyfile(run.log, out / "godot-process.log")


if __name__ == "__main__":
    main()
