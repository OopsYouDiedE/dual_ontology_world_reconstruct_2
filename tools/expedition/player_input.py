"""Drive the game input and room targets through the project MCP."""
from collections import deque
import json
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "mcp/game"))
from server import Run


class Player:
    def __init__(self, run, *, quiet=False):
        self.run = run
        self.quiet = quiet
        self.state = self.ask("observe")

    def ask(self, op, *, screenshot=False, **args):
        raw = self.run.request(op, screenshot=screenshot, timeout=40, **args)
        row = json.loads(raw[0]) if screenshot else raw
        if screenshot:
            print(f'{row["state"]["stage"]}: {row["screenshot"]}', flush=True)
        self.state = row["state"]
        return self.state

    def action(self, key, n=2):
        return self.ask("action", action=key, frames=n)

    def button(self, prefix):
        slots = [b for b in self.state["buttons"] if b["label"].startswith(prefix) and b["enabled"]]
        if not slots or slots[0]["y"] <= 0 or slots[0]["y"] >= 720:
            self.ask("wait", frames=5)
            slots = [b for b in self.state["buttons"] if b["label"].startswith(prefix) and b["enabled"]]
        if not slots:
            raise AssertionError(f'{prefix!r} not in {self.state["buttons"]}')
        b = slots[0]
        self.ask("click", x=b["x"], y=b["y"])

    def displacement(self, x, z):
        for _attempt in range(6):
            p = self.state["player_observation"]
            dx, dz = x - p["position"][0], z - p["position"][2]
            if math.hypot(dx, dz) <= .115:
                return
            yaw = p["yaw"]
            costs = {"move_right": dx * math.cos(yaw) - dz * math.sin(yaw),
                     "move_down": dx * math.sin(yaw) + dz * math.cos(yaw)}
            key = max(costs, key=lambda k: abs(costs[k]))
            amount = costs[key]
            if amount < 0:
                key = {"move_right": "move_left", "move_down": "move_up"}[key]
            self.action(key, max(2, min(23, round(abs(amount) * 20))))
        p = self.state["player_observation"]["position"]
        if math.hypot(x - p[0], z - p[2]) > .24:
            raise AssertionError(f"Blocked from {p} to {(x, z)} in {self.state['stage']}")

    def target(self, kind, index):
        p = self.state["player_observation"]
        for t in p["targets"]:
            if t["kind"] == kind and t.get("id", t.get("index")) == index:
                return t
        raise AssertionError(f"No {kind}/{index} in {self.state['stage']}")

    def approach(self, kind, id):
        for _ in range(4):
            self.ask("observe")
            desired = self.target(kind, id)
            obs = self.state["player_observation"]
            if obs["available_interact"] and obs["prompt"].endswith(" " + desired["label"]):
                self.action("interact")
                if kind == "exit" or self.state["modal"]:
                    return
            p = obs["position"]
            sx, sz = math.floor(p[0]), math.floor(p[2])
            tx, _, tz = desired["position"]
            if kind == "crossing":
                self.displacement(tx, tz)
                continue
            grid = {(x,z): e for x,z,e in self.state["walk_grid"]}
            start = (sx,sz)
            grid.setdefault(start, 15)
            parents = {start: None}
            queue = deque([start])
            while queue:
                x,z = queue.popleft()
                for d,(ax,az) in enumerate(((1,0),(0,1),(-1,0),(0,-1))):
                    nxt = (x+ax,z+az)
                    if grid[x,z] & (1 << d) and nxt in grid and nxt not in parents:
                        parents[nxt] = (x,z)
                        queue.append(nxt)
            best = min(parents, key=lambda a: math.hypot(tx-a[0]-.5,tz-a[1]-.5))
            path = []
            while parents[best] is not None:
                path.append(best)
                best = parents[best]
            for x,z in reversed(path):
                old_room = self.state["room"]
                self.displacement(x+.5, z+.5)
                if self.state["room"] != old_room:
                    return
            if math.hypot(tx-self.state['player_observation']['position'][0], tz-self.state['player_observation']['position'][2]) < .9:
                p = self.state['player_observation']['position']
                self.displacement((p[0]+tx)*.5, (p[2]+tz)*.5)
        raise AssertionError(f"Could not reach {kind}/{id} {desired['position']}: {self.state['player_observation']['prompt']}")

    def act(self, station, prefix):
        self.approach("crossing", station)
        self.button(prefix)
        while self.state["performing"]:
            self.ask("wait", frames=30)
