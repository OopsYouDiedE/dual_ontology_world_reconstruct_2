"""Exercise R-05's embedded Blender action with the project's real Forward+ MCP."""
import asyncio
import json
import math
from datetime import timedelta
from pathlib import Path
import sys

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

ROOT = Path(__file__).resolve().parents[2]
SCENE = "res://scenes/character_review/R05NativeMotion.tscn"
MODEL = "res://assets/characters/mpfb/r05_styled.glb"
CLIP = "MPFB_Pose_Check"


def rotation_delta(a, b):
    assert len(a) == len(b) == 4
    return 2 * math.acos(min(1.0, abs(sum(x * y for x, y in zip(a, b)))))


async def verify():
    params = StdioServerParameters(command=sys.executable, cwd=str(ROOT), args=[
        "-B", str(ROOT / "mcp/game/server.py"), "--service", "input", "--expected-project-root", str(ROOT),
    ])
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write, read_timeout_seconds=timedelta(seconds=90)) as client:
            await client.initialize()

            async def call(tool, **args):
                result = await client.call_tool(tool, args)
                text = next(part.text for part in result.content if part.type == "text")
                if result.isError:
                    raise RuntimeError(text)
                return result.structuredContent or json.loads(text)

            initial = await call("on", scene="r05_native_motion", screenshot=False)
            sid = initial["session_id"]
            try:
                state = initial.get("state", {})
                assert initial["scene"] == SCENE and initial["renderer"] == "forward_plus", initial
                assert state.get("ready") and state["model"] == MODEL, initial
                assert state["clips"] == [CLIP] and state["bones"] == 53, state
                assert state["rig_path"] and abs(state["length"] - 3.0) < 0.06, state
                assert state["playing"], state  # Opens already playing the imported action.
                x, y = state["replay_center"]
                neutral = await call("step", session_id=sid, operation="click", x=x, y=y)
                state = neutral["state"]
                assert state["playing"] and state["seconds"] < 0.25, state
                reach = await call("step", session_id=sid, operation="wait", frames=38)
                assert reach["state"]["seconds"] > state["seconds"], reach
                elbow = rotation_delta(state["right_elbow"], reach["state"]["right_elbow"])
                assert elbow > math.radians(20), reach
                step = await call("step", session_id=sid, operation="wait", frames=78)
                knee = rotation_delta(state["right_knee"], step["state"]["right_knee"])
                assert knee > math.radians(18), step
                end = await call("step", session_id=sid, operation="wait", frames=104, screenshot=False)
                assert end["state"]["finished"] and not end["state"]["playing"], end
                restarted = await call("step", session_id=sid, operation="click", x=x, y=y, screenshot=False)
                assert restarted["state"]["playing"] and not restarted["state"]["finished"], restarted
                print(json.dumps({
                    "status": "R05_NATIVE_MOTION_PASS", "renderer": initial["renderer"],
                    "duration_seconds": state["length"], "bone_count": state["bones"],
                    "elbow_delta_degrees": round(math.degrees(elbow), 2),
                    "knee_delta_degrees": round(math.degrees(knee), 2),
                    "screenshots": [neutral["screenshot"], reach["screenshot"], step["screenshot"]],
                    "log": initial["log"],
                }, indent=2))
            finally:
                await call("close", session_id=sid)


if __name__ == "__main__":
    asyncio.run(verify())
