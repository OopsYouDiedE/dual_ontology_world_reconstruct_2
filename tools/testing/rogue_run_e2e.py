"""Real Forward+ Rogue Run regression over the project's stdio MCP."""
import argparse
import asyncio
from collections import deque
from datetime import timedelta
import json
from pathlib import Path
from hashlib import sha256
import sys

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from PIL import Image
from rogue_smoke import ROOT, data


RENDERER = "forward_plus"
SCENE = "res://scenes/rogue/Run.tscn"
RESET_FIELDS = ("room", "camp", "goal", "phase", "health", "moves", "roster", "party", "journal", "exits", "recruits")


def check(condition, message):
    if not condition:
        raise RuntimeError(message)


class Expedition:
    def __init__(self, client, initial):
        self.client = client
        self.session_id = initial["session_id"]
        self.pid = initial["pid"]
        self.artifacts = Path(initial["log"]).parent
        self.trace = []
        self.blueprints = {}
        self.record("initial", initial)
        self.record_blueprint(initial)
        self.visited = {self.state["room"]}

    def record(self, name, result):
        check(result["pid"] == self.pid and result["renderer"] == RENDERER and result["scene"] == SCENE,
              f"Wrong host, renderer or scene at {name}: {result}")
        state = result.get("state")
        check(isinstance(state, dict) and "buttons" in state, f"mcp_observe state missing at {name}; see {result['log']}")
        self.state = state
        self.viewport = result["viewport_size"]
        self.trace.append({"event": name, "state": state, "screenshot": result.get("screenshot")})
        (self.artifacts / "regression.json").write_text(json.dumps(self.trace, indent=2), encoding="utf-8")

    async def step(self, name, **args):
        result = data(await self.client.call_tool("step", {"session_id": self.session_id,
            "screenshot": False, **args}))
        self.record(name, result)
        return result

    async def click(self, label, *, destination=None, screenshot=False):
        buttons = [b for b in self.state["buttons"] if b["label"] == label
                   and (destination is None or b.get("destination") == destination)]
        check(len(buttons) == 1, f"Expected one visible button {label!r}: {self.state}")
        button = buttons[0]
        x, y = button["x"], button["y"]
        if not (0 <= x < self.viewport[0] and 0 <= y < self.viewport[1]):
            await self.capture("off-screen button")
            raise RuntimeError(f"Button outside {self.viewport} in {self.state['room']}: {button}; "
                               f"evidence: {self.artifacts / 'regression.json'}")
        return await self.step(f"click {label} @ ({x:g}, {y:g})", operation="click",
                               x=x, y=y, screenshot=screenshot)

    async def capture(self, name):
        result = data(await self.client.call_tool("observe", {"session_id": self.session_id, "screenshot": True}))
        check(result.get("screenshot"), f"Missing screenshot for {name}")
        self.record(name, result)
        return result

    def record_blueprint(self, result):
        state = result["state"]
        template = state.get("template")
        check(state.get("presentation") == "blueprint" and template,
              f"Expected a blueprint on first room frame: {state}")
        if template not in self.blueprints:
            path = result.get("screenshot")
            check(path, f"Missing first-frame screenshot for {template}")
            with Image.open(path) as image:
                # Compare room interiors, excluding title, top HUD and bottom buttons.
                w, h = image.size
                crop = image.crop((w // 4, h // 4, 3 * w // 4, 3 * h // 4)).convert("RGB")
                digest = sha256(crop.tobytes()).hexdigest()
            self.blueprints[template] = {"screenshot": path, "room_crop_sha256": digest}

    def doors(self):
        doors = {}
        for room in self.state["exits"]:
            matches = [b["label"] for b in self.state["buttons"] if b.get("destination") == room]
            check(len(matches) == 1, f"Live exit {room!r} has no unique clickable destination: {self.state['buttons']}")
            doors[room] = matches[0]
        return doors

    async def move(self, room):
        previous = self.state
        result = await self.click(self.doors()[room], destination=room, screenshot=room not in self.visited)
        check(self.state["room"] == room and self.state["moves"] == previous["moves"] + 1,
              f"Door to {room} did not advance exactly one move: {self.state}")
        check(self.state["journal"] == previous["journal"], "Travel changed the journal")
        if room not in self.visited:
            self.record_blueprint(result)
            self.visited.add(room)

    async def resolve(self, *, wrong=False, assign=False):
        objective = self.state
        check(objective["prompt"].strip() and any(b["label"] == "Inspect room" for b in objective["buttons"])
              and not any(b["label"] in ANSWERS.values() for b in objective["buttons"]),
              f"New encounter should expose an inspection objective before puzzle choices: {objective}")
        await self.click("Inspect room")
        before = self.state
        for key in ("room", "moves", "health", "journal"):
            check(before[key] == objective[key], f"Inspection changed {key}")
        labels = [button["label"] for button in before["buttons"]]
        options = [label for label in labels if not label.startswith("Assign ")]
        safe = safe_option(before["prompt"], options)
        helpers = [label for label in labels if label.startswith("Assign ")]
        check(len(helpers) <= 1 and all(label[7:] in before["party"] for label in helpers),
              f"Invalid matching-companion choices: {helpers}")
        chosen = next(label for label in options if label != safe) if wrong else safe
        used_helper = bool(not wrong and assign and helpers)
        if used_helper:
            chosen = helpers[0]
        await self.click(chosen)
        after = self.state
        check(after["health"] == max(0, before["health"] - (3 if wrong else 0)),
              f"Wrong health change for {chosen!r} (safe: {safe!r}): {before['health']} → {after['health']}")
        if used_helper:
            check(chosen[7:] + " carries out your order" in after["prompt"],
                  f"Assign did not show companion feedback: {after['prompt']!r}")
        check(after["room"] == before["room"] and after["moves"] == before["moves"] and
              set(before["journal"]) <= set(after["journal"]) and after["journal"],
              f"Encounter should record learning in place: {after}")
        return used_helper


# Player-visible clue excerpts and their expected answers, independent of the
# game's shuffled option order and encounter seed implementation.
ANSWERS = {
    "steam reaches its spout": "Use the kettle whistle",
    "wall anchor stays still": "Brace the chain at its wall anchor",
    "fresh ring of soot": "Check the burner with the soot ring",
    "taps the tray in time": "Signal with the chalk on the tray",
    "blackboard stays aligned": "Align with the blackboard edge",
    "fresh chalk fills": "Copy the fresh chalk number",
    "order is clean dressing": "Set out a clean dressing first",
    "medical desk stays flush": "Take your bearing from the medical desk",
    "packet still has its seal": "Take the sealed dressing packet",
    "plate touches the counter on the second tap": "Collect the plate on the second tap",
    "serving counter stays square": "Cross beside the fixed serving counter",
    "wet plate ring": "Set the plate at the place with the drip trail",
    "second knock as the gauge settles": "Wait for the second knock at the return",
    "bracket bolted to the stone": "Mark the bolted pipe bracket",
    "wet line runs along the bypass": "Trace the wet bypass return",
    "cable stops rattling": "Cross when the food-lift cable falls quiet",
    "stays level with its mortar line": "Take your bearing from the stone landing",
    "leaves a tread mark": "Follow the flour tread on the stair",
    "left flight match the moving feet": "Take the flight whose steps match the feet",
    "gallery still meets the same wall corner": "Use the fixed gallery corner",
    "fresh scuffs leading up": "Follow the freshly scuffed treads",
    "as the last tally arrives": "Reconcile when the fourth tally arrives",
    "centered on the same floor joint": "Meet at the table over the floor joint",
    "match the amended total": "Use the correction backed by the slip",
}


def safe_option(prompt, options):
    matches = [label for clue, label in ANSWERS.items() if clue in prompt.casefold()]
    check(len(options) == 3 and len(set(options)) == 3 and len(matches) == 1 and matches[0] in options,
          f"Could not solve visible clue {prompt!r} against three choices: {options}")
    return matches[0]


def first_hop(graph, start, targets):
    queue = deque((room, room) for room in graph[start])
    seen = {start}
    while queue:
        room, hop = queue.popleft()
        if room in seen:
            continue
        seen.add(room)
        if room in targets:
            return hop
        queue.extend((other, hop) for other in graph.get(room, ()) if other not in seen)
    return None


def next_room(graph, room, doors, target=None):
    graph[room] = tuple(doors)
    frontier = {neighbor for links in graph.values() for neighbor in links if neighbor not in graph}
    hop = (first_hop(graph, room, {target}) if target and target != room else None)
    hop = hop or first_hop(graph, room, frontier)
    check(hop is not None, f"No reachable objective or unexplored exit from {room}")
    return hop


async def reach_camp(run):
    start_health = run.state["health"]
    graph = {}
    injured = False
    recruits_met = set()
    for _ in range(180):
        state = run.state
        if state["phase"] == "camp":
            check(injured and state["room"] == state["camp"] and state["health"] == start_health
                  and state["roster"], f"Camp should heal and offer a roster: {state}")
            check(recruits_met == set(state["recruits"]), f"Approach missed recruit rooms: {state['recruits']}")
            await run.capture("camp healed approach damage")
            return graph
        check(state["phase"] == "approach", f"Unexpected approach phase: {state}")
        doors = run.doors()
        if doors:
            hop = next_room(graph, state["room"], doors, state["camp"])
            await run.move(hop)
            if hop in state["recruits"] and hop not in recruits_met:
                new_names = set(run.state["roster"]) - set(state["roster"])
                check(len(new_names) == 1 and new_names <= set(run.state["party"]),
                      f"Entering recruit room {hop} did not add its companion to the active team")
                recruits_met.add(hop)
        else:
            await run.resolve(wrong=not injured)
            injured = True
    raise RuntimeError("Approach exploration budget exhausted")


async def select_party(run):
    await run.capture("camp roster")
    roster = run.state["roster"][:]
    target = min(3, len(roster))
    check(target >= 2, f"Need at least two selectable companions, got {roster}")
    for member in run.state["party"][:]:
        before = run.state["party"][:]
        await run.click("Drop " + member)
        check(run.state["party"] == [name for name in before if name != member], "Drop changed the wrong slot")
    check(not run.state["party"], "Expected solo selection after dropping everybody")
    await run.capture("solo selection")
    for member in roster[:target]:
        before = run.state["party"][:]
        await run.click("Add " + member)
        check(run.state["party"] == before + [member] and run.state["roster"] == roster,
              "Add should insert one roster member into the party")
    check(len(run.state["party"]) == target, "Party size did not reach the allowed roster limit")
    if target == 3:
        check(not any(b["label"].startswith("Add ") for b in run.state["buttons"]),
              "Camp offered an extra slot for a fourth companion")
    await run.capture(f"selected {target} companions")


async def check_guide(run):
    before = run.state
    await run.click("Field guide")
    after = run.state
    for key in ("health", "moves", "party", "journal", "phase", "room"):
        check(after[key] == before[key], f"Reading field guide changed {key}")
    check(all(rule in after["prompt"] for rule in before["journal"]), "Guide omitted recorded rules")
    await run.click("Close guide")
    check(run.state["exits"] == before["exits"], "Closing guide changed available exits")


async def win(run, graph):
    assigned = False
    departure_party = run.state["party"][:]
    await check_guide(run)
    for _ in range(200):
        state = run.state
        check(state["phase"] in ("camp", "expedition"), f"Unexpected expedition phase: {state}")
        check(state["party"] == departure_party, f"Selected party changed outside recruitment: {state}")
        if "Wake the house" in [b["label"] for b in state["buttons"]]:
            check(state["room"] == state["goal"] and len(set(state["journal"])) >= 3,
                  f"Wake available before meeting goal requirements: {state}")
            await run.capture("goal ready: three distinct rules")
            await run.click("Wake the house")
            check(run.state["phase"] == "won" and run.state["health"] > 0, f"Wake did not win: {run.state}")
            await run.capture("victory")
            return assigned
        if state["room"] == state["goal"]:
            check(len(set(state["journal"])) < 3, "Wake missing at the goal with three learned rules")
        doors = run.doors()
        if doors:
            target = state["goal"] if len(set(state["journal"])) >= 3 else None
            await run.move(next_room(graph, state["room"], doors, target))
        else:
            used = await run.resolve(assign=not assigned)
            if used:
                await run.capture("matching companion assigned")
            assigned |= used
    raise RuntimeError("Expedition exploration budget exhausted")


async def lose(run):
    graph = {}
    for errors in range(1, 4):
        for _ in range(100):
            doors = run.doors()
            if not doors:
                break
            # Stay before camp so the three mistakes are not separated by a rest.
            doors.pop(run.state["camp"], None)
            await run.move(next_room(graph, run.state["room"], doors))
        else:
            raise RuntimeError("Could not find an unresolved encounter for defeat")
        await run.resolve(wrong=True)
        actual_phase = "lost" if errors == 3 else "approach"
        check(run.state["phase"] == actual_phase and run.state["health"] == 9 - 3 * errors,
              f"Expected {actual_phase} after {errors} errors: {run.state}")
    await run.capture("defeat after three mistakes")


async def verify_movement(run, action):
    before = run.state
    initial = before.get("player_observation")
    check(isinstance(initial, dict), f"Missing player_observation: {before}")
    moving = await run.step("move in the foyer", operation="action", action=action, frames=18, screenshot=True)
    after = moving["state"]["player_observation"]
    check(after["position"] != initial["position"], f"Movement did not change the player position: {after}")
    check(moving.get("screenshot"), "Missing rendered movement screenshot")
    settled = await run.step("settled after movement", operation="wait", frames=24, screenshot=True)
    resting = settled["state"]["player_observation"]
    check(initial.get("animation") and resting.get("animation") == initial["animation"] and settled.get("screenshot"),
          f"Animation did not return to its initial state after release: {resting}")
    for key in ("room", "moves", "health", "journal"):
        check(run.state[key] == before[key], f"Local movement unexpectedly changed expedition {key}")


async def regression(seed, move_action):
    params = StdioServerParameters(command=sys.executable, cwd=str(ROOT),
        args=["-B", str(ROOT / "mcp/game/server.py"), "--service", "input", "--expected-project-root", str(ROOT)])
    async with stdio_client(params) as (reader, writer):
        async with ClientSession(reader, writer, read_timeout_seconds=timedelta(seconds=120)) as client:
            await client.initialize()
            ready = data(await client.call_tool("status", {}))
            check(ready["ready"], "; ".join(ready["reasons"]))
            opened = data(await client.call_tool("on", {"seed": seed}))
            try:
                run = Expedition(client, opened)
                initial = run.state
                check(all(key in initial for key in RESET_FIELDS), f"New Run MCP contract missing; see {opened['log']}")
                check(initial["seed"] == seed and initial["phase"] == "approach" and initial["health"] == 9
                      and initial["moves"] == 0 and not any(initial[k] for k in ("roster", "party", "journal"))
                      and run.doors(), f"Invalid initial expedition: {initial}; see {opened['log']}")
                await verify_movement(run, move_action)
                graph = await reach_camp(run)
                await select_party(run)
                selected = run.state["party"][:]
                assigned = await win(run, graph)
                won = run.state
                check(len(run.blueprints) >= 2 and len({e["room_crop_sha256"] for e in run.blueprints.values()}) >= 2,
                      f"Expected distinct rendered rooms from different templates: {run.blueprints}")
                await run.click("Replay seed")
                check(run.state["seed"] == seed and all(run.state[k] == initial[k] for k in RESET_FIELDS),
                      f"Same-seed replay did not restore the approach: {run.state}")
                await run.capture("same-seed replay")
                run.visited = {run.state["room"]}
                await lose(run)
                dead = run.state
                await run.click("New expedition")
                new = run.state
                check(all(new[k] == initial[k] for k in ("room", "phase", "health", "moves", "roster", "party", "journal"))
                      and run.doors(), f"New expedition not reset to playable approach: {new}")
                await run.capture("new expedition")
                return {"passed": True, "seed": seed, "victory_moves": won["moves"],
                        "learned_rules": len(won["journal"]), "party": selected, "assigned": assigned,
                        "death_moves": dead["moves"], "blueprints": run.blueprints, "new_seed": new["seed"],
                        "evidence": str(run.artifacts / "regression.json")}
            finally:
                data(await client.call_tool("close", {"session_id": opened["session_id"]}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--move-action", default="move_up", help="InputMap movement action for the foyer check")
    args = parser.parse_args()
    print(json.dumps(asyncio.run(regression(args.seed, args.move_action)), indent=2))
