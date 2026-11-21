"""Exercise Rubber Yard in the project's real Forward+ game MCP."""
import asyncio
from datetime import timedelta
import json
import math
import sys

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

from rogue_smoke import ROOT, data


async def exercise(client, identity):
    async def step(frames=12, action=None, screenshot=False):
        args = {"session_id": identity, "frames": frames, "screenshot": screenshot}
        args["operation"] = "action" if action else "wait"
        if action:
            args["action"] = action
        return data(await client.call_tool("step", args))

    async def state(frames=12, action=None):
        return (await step(frames, action))["state"]

    async def reset():
        await state(6, "whitebox_reset")
        home = await state(14)
        assert math.dist(home["player"], (0, 0, 4.45)) < 0.05, home
        assert math.dist(home["block"], (4.55, 0.56, -0.95)) < 0.05, home
        assert home["gate"] == "Standby" and home["grounded"], home

    overview = await step(48, screenshot=True)
    assert overview["renderer"] == "forward_plus", overview
    assert overview["state"]["grounded"] and overview["state"]["gate"] == "Standby", overview
    jumping = await state(9, "whitebox_jump")
    assert not jumping["grounded"] and jumping["player"][1] > 0.15, jumping
    landed = await state(64)
    assert landed["grounded"] and landed["peak_height"] > 1.0, landed

    await state(77, "move_up")
    opened = await state(45)
    assert opened["plate_occupied"] and opened["gate"] == "Open", opened
    through = await state(96, "move_up")
    assert through["player"][2] < -6.5 and not through["plate_occupied"], through
    closed = await state(120)
    assert closed["gate"] == "Standby", closed

    await reset()
    await state(91, "move_left")
    on_deck = await state(92, "move_up")
    assert on_deck["grounded"] and 1.20 < on_deck["player"][1] < 1.30, on_deck
    down = await state(105, "move_up")
    assert down["grounded"] and abs(down["player"][1]) < 0.04, down
    wall = await state(115, "move_left")
    assert -10.55 < wall["player"][0] < -10.25, wall

    await reset()
    await state(85, "move_right")
    await state(78, "move_up")
    # MCP action durations use process frames. Approach the plate by observed
    # position so a slower render frame cannot push the block through the target.
    pushed = await state(41, "move_left")
    for _ in range(16):
        if pushed["block"][0] < 0.83:
            break
        pushed = await state(8, "move_left")
    assert -0.8 < pushed["block"][0] < 0.83, pushed
    away = await state(37, "move_down")
    assert away["player"][2] > 0.55 and abs(away["block"][0]) < 1.3, away
    loaded = await state(120)
    assert loaded["plate_occupied"] and loaded["gate"] == "Open", loaded

    await reset()
    await state(6, "whitebox_hud")
    zoom = await state(48, "whitebox_zoom_in")
    assert zoom["camera_distance"] < 4.0, zoom
    orbit = await state(22, "whitebox_orbit_right")
    assert orbit["orbit"] < -0.45, orbit
    await state(15, "whitebox_tilt_down")
    closeup = await step(32, screenshot=True)
    assert closeup["state"]["camera_pitch"] < -0.68, closeup
    log = (ROOT / ".runtime" / "rogue-mcp" / identity / "godot.log").read_text(encoding="utf-8")
    assert "ERROR:" not in log, log
    return {"overview": overview["screenshot"], "material": closeup["screenshot"], "log": overview["log"]}


async def main():
    params = StdioServerParameters(command=sys.executable, cwd=str(ROOT), args=[
        str(ROOT / "mcp/game/server.py"), "--service", "input", "--expected-project-root", str(ROOT),
    ])
    async with stdio_client(params) as (reader, writer):
        async with ClientSession(reader, writer, read_timeout_seconds=timedelta(seconds=90)) as client:
            await client.initialize()
            host = data(await client.call_tool("on", {"scene": "whitebox", "screenshot": False}))
            try:
                report = await exercise(client, host["session_id"])
                print(json.dumps(report, ensure_ascii=False, indent=2))
            finally:
                data(await client.call_tool("close", {"session_id": host["session_id"]}))


if __name__ == "__main__":
    asyncio.run(main())
