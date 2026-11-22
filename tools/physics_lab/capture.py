"""Run all ten counterfactual/positive experiments through the Game MCP Forward+ viewport."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "mcp" / "game"))
import server  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / ".runtime" / "physics-lab" / "evidence")
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    run = server.Run(1, scene_key="physics_lab")
    rows = []
    trace = []

    def key(name):
        packet = run.request("action", action="lab_" + name, frames=1, timeout=45)["state"]
        # The pause request can land at any wall-clock time; the reset establishes tick zero.
        if name != "pause":
            packed = json.dumps(packet["state"], sort_keys=True, separators=(",", ":"))
            trace.append(dict(plate=packet["plate"], tick=packet["tick"], action=name,
                              sha256=hashlib.sha256(packed.encode()).hexdigest()))
        return packet["state"]

    def step(count=1):
        for _ in range(count):
            value = key("step")
        return value

    def shot(name):
        packet = json.loads(run.request("observe", screenshot=True, timeout=60)[0])
        state = packet["state"]
        filename = f'{state["plate"]:02d}-{name}.png'
        shutil.copyfile(packet["screenshot"], out / filename)
        rows.append(dict(image=filename, viewport=packet["viewport_size"], renderer=packet["renderer"], **state))
        (out / "manifest.json").write_text(json.dumps(rows, indent=2), encoding="utf-8")
        print(filename, flush=True)
        return state["state"]

    def next_plate():
        key("next")
        key("reset")
        shot("entry")

    try:
        print(f"Godot log: {run.log}", flush=True)
        run.request("observe", timeout=90)
        key("pause")
        key("reset")
        shot("entry")
        assert not key("c")["passed"]
        assert abs(key("a")["power"] - 0.125) < 1e-9
        assert key("c")["passed"]
        shot("third-pane-45")
        assert key("b")["power"] == 0
        assert not key("c")["passed"]
        shot("third-pane-90")
        key("b")
        key("c")
        key("view")
        shot("eye-level")
        key("view")

        next_plate()
        key("a")
        key("c")
        assert step()["warning"] == 20
        shot("antinode-warning")
        assert step()["fault"]
        shot("antinode-stop")
        key("b")
        key("c")
        assert step(3)["passed"]
        shot("shifted-node-pass")

        next_plate()
        key("a")
        assert step()["hits"] > 0
        key("b")
        assert not step()["bridge"]
        key("b")
        assert step()["bridge"]
        key("c")
        assert step()["crossing"] == 20
        shot("crossing")
        key("a")
        assert step()["warning"] == 20
        shot("gaze-loss-warning")
        assert step()["fault"]
        key("a")
        step()
        key("c")
        step()
        key("a")
        assert step()["warning"] == 20
        key("a")
        assert step(3)["passed"]
        shot("partner-across")

        next_plate()
        assert key("c")["probe_length"] == 6000
        for _ in range(3):
            assert key("a")["layer"] == 0
        assert key("a")["layer"] == 1
        s = key("c")
        assert s["probe_length"] == 12000 and s["probe_hits"] > 0
        assert key("d")["passed"]
        shot("four-turns-upstairs")
        key("view")
        shot("upper-door-eye")
        key("view")
        assert key("b")["layer"] == 0

        next_plate()
        key("a")
        key("d")
        assert step()["gate"] > 0
        shot("open-gate")
        assert step(2)["right"] == 1
        step(3)
        key("a")
        key("d")
        assert step(6)["energy_r"] == 5  # Slow pellet also passes an open gate.
        assert not shot("unsorted-control")["passed"]
        key("reset")
        for fast in [1, 0, 0, 1]:
            assert key("b")["register"] == fast
            if fast:
                key("a")
            key("d")
            step(3)
            if fast:
                shot(f"fast-{step(1)['right']}")
                step(2)
            else:
                step(3)
            key("c")
        s = shot("selective-sort")
        assert s["left"] == 2 and s["right"] == 2 and s["passed"] and s["erased"] == 4

        next_plate()
        key("b")
        assert step()["warning"] > 0
        shot("ascent-warning")
        key("d")
        assert shot("brake-recovered")["height"] == 0
        key("b")
        assert step(3)["fault"]
        key("c")
        key("a")
        key("b")
        assert 0 < step(2)["height"] < 3
        shot("flipped-in-transit")
        step(2)
        key("c")
        key("a")
        key("b")
        step(4)
        key("c")
        key("a")
        key("b")
        step(4)
        assert key("c")["passed"]
        shot("both-weights-upstairs")
        key("reset")
        assert key("d")["pocket"]
        key("b")
        s = step(4)
        assert s["height"] > 2.99 and s["warning"] == 0 and s["gravity"] == -1
        shot("field-free-pocket")

        next_plate()
        assert not key("b")["valid"]
        shot("rejected-stroke")
        for action, form in zip("abc", ["magnetic", "floating", "luminous"]):
            key(action)
            step(2)
            shot(form)
        assert key("d")["passed"]
        shot("deck-lowered")

        next_plate()
        assert step()["emf"] == 0
        key("b")
        assert step(3)["probe_x"] > 0
        shot("positive-field")
        key("a")
        key("b")
        assert step(3)["probe_x"] < 0
        shot("reversed-field")
        key("c")
        step(2)
        shot("stroke-approach")
        assert step()["hold"] > 0
        shot("induced-open")
        key("a")
        assert step()["warning"] == 20
        shot("live-reversal-warning")
        key("d")
        assert step()["emf"] == 0
        assert step(3)["hold"] == 0
        shot("stationary-lock")

        next_plate()
        assert key("a")["frame_delta"] > 0
        assert step(2)["arrival_r"] == ["B"]
        shot("photons-in-flight")
        assert step(3)["order_seen"]
        s = shot("opposite-arrival-orders")
        assert s["arrival_l"] == ["A", "B"] and s["arrival_r"] == ["B", "A"]
        assert key("b")["frame_delta"] < 0
        key("c")
        assert len(step(3)["record"]) == 60
        key("c")
        assert step()["warning"] == 20
        shot("echo-obstructed")
        assert step()["fault"]
        key("c")
        key("d")
        assert step()["passed"]
        shot("echo-synchronized")

        next_plate()
        key("c")
        assert step(3)["head"] == 1
        shot("first-write")
        assert step(12)["halt"] == "REJECT"
        shot("odd-rejected")
        key("reset")
        key("a")
        assert key("d")["tape"] == [1, 1, 0, 0]
        key("c")
        assert step(15)["halt"] == "ACCEPT"
        shot("even-accepted")
        log = run.log.read_text(encoding="utf-8", errors="replace")
        if "SCRIPT ERROR" in log or "ERROR:" in log:
            raise RuntimeError(f"Engine errors: {run.log}")
        (out / "trace.json").write_text(json.dumps(trace, indent=2), encoding="utf-8")
        print(f"10 plates, {len(rows)} real viewport captures, {len(trace)} deterministic command samples: {out}", flush=True)
    finally:
        run.close()


if __name__ == "__main__":
    main()
