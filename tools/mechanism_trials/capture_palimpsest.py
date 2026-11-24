"""Play the Palimpsest Switchyard through Game MCP; capture scene and turn evidence."""
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
    parser.add_argument("--out", type=Path, default=ROOT / ".runtime" / "academy-mechanisms" / "palimpsest")
    out = parser.parse_args().out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    case = json.loads((ROOT / "tools" / "palimpsest" / "golden.json").read_text(encoding="utf-8"))["cases"][0]
    run = Run(1, scene_key="palimpsest")
    frames, trace = [], []

    def key(action):
        return run.request("action", action="palimpsest_" + action, frames=1, timeout=20)["state"]

    def wait_for(condition, timeout=10):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            data = run.request("observe", timeout=20)["state"]
            if condition(data):
                return data
        raise AssertionError(f"Unexpected state: {data}")

    def shot(name, kind="golden"):
        packet = json.loads(run.request("observe", screenshot=True, timeout=40)[0])
        state = packet["state"]
        r = state["render"]
        assert packet["viewport_size"] == [1280, 720]
        assert r["scaling_3d_scale"] == 1.0 and r["msaa_samples"] == 2 and r["sdfgi_enabled"]
        assert abs(r["ink_opacity"] - 0.40) < 1e-5
        assert r["opaque_shader"].endswith("/HallFinish.gdshader") and r["atmosphere_baseline"].endswith("/Hall04.tres")
        file = out / (name + ".png")
        shutil.copyfile(packet["screenshot"], file)
        frames.append({"label": name, "kind": kind, "file": file.name, "sha256": digest(file),
                       "renderer": packet["renderer"], "viewport": packet["viewport_size"], **state})
        print(name, state["state"]["tick"], flush=True)
        return state

    def commit(port):
        key(["i", "ii", "iii"][int(port.removeprefix("port_"))])
        key("confirm")
        return wait_for(lambda d: not d["selected"] and not d["state"]["in_flight"])

    try:
        run.request("observe", timeout=90)
        shot("01-entry")
        key("i")
        s = shot("02-forty-tick-ghost")
        assert s["selected"] == "port_0" and s["state"]["tick"] == 0
        key("view")
        shot("03-detail", "controls")
        key("view")
        shot("04-plan", "controls")
        key("view")
        key("confirm")
        wait_for(lambda d: d["state"]["tick"] == 20 and not d["state"]["in_flight"])
        key("iii")
        s = shot("05-forecast-of-revisit", "controls")
        assert s["preview_result"] == "failed"
        key("confirm")
        s = wait_for(lambda d: d["state"]["phase"] == "failed")
        assert s["state"]["failure"] == "ink_revisit"
        shot("06-revisit-rejected", "controls")
        key("reset")

        for n, port in enumerate(case["actions"], start=1):
            if port == "rewind":
                key("confirm")
                s = shot("10-turn-first-two-strokes")
                assert s["selected"] == "rewind" and s["state"]["phase"] == "record"
                key("confirm")
                wait_for(lambda d: d["state"]["phase"] == "rewind" and d["state"]["cured"].count(True) >= 25)
                shot("11-return-and-cure")
                end = wait_for(lambda d: d["state"]["phase"] == "won", timeout=40)
                trace.append({"action": port, **end})
                break
            state = commit(port)
            assert len(state["state"]["tape"]) == n and state["state"]["phase"] == "record", state
            trace.append({"action": port, **state})
            if n in [13, 40, 72]:
                shot({13: "07-ink-thirteen", 40: "08-ink-forty", 72: "09-ready-to-rewind"}[n])
        assert shot("12-exit-open")["state"]["tick"] == 2880
        (out / "manifest.json").write_text(json.dumps({"room": "A03 / The Palimpsest Switchyard", "session": run.id,
                                                       "frames": frames}, ensure_ascii=False, indent=2), encoding="utf-8")
        (out / "live-trace.json").write_text(json.dumps(trace, ensure_ascii=False, indent=2), encoding="utf-8")
        for kind, title in [("golden", "A03 / SWITCHYARD: INK FORWARD, CURE BACKWARD"),
                            ("controls", "A03 / SWITCHYARD: SECTIONS AND JAM CONTROL")]:
            contact_sheet(out, [f for f in frames if f["kind"] == kind], kind + "-contact", title)
    finally:
        run.close()
        shutil.copyfile(run.log, out / "godot-process.log")


if __name__ == "__main__":
    main()
