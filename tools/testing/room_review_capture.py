"""Capture each Night Watch blockout in the real Forward+ game MCP."""
import argparse
import asyncio
from datetime import timedelta
import json
from pathlib import Path
import shutil
import sys

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from PIL import Image, ImageDraw, ImageFont

from rogue_smoke import ROOT, data

ORDER = ("intake", "returns", "exchange", "wash", "lift", "airlock", "shutter", "hall", "darkroom", "relay", "meridian")


def contact_sheet(records, view, output):
    width, height = 412, 232
    gap, pad, caption = 10, 16, 26
    rows = (len(records) + 2) // 3
    board = Image.new("RGB", (pad * 2 + 3 * width + 2 * gap, pad * 2 + rows * (height + caption + gap)), "#142431")
    draw = ImageDraw.Draw(board)
    font = ImageFont.load_default(size=16)
    for i, record in enumerate(records):
        left = pad + (i % 3) * (width + gap)
        top = pad + (i // 3) * (height + caption + gap)
        with Image.open(output / record[view]) as shot:
            board.paste(shot.resize((width, height), Image.Resampling.LANCZOS), (left, top))
        draw.text((left, top + height + 3), f"{i + 1:02d}  {record['name']}", fill="#f0e5d2", font=font)
    path = output / f"all-{view}.png"
    board.save(path)
    return str(path)


async def review(session, identity, output):
    async def step(action=None, frames=6, screenshot=False):
        args = dict(session_id=identity, frames=frames, screenshot=screenshot, operation="wait")
        if action:
            args.update(operation="action", action=action)
        return data(await session.call_tool("step", args))

    def save(result, stem):
        assert result["renderer"] == "forward_plus", result
        name = stem + ".png"
        shutil.copyfile(result["screenshot"], output / name)
        return name

    # Use input, not teleportation, to walk through the first actual portal and advance.
    assert (await step("review_use_threshold"))["state"]["stage"] == "intake"
    initial = await step("move_up", 110)
    assert initial["state"]["position"][2] < -1.8, initial
    for _ in range(9):
        current = (await step(frames=10))["state"]
        if current["near_finish"]:
            break
        direction = "move_up" if current["position"][2] > -7.35 else "move_down"
        await step(direction, 13)
    assert current["near_finish"], current
    assert (await step("review_use_threshold"))["state"]["stage"] == "returns"
    assert (await step("review_previous"))["state"]["stage"] == "intake"

    records = []
    for index, stage in enumerate(ORDER, 1):
        if index > 1:
            await step("review_next")
        walk = await step(frames=33, screenshot=True)
        state = walk["state"]
        assert state["stage"] == stage and state["index"] == index and state["count"] == len(ORDER), state
        assert state["grounded"] and state["view"] == "walk" and not state["near_finish"], state
        name = f"{index:02d}-{stage}"
        record = {"name": state["name"], "stage": stage, "fixtures": state["fixtures"], "alternate": state["alternate"]}
        record["walk"] = save(walk, f"{name}-walk")
        # Actual input moves each room's player; reset before photographing the plan.
        walked = (await step("move_up", 20))["state"]
        assert walked["position"][2] < state["position"][2] - 0.8, walked
        await step("whitebox_reset")
        await step("review_plan")
        plan = await step(frames=32, screenshot=True)
        assert plan["state"]["view"] == "plan", plan["state"]
        record["plan"] = save(plan, f"{name}-plan")
        records.append(record)
        print(f"{index:02d} {stage}: walk + plan", flush=True)
        await step("review_plan")
    for _ in range(2):
        await step("move_up", 74)
    for _ in range(9):
        bell = (await step(frames=10))["state"]
        if bell["near_finish"]:
            break
        direction = "move_up" if bell["position"][2] > -4.37 else "move_down"
        await step(direction, 9)
    assert bell["near_finish"], bell
    assert (await step("review_use_threshold"))["state"]["finished"]
    assert not (await step("whitebox_reset"))["state"]["finished"]
    log = Path(plan["log"])
    contents = log.read_text(encoding="utf-8")
    assert "ERROR:" not in contents, contents
    summary = {"rooms": records, "walk_sheet": contact_sheet(records, "walk", output),
               "plan_sheet": contact_sheet(records, "plan", output), "godot_log": str(log)}
    (output / "report.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"PASS: {len(records)} rooms, {2 * len(records)} real Forward+ views. {output}")


async def main(output):
    output.mkdir(parents=True, exist_ok=True)
    params = StdioServerParameters(command=sys.executable, cwd=str(ROOT), args=[
        str(ROOT / "mcp/game/server.py"), "--service", "input", "--expected-project-root", str(ROOT),
    ])
    async with stdio_client(params) as (reader, writer):
        async with ClientSession(reader, writer, read_timeout_seconds=timedelta(seconds=90)) as session:
            await session.initialize()
            started = data(await session.call_tool("on", {"scene": "room_review", "screenshot": False}))
            try:
                await review(session, started["session_id"], output)
            finally:
                data(await session.call_tool("close", {"session_id": started["session_id"]}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / ".runtime" / "room-review")
    asyncio.run(main(parser.parse_args().output.resolve()))
