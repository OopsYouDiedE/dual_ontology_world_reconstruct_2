"""B01 · The Thirteenth Tread — core feasibility model (design aid, not the room judge).

The one coupling that makes or breaks the room:
    companion watch W  - proper time, slowed inside the lag field around the pendulum bob
    hall count H       - escape-wheel marks; beat length grows with pendulum amplitude A
The companion (Cobalt card) brakes the wheel at the start of their own 12th watch mark. The
Lantern only opens if the hall is then inside its own 12th mark: gap G = W - H in (-1, 0].

Levers the captain has, both directions:
    G down  - park the companion in the lag niche (watch slows; their drag also lowers A)
    G up    - keep them out of the field and push the bob at its turnaround (A up, hall slows)
    veto    - watch the companion at the brake (Cobalt C-2 freezes them): skip a bad hour
    drop    - a wrong-hour brake: the run-on skips a hall mark, throws the red-tread rider and
              strikes dawn one hour early, so blind retries cannot ratchet G into the window
The field centre rides a chaotic secondary arm (logistic map per beat), so exposure can only
be steered by feedback, never computed in advance.

    python -I tools/b_series/b01_core_sim.py [--seeds 120] [--out .runtime/b-series/b01-core.json]
"""
from __future__ import annotations

import argparse
import json
import math
import random
from dataclasses import dataclass, field
from pathlib import Path

DT = 0.1                  # s
WATCH_MARK = 20.0         # s of proper time per watch mark
BEATS_PER_MARK = 5
CLIMB = 40.0              # s, niche -> service stair -> brake gallery
WALK_IN = 10.0            # s, entry -> lag niche
DEADLINE_MARKS = 36       # three hall hours, then dawn retracts the treads
NICHE = (8.0, 2.2)        # lag niche, two-thirds along the east sweep, beside the bob's path
IMPULSE = 0.05            # escapement energy per beat (amplitude units)
KICK = 0.05               # captain's push at the turnaround
FIELD_RADIUS = 7.5        # x amplitude
FIELD_DEPTH = 0.88        # watch rate at the bob centre = 1 - depth
WINDOW = 0.6              # hall marks: the red tread sits within run-on reach only in the last 3 beats of mark 12
TARGET_G = -1.0 + WINDOW / 2.0   # centre of the success window (-1, -1 + WINDOW]


def beat_length(a: float) -> float:
    """Deliberately non-isochronous regulator (mis-set cycloidal cheeks): wide swings beat slowly."""
    return 3.6 * (1.0 + 0.45 * a * a)


def outside_drift(a: float) -> float:
    """dG/dt with the companion outside the field, marks per second."""
    return 1.0 / WATCH_MARK - 1.0 / (BEATS_PER_MARK * beat_length(a))


@dataclass
class Seed:
    a0: float
    c: float
    w0: float
    e0: float
    kd: float

    @staticmethod
    def draw(rng: random.Random) -> "Seed":
        return Seed(a0=rng.uniform(0.62, 1.0), c=rng.uniform(0.050, 0.068), w0=rng.uniform(-2.4, 2.6),
                    e0=rng.uniform(0.05, 0.95), kd=rng.uniform(0.018, 0.028))


@dataclass
class World:
    seed: Seed
    t: float = 0.0
    a: float = 0.0
    phi: float = 0.0
    h: float = 0.0             # hall marks elapsed (+1/5 per beat)
    w: float = 0.0             # companion watch marks elapsed
    e: float = 0.5             # chaotic secondary arm
    beats: int = 0
    beat_drag: float = 0.0
    running: bool = True
    hold_beats: int = 0
    brake_mark: float = 0.0
    where: str = "walk"        # walk | niche | climb | gallery | back
    timer: float = WALK_IN
    gaze: bool = False         # captain watching the companion (Cobalt C-2: they freeze)
    kicked_beat: int = -1
    attempts: list = field(default_factory=list)
    won: bool = False
    hp_lost: int = 0
    vetoes: int = 0
    kicks: int = 0
    deadline: float = DEADLINE_MARKS

    def __post_init__(self) -> None:
        self.a, self.w, self.e = self.seed.a0, self.seed.w0, self.seed.e0

    def gap(self) -> float:
        return self.w - self.h

    def to_brake(self) -> float:
        """Proper seconds until the companion's next 12th watch mark begins."""
        return ((11.0 - self.w % 12.0) % 12.0) * WATCH_MARK

    def can_kick(self) -> bool:
        return self.running and self.h % 12.0 < 5.0 and self.kicked_beat != self.beats

    def kick(self) -> None:
        if self.can_kick():
            self.a = min(1.1, self.a + KICK)
            self.kicked_beat = self.beats
            self.kicks += 1

    def order(self, place: str) -> None:
        """Hale-style order; the companion only moves while unobserved, which the model folds into the timer."""
        if place == "gallery" and self.where in ("niche", "walk"):
            self.where, self.timer = "climb", CLIMB
        elif place == "niche" and self.where == "gallery":
            self.where, self.timer = "back", CLIMB

    def field_rate(self) -> float:
        if self.where != "niche":
            return 1.0
        xb = 18.0 * math.sin(self.a) * math.sin(self.phi)
        radius = FIELD_RADIUS * self.a * (0.7 + 0.4 * self.e)
        d = math.hypot(NICHE[0] - xb, NICHE[1])
        return 1.0 - FIELD_DEPTH * max(0.0, 1.0 - (d / radius) ** 2)

    def step(self) -> None:
        r = self.field_rate()
        before = self.w
        self.w += r * DT / WATCH_MARK
        self.beat_drag += (1.0 - r) * DT
        old = self.phi
        self.phi += math.pi / beat_length(self.a) * DT
        if math.floor(self.phi / math.pi) != math.floor(old / math.pi):
            self._beat()
        self.t += DT
        if self.where in ("walk", "climb", "back"):
            self.timer -= DT
            if self.timer <= 0:
                self.where = {"walk": "niche", "climb": "gallery", "back": "niche"}[self.where]
        crossed = math.floor((before - 11.0) / 12.0) != math.floor((self.w - 11.0) / 12.0)
        if crossed and self.where == "gallery" and self.running:
            if self.gaze:
                self.vetoes += 1
            else:
                self._brake()

    def _beat(self) -> None:
        s = self.seed
        self.beats += 1
        self.e = 3.93 * self.e * (1.0 - self.e)
        if self.running:
            self.h += 1.0 / BEATS_PER_MARK
            self.a += IMPULSE - s.c * self.a - s.kd * self.beat_drag
        else:
            self.a -= s.c * self.a
            self.hold_beats += 1
            if self.hold_beats >= 2:                      # bob out and back once
                self._release()
        self.a = min(1.1, max(0.25, self.a))
        self.beat_drag = 0.0

    def _brake(self) -> None:
        self.running, self.hold_beats, self.brake_mark = False, 0, self.h % 12.0

    def _release(self) -> None:
        self.running = True
        ok = 12.0 - WINDOW <= self.brake_mark < 12.0
        self.attempts.append({"t": round(self.t, 1), "hall_mark": round(self.brake_mark + 1, 2), "ok": ok})
        if ok:
            self.won = True
        else:
            self.h += 1.0                                  # the run-on skips a hall mark
            self.hp_lost += 1                              # whoever rides the red tread is thrown
            self.deadline -= 12.0                          # a stopped wheel strikes dawn one hour early


def run(seed: Seed, policy) -> World:
    world = World(seed)
    while not world.won and world.h < world.deadline:
        policy(world)
        world.step()
    return world


# ----------------------------------------------------------------- policies
def obey_ivory(world: World) -> None:
    """Ivory I-2, keep the companion in sight: C-2 holds them at the door for the whole hour."""
    world.where, world.timer, world.gaze = "walk", 1e9, True


def straight_up(world: World) -> None:
    """No field, no kicks: send the companion to the brake at once."""
    world.order("gallery")


def tape(exit_time: float):
    """Open-loop: leave the niche at one fixed clock time."""
    def policy(world: World) -> None:
        if world.where == "niche" and exit_time <= world.t:
            world.order("gallery")
    return policy


def make_feedback(noise: random.Random, margin: float = 0.0):
    """A careful player. Observes the dial, the companion's spoken count / watch face, the bob's
    swing. Extrapolates the out-of-field drift from the amplitude in view (noisy), keeps a margin,
    and re-decides every tick. No access to the seed or to the chaotic arm's future."""
    target = TARGET_G + margin

    def predicted(world: World, a_guess: float) -> float:
        return world.gap() + noise.gauss(0.0, 0.05) + outside_drift(a_guess) * world.to_brake()

    def policy(world: World) -> None:
        a_seen = world.a + noise.gauss(0.0, 0.03)
        a_back = 0.5 * (a_seen + IMPULSE / world.seed.c)   # amplitude recovers once the drag leaves
        world.gaze = False
        if world.where in ("walk", "niche"):
            pred = predicted(world, a_back)
            if world.to_brake() >= CLIMB + 2.0 and pred <= target:
                world.order("gallery")                     # enough lag: climb now
        elif world.where in ("climb", "gallery"):
            pred = predicted(world, a_seen)
            if pred < target - 0.05:
                world.kick()                               # watch behind: slow the hall
            if world.where == "gallery" and pred > target + 0.3 and world.to_brake() > 2 * CLIMB + 10.0:
                world.order("niche")                       # still ahead with time to spare: more field
            if world.where == "gallery" and world.to_brake() < 2.0:
                world.gaze = not (-0.98 < pred <= -1.02 + WINDOW)   # veto a bad hour rather than drop
    return policy


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seeds", type=int, default=120)
    parser.add_argument("--out", default=".runtime/b-series/b01-core.json")
    args = parser.parse_args()
    rng = random.Random(20261125)
    seeds = [Seed.draw(rng) for _ in range(args.seeds)]

    def summary(worlds: list[World]) -> dict:
        won = [w for w in worlds if w.won]
        return {"win_rate": round(len(won) / len(worlds), 3),
                "first_attempt": round(sum(1 for w in won if len(w.attempts) == 1) / len(worlds), 3),
                "median_win_s": round(sorted(w.t for w in won)[len(won) // 2], 1) if won else None,
                "mean_hp_lost": round(sum(w.hp_lost for w in worlds) / len(worlds), 2)}

    reference = [run(s, make_feedback(random.Random(i))) for i, s in enumerate(seeds)]
    lost = [s for s, w in zip(seeds, reference) if not w.won]
    rescued = sum(1 for s in lost if any(run(s, make_feedback(random.Random(7), m)).won
                                         for m in (-0.3, -0.15, 0.15, 0.3)))
    half = len(seeds) // 2
    exits = range(int(WALK_IN), 360, 3)
    train = {k: sum(run(s, tape(float(k))).won for s in seeds[:half]) / half for k in exits}
    best = max(train, key=train.get)
    test = sum(run(s, tape(float(best))).won for s in seeds[half:]) / (len(seeds) - half)
    up = [w for w, s in zip(reference, seeds) if s.w0 < 0.0]

    report = {
        "seeds": len(seeds),
        "obey_ivory": summary([run(s, obey_ivory) for s in seeds]),
        "straight_up": summary([run(s, straight_up) for s in seeds]),
        "reference_player": summary(reference),
        "reference_player_kicks_used_on_watch_behind_seeds": round(sum(w.kicks > 0 for w in up) / max(1, len(up)), 3),
        "reference_player_vetoes_mean": round(sum(w.vetoes for w in reference) / len(reference), 2),
        "reference_losses": len(lost),
        "losses_rescued_by_other_margin": rescued,
        "best_single_tape": {"exit_s": best, "train": round(train[best], 3), "held_out": round(test, 3)},
    }
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
