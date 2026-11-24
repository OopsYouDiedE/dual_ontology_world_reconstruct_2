"""Evidence Register positive/negative Forward+ walk; wait on observed gameplay, not frames."""
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
    parser.add_argument("--out", type=Path, default=ROOT / ".runtime" / "academy-mechanisms" / "evidence-register")
    out = parser.parse_args().out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    run = Run(1, scene_key="evidence_register")
    frames, trace = [], []

    def seen(expect):
        end = time.monotonic() + 10
        while time.monotonic() < end:
            s = run.request("observe", timeout=15)["state"]
            if all(s.get(k) == v for k, v in expect.items()):
                return s
        raise AssertionError(f"Missing {expect} at frame state: {s}")

    def command(action, **expect):
        run.request("action", action="register_" + action, frames=1, timeout=30)
        s = seen(expect) if expect else run.request("observe", timeout=15)["state"]
        trace.append({"action": action, "expected": expect, "state": s})
        return s

    def shot(name, kind="golden"):
        packet = json.loads(run.request("observe", screenshot=True, timeout=60)[0])
        assert packet["viewport_size"] == [1280, 720], packet
        result = packet["state"]
        r = result["render"]
        assert r["scaling_3d_scale"] == 1.0 and r["msaa_samples"] == 2 and r["sdfgi_enabled"]
        assert abs(r["ink_opacity"] - 0.40) < 1e-5
        assert r["opaque_shader"].endswith("/HallFinish.gdshader") and r["atmosphere_baseline"].endswith("/Hall04.tres")
        f = out / (name + ".png")
        shutil.copyfile(packet["screenshot"], f)
        frames.append({"label": name, "kind": kind, "file": f.name, "sha256": digest(f),
                       "viewport": packet["viewport_size"], "renderer": packet["renderer"], "state": result})
        print(name, result["tick"], flush=True)
        return result

    try:
        run.request("observe", timeout=90)
        shot("01-entry")
        command("optics", optics_overlay=True)
        command("take_prism", held="prism")
        command("drawer", station="drawer", walk_ticks_left=0)
        command("send", received="prism", drawer_ticks_left=0)
        shot("02-blind-handoff")
        command("show", last_event="proof_occluded", clerk_sample_rays=0)
        shot("03-hood-occludes", "controls")
        command("sun", dial="sun")
        command("release", last_event="release_denied", latch_open=False)
        shot("04-edition-III-denies", "controls")
        command("proof", station="proof", walk_ticks_left=0)
        command("show", clerk_sample_rays=27, proof_ticks=40)
        shot("05-live-gold-return")
        command("release", latch_open=True)
        command("threshold", station="threshold", stamp_ready=True, walk_ticks_left=0)
        command("file", outcome="clean")
        assert shot("06-clean-filing")["pressure_debt"] == 0

        command("plate", plate=2, station="survey")
        command("take_wax", held="wax")
        command("drawer", station="drawer", walk_ticks_left=0)
        command("send", received="wax")
        command("proof", station="proof", walk_ticks_left=0)
        command("show", last_event="proof_inert", clerk_sample_rays=27)
        shot("07-wax-makes-no-return", "controls")
        command("moon", dial="moon")
        command("override", last_event="override_warning", latch_open=True, pressure_debt=1)
        warning = shot("08-override-warning", "controls")
        assert warning["warning_ticks_left"] > 0
        command("threshold", station="threshold", walk_ticks_left=0)
        command("brace", brace_fitted=True)
        seen({"stamp_ready": True})
        command("file", outcome="emergency")
        shot("09-emergency-filing", "controls")

        (out / "manifest.json").write_text(json.dumps({"room": "A02 / The Evidence Register", "session": run.id,
                                                       "frames": frames}, ensure_ascii=False, indent=2), encoding="utf-8")
        (out / "live-trace.json").write_text(json.dumps(trace, ensure_ascii=False, indent=2), encoding="utf-8")
        for kind, title in [("golden", "A02 / THE EVIDENCE REGISTER — CLEAN WALK"),
                            ("controls", "A02 / HOOD, WAX, OVERRIDE & BRACE")]:
            contact_sheet(out, [f for f in frames if f["kind"] == kind], kind + "-contact", title)
    finally:
        run.close()
        shutil.copyfile(run.log, out / "godot-process.log")


if __name__ == "__main__":
    main()
