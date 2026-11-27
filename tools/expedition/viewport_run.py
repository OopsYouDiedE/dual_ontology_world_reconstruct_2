"""Replay a fixed expedition using only player inputs; keep an auditable frame manifest."""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[2]
from player_input import Player, Run

PLANS = {
    "returns": [(1, "Tie off"), (2, "Use the porter")],
    "exchange": [(2, "Separate the booths"), (2, "Use both booths")],
    "wash": [(0, "Pack the papers"), (2, "Wait out")],
    "lift": [(2, "Set the service brake"), (2, "Release the escape")],
    "airlock": [(2, "Pin the inner"), (2, "Pass one person")],
    "shutter": [(1, "Mute the repeated"), (1, "Wait for the bell")],
    "darkroom": [(1, "Close and rewind"), (1, "Make a dry")],
    "relay": [(2, "Separate the return"), (2, "Print independently")],
}


def play(seed, out, lane):
    out.mkdir(parents=True, exist_ok=True)
    run = Run(seed, scene_args=("--post-first-sortie",))
    evidence = []
    try:
        p = Player(run)
        p.ask("wait", frames=12)

        def frame(name):
            row = json.loads(run.request("observe", screenshot=True, timeout=60)[0])
            with Image.open(row["screenshot"]) as image:
                ImageOps.pad(image.convert("RGB"), (1080, 720), method=Image.Resampling.LANCZOS,
                             color="#151918").save(out / (name + ".jpg"), quality=92)
            keys = ("room", "stage", "phase", "health", "recalled", "route", "pack", "exits", "moves", "actions", "supplies", "seed")
            evidence.append(dict(file=name + ".jpg", renderer=row['renderer'], viewport=row['viewport_size'],
                                 state={k:row['state'][k] for k in keys}))
            (out / "frames.json").write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf8")

        assert p.state["room"] == "camp" and p.state["witness_count"] == 16
        frame("01-camp")
        p.button("Route chart")
        p.ask("wait", frames=5)
        frame("02-chart")
        p.button("Fold chart")
        # UI presents destinations in the solver's forward order; never pass a hidden room ID.
        p.button(p.state['buttons'][int(lane=='east')]['label'])
        returned = False
        for _ in range(10):
            stage = p.state["stage"]
            print(p.state["room"], stage, p.state["pack"], flush=True)
            if p.state["moves"] == 1:
                frame("03-first-room")
            if stage == "meridian":
                frame("05-observatory")
                plan = ([(0,"Seal the paper"),(2,"Pack: arrest"),(2,"Wind by hand")]
                        if lane == "east" else [(1,"Pack: fit felt"),(1,"File the party")])
                for station, action in plan:
                    p.act(station, action)
                assert p.state["phase"] == "won" and returned
                frame("06-complete")
                return
            if p.state["room"] not in p.state["cleared"]:
                for station, action in PLANS[stage]:
                    p.act(station, action)
            assert p.state["room"] in p.state["cleared"], p.state["prompt"]
            if stage == "shutter" and not returned:
                frame("04-return-junction")
                pack = dict(p.state['pack'])
                p.button("Return to camp")
                assert p.state['room']=='camp' and p.state['recalled'] and p.state['pack']==pack
                p.button("Return Junction")
                assert 'camp' not in p.state['exits'] and p.state['pack']==pack
                returned = True
                continue
            p.button(p.state['buttons'][0]['label'])
        raise AssertionError("Route did not terminate")
    finally:
        run.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seed', type=int, default=1)
    parser.add_argument('--lane', choices=['east', 'west'], default='east')
    parser.add_argument('--out', type=Path, default=ROOT / '.runtime/expedition-capture')
    args = parser.parse_args()
    play(args.seed, args.out, args.lane)
