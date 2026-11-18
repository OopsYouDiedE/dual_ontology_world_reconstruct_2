"""Walk the generated hot kitchen and operate its three fixtures through the game MCP."""
import asyncio
import json
import math
import sys
from datetime import timedelta

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from rogue_run_e2e import Expedition, check, next_room
from rogue_smoke import ROOT, data


def player(run):
    return run.state["player_observation"]


async def walk(run, x, z):
    for _ in range(18):
        px, py, pz = player(run)["position"]
        check(abs(py) < 0.1, f"Fell off the kitchen floor at {px,py,pz}")
        dx, dz = x - px, z - pz
        if max(abs(dx), abs(dz)) < 0.18:
            return
        if abs(dx) > abs(dz):
            action, distance = ("move_right" if dx > 0 else "move_left"), abs(dx)
        else:
            action, distance = ("move_down" if dz > 0 else "move_up"), abs(dz)
        await run.step(f"walk to {x,z}", operation="action", action=action,
                       frames=max(2, min(36, round(distance * 20))))
    raise RuntimeError(f"Could not walk to {x,z}; last player state: {player(run)}")


async def operate(run, fixture, closed):
    state = player(run)
    target = next(t for t in state["targets"] if t.get("id") == fixture)
    check(state["available_interact"] and state["prompt"].endswith(target["label"]), state)
    await run.step(f"operate {fixture}", operation="action", action="interact", frames=1)
    for _ in range(5):
        await run.step(f"settle {fixture}", operation="wait", frames=24)
        if player(run)["fixtures"][fixture] == closed and not player(run)["fixtures_moving"]:
            return
    raise RuntimeError(f"Fixture {fixture} did not settle; {player(run)}")


async def regression():
    params = StdioServerParameters(command=sys.executable, cwd=str(ROOT), args=[
        "-B", str(ROOT / "mcp/game/server.py"), "--service", "input", "--expected-project-root", str(ROOT)])
    async with stdio_client(params) as (reader, writer):
        async with ClientSession(reader, writer, read_timeout_seconds=timedelta(seconds=120)) as client:
            await client.initialize()
            opened = data(await client.call_tool("on", {"seed": 1}))
            try:
                run = Expedition(client, opened)
                graph = {}
                for _ in range(100):
                    if run.state.get("template") == "kitchen":
                        break
                    if run.doors():
                        await run.move(next_room(graph, run.state["room"], run.doors()))
                    else:
                        await run.resolve()
                check(run.state.get("template") == "kitchen", "Seed 1 did not reach the kitchen")
                await run.step("settle entrance", operation="wait", frames=72)
                entrance = await run.capture("kitchen entrance")
                check(player(run)["grounded"], "Kitchen spawn is not grounded")
                check(player(run)["available_interact"], "Notebook must be reachable from the entrance")
                await run.step("inspect notebook", operation="action", action="interact", frames=1)
                await run.step("finish inspection gesture", operation="wait", frames=60)
                check(not any(t["kind"] == "inspect" for t in player(run)["targets"]), "Notebook did not inspect")
                await walk(run, 2.0, 4.15)
                await operate(run, "oven", True)
                await run.capture("oven closed")
                await operate(run, "oven", False)
                await walk(run, 6.35, 4.15)
                await walk(run, 6.35, 1.15)
                await walk(run, 3.4, 1.15)
                await operate(run, "hatch", True)
                await run.capture("shutter closed")
                await operate(run, "hatch", False)
                await walk(run, 6.35, 1.15)
                await walk(run, 6.35, -1.35)
                before = player(run)["position"]
                cold_open = await run.capture("cold door open from passage")
                await operate(run, "cold-door", True)
                cold_closed = await run.capture("cold door closed from passage")
                check(math.dist(before, player(run)["position"]) < 0.05, "Door operation displaced the player")
                await run.step("closed threshold blocks movement", operation="action", action="move_up", frames=35)
                check(player(run)["position"][2] > -2, "Player crossed the closed cold door")
                await walk(run, 6.35, -1.35)
                await operate(run, "cold-door", False)
                await walk(run, 6.4, -3.65)
                await run.capture("walked through open door into cold store")
                return {"passed": True, "entrance": entrance["screenshot"],
                        "cold_open": cold_open["screenshot"], "cold_closed": cold_closed["screenshot"],
                        "trace": str(run.artifacts / "regression.json")}
            finally:
                await client.call_tool("close", {"session_id": opened["session_id"]})


if __name__ == "__main__":
    print(json.dumps(asyncio.run(regression()), indent=2))
