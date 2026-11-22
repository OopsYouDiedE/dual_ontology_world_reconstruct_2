"""Versioned integer mechanics, independent of renderer, host RNG and wall time."""
from hashlib import sha256
import json
from math import isqrt

HZ = 60
DECISION_TICKS = 20
MAX_TICKS = 10_800
WITNESS_TICKS = MAX_TICKS * 45 // 100
MAX_PHASE_PERIOD = 36_000
TELEGRAPH_TICKS = 40
MIN_WINDOW = 60
RANGE = 10_000
REACH = 2_400
EYE = 1_560
CROUCH_EYE = 940
ACTOR_RADIUS = 230
RAY_UNIT = 1_000_000
MASK64 = (1 << 64) - 1

# Integral, frozen sine lookup; Q6 meters/meters, 1 degree increments.
_SIN = (
    0, 17452, 34899, 52336, 69756, 87156, 104528, 121869, 139173, 156434,
    173648, 190809, 207912, 224951, 241922, 258819, 275637, 292372, 309017, 325568,
    342020, 358368, 374607, 390731, 406737, 422618, 438371, 453990, 469472, 484810,
    500000, 515038, 529919, 544639, 559193, 573576, 587785, 601815, 615661, 629320,
    642788, 656059, 669131, 681998, 694658, 707107, 719340, 731354, 743145, 754710,
    766044, 777146, 788011, 798636, 809017, 819152, 829038, 838671, 848048, 857167,
    866025, 874620, 882948, 891007, 898794, 906308, 913545, 920505, 927184, 933580,
    939693, 945519, 951057, 956305, 961262, 965926, 970296, 974370, 978148, 981627,
    984808, 987688, 990268, 992546, 994522, 996195, 997564, 998630, 999391, 999848,
    1000000,
)


def sin(deg):
    deg %= 360
    if deg > 180:
        return -sin(deg - 180)
    return _SIN[min(deg, 180 - deg)]


def cos(deg):
    return sin(deg + 90)


def ray_dir(yaw, pitch):
    pitch_scale = cos(pitch)
    return (sin(yaw) * pitch_scale // RAY_UNIT, sin(pitch), cos(yaw) * pitch_scale // RAY_UNIT)


def dist2(a, b):
    return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2


def canonical(value):
    return json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(",", ":"), allow_nan=False)


def digest(value):
    return sha256(canonical(value).encode("ascii")).hexdigest()


class Rng:
    """SplitMix64 with rejection sampling and stable named stream derivation."""
    def __init__(self, seed, stream):
        self.state = int.from_bytes(sha256(f"rule-eval:v1:{seed}:{stream}".encode()).digest()[:8], "big")

    def next(self):
        self.state = (self.state + 0x9E3779B97F4A7C15) & MASK64
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK64
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK64
        return (z ^ (z >> 31)) & MASK64

    def randint(self, a, b):
        width = b - a + 1
        if not 0 < width <= 1 << 64:
            raise ValueError("invalid rng interval")
        limit = (1 << 64) - (1 << 64) % width
        while (pick := self.next()) >= limit:
            pass
        return a + pick % width

    def choice(self, values):
        return values[self.randint(0, len(values) - 1)]


def ray_box(origin, direction, bounds, limit=RANGE):
    """Integer slab intersection. Returns ceil entry distance in mm.

    Keep the fractions until every slab has been tested (thin or diagonal hits
    are robust across platforms). Direction components are Q6 integers.
    """
    lo_n, lo_d, hi_n, hi_d = 0, 1, limit, 1
    for o, d, (low, high) in zip(origin, direction, bounds):
        if d == 0:
            if not low <= o <= high:
                return None
            continue
        if d > 0:
            near, far = (low - o) * RAY_UNIT, (high - o) * RAY_UNIT
        else:
            d = -d
            near, far = (o - high) * RAY_UNIT, (o - low) * RAY_UNIT
        if near * lo_d > lo_n * d:
            lo_n, lo_d = near, d
        if far * hi_d < hi_n * d:
            hi_n, hi_d = far, d
        if lo_n * hi_d > hi_n * lo_d:
            return None
    return -(-lo_n // lo_d)


def movement(action):
    x, z = action["dir_vec"]
    # Rounded once into an integral mm/tick vector. Vectors are signed Q3 or cardinal.
    length = isqrt((x*x + z*z) * RAY_UNIT**2)
    if not length:
        return (0, 0)
    def component(axis):
        return (1 if axis >= 0 else -1) * ((abs(axis) * action["speed_ratio"] * RAY_UNIT + length//2) // length)
    return component(x), component(z)
