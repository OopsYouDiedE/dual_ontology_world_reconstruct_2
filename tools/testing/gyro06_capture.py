"""Capture the four Gyroscope Well plates via the real Forward+ game MCP."""
import argparse
import asyncio
from datetime import timedelta
import json
from pathlib import Path
import shutil
import sys

from PIL import Image, ImageChops

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

from rogue_smoke import ROOT, data

PLATES = {"A": "A-section", "B": "B-ground", "C": "C-bridge", "D": "D-half-cycle"}


async def capture(seed, output):
    output.mkdir(parents=True, exist_ok=True)
    params = StdioServerParameters(command=sys.executable, cwd=str(ROOT), args=[
        str(ROOT / "mcp/game/server.py"), "--service", "input", "--expected-project-root", str(ROOT),
    ])
    async with stdio_client(params) as (reader, writer):
        async with ClientSession(reader, writer, read_timeout_seconds=timedelta(seconds=110)) as session:
            await session.initialize()
            started = data(await session.call_tool("on", {"scene": "gyro06", "seed": seed, "screenshot": False}))
            identity = started["session_id"]

            async def call(name, **args):
                return data(await session.call_tool(name, {"session_id": identity, **args}))

            async def press(action):
                return await call("step", operation="action", action=action, frames=3, screenshot=False)

            try:
                states = {}
                for plate, filename in PLATES.items():
                    await press("gyro_" + plate.lower())
                    shot = await call("step", operation="wait", frames=25, screenshot=True)
                    state = shot["state"]
                    assert shot["renderer"] == "forward_plus" and shot["viewport_size"] == [1600, 1000], shot
                    assert state["view"] == plate and state["step"] == (600 if plate == "D" else 0), state
                    with Image.open(shot["screenshot"]) as image:
                        assert image.size == (1600, 1000), image.size
                    shutil.copyfile(shot["screenshot"], output / (filename + ".png"))
                    states[plate] = state
                    print(f"{filename}: step {state['step']}", flush=True)

                a, d = states["A"], states["D"]
                assert all(abs(a["axis"][i] + d["axis"][i]) < 1e-5 for i in (0, 2)), (a, d)
                assert abs(a["axis"][1] - d["axis"][1]) < 1e-5, (a, d)
                assert a["bridge_nose_m"][0] > a["bridge_nose_m"][1] and d["bridge_nose_m"][0] < d["bridge_nose_m"][1]
                hidden = (await press("gyro_hide"))["state"]
                assert not hidden["visible"] and max(hidden["bridge_nose_m"]) < 7.15, hidden
                revealed = (await press("gyro_hide"))["state"]
                assert revealed["bridge_nose_m"] == d["bridge_nose_m"], revealed
                await press("gyro_b")
                await press("gyro_hide")
                uncovered = await call("step", operation="wait", frames=25, screenshot=True)
                assert not uncovered["state"]["visible"], uncovered
                # Compare a central band of the floor before/after removing the actual mesh.
                region = (350, 693, 1250, 898)
                with Image.open(uncovered["screenshot"]) as off, Image.open(output / "B-ground.png") as on:
                    gain = ImageChops.subtract(off.crop(region).convert("L"), on.crop(region).convert("L"))
                    brightened = sum(gain.histogram()[36:])
                assert brightened > 2000, brightened
                await press("gyro_hide")
                walking = (await press("gyro_walk"))["state"]
                advanced = (await call("step", operation="wait", frames=18, screenshot=False))["state"]
                assert walking["view"] == "" and walking["visible"] and advanced["step"] > walking["step"], (walking, advanced)
                paused = (await press("gyro_pause"))["state"]
                held = (await call("step", operation="wait", frames=12, screenshot=False))["state"]
                assert held["step"] == paused["step"], (paused, held)
                await press("gyro_pause")
                resumed = (await call("step", operation="wait", frames=12, screenshot=False))["state"]
                assert resumed["step"] > held["step"], (held, resumed)
                print(f"Live playback: pause held tick {held['step']}; resumed to {resumed['step']}", flush=True)
                log = Path(started["log"])
                assert "ERROR:" not in log.read_text(encoding="utf-8"), log
                (output / "report.json").write_text(json.dumps({"plates": states, "floor_pixels_relit_by_hide": brightened, "log": str(log)}, indent=2) + "\n")
            finally:
                await call("close")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=int, default=6)
    parser.add_argument("--output", type=Path, default=ROOT / ".runtime/gyro06/plates")
    options = parser.parse_args()
    asyncio.run(capture(options.seed, options.output.resolve()))
