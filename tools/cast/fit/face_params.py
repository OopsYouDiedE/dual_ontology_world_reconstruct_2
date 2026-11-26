"""Landmark sets and face-shape parameters shared by the Blender fit and the Godot fit loop (no bpy)."""
# ------------------------------------------------------------------ MediaPipe face landmark sets
OVAL = [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377, 152,
        148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109]
EYES = [33, 7, 163, 144, 145, 153, 154, 155, 133, 246, 161, 160, 159, 158, 157, 173,
        263, 249, 390, 373, 374, 380, 381, 382, 362, 466, 388, 387, 386, 385, 384, 398]
BROWS = [70, 63, 105, 66, 107, 55, 65, 52, 53, 46, 300, 293, 334, 296, 336, 285, 295, 282, 283, 276]
NOSE = [1, 2, 98, 327, 168, 6, 197, 195, 5, 4, 48, 278, 129, 358, 64, 294]
LIPS = [61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291, 409, 270, 269, 267, 0, 37, 39, 40, 185,
        78, 95, 88, 178, 87, 14, 317, 402, 318, 324, 308, 415, 310, 311, 312, 13, 82, 81, 80, 191]
FACE = OVAL + EYES + BROWS + NOSE + LIPS
# Forehead points of the oval hide under hats and fringes in the paintings; trust them less.
FACE_W = {i: 0.35 for i in (10, 338, 297, 332, 284, 109, 67, 103, 54, 21, 251)}
EYE_L, EYE_R = [263, 362, 386, 374], [33, 133, 159, 145]


def sym(name):
    """Left/right target pair driven by one weight."""
    return [f"l-{name}", f"r-{name}"]


# Closed-loop face parameters: (positive targets, negative targets); weight v in [-FACE_LIMIT, FACE_LIMIT].
def pair(a, b, sided=False):
    return (sym(a) if sided else [a], sym(b) if sided else [b])


FACE_PARAMS = [
    pair("head-scale-horiz-incr", "head-scale-horiz-decr"), pair("head-invertedtriangular", "head-square"),
    pair("head-oval", "head-round"), pair("forehead-scale-vert-incr", "forehead-scale-vert-decr"),
    pair("chin-width-incr", "chin-width-decr"), pair("chin-height-incr", "chin-height-decr"),
    pair("cheek-bones-incr", "cheek-bones-decr", True),
    pair("eye-scale-incr", "eye-scale-decr", True), pair("eye-trans-up", "eye-trans-down", True),
    pair("eye-trans-out", "eye-trans-in", True), pair("eye-height2-incr", "eye-height2-decr", True),
    pair("eyebrows-trans-up", "eyebrows-trans-down"),
    pair("nose-scale-horiz-incr", "nose-scale-horiz-decr"), pair("nose-scale-vert-incr", "nose-scale-vert-decr"),
    pair("nose-trans-up", "nose-trans-down"),
    pair("mouth-scale-horiz-incr", "mouth-scale-horiz-decr"), pair("mouth-trans-up", "mouth-trans-down"),
    pair("mouth-upperlip-height-incr", "mouth-upperlip-height-decr"),
    # Outline freedom: jaw angle and drop, chin projection, temples, slimming of the cheeks only.
    pair("chin-jaw-drop-incr", "chin-jaw-drop-decr"), pair("chin-prominent-incr", "chin-prominent-decr"),
    pair("chin-bones-incr", "chin-bones-decr"), pair("forehead-temple-incr", "forehead-temple-decr"),
    pair("head-triangular", "head-diamond"), pair("cheek-inner-incr", "cheek-inner-decr", True),
    pair("eye-corner1-up", "eye-corner1-down", True), pair("eye-corner2-up", "eye-corner2-down", True),
    pair("mouth-scale-vert-incr", "mouth-scale-vert-decr"), pair("mouth-lowerlip-height-incr", "mouth-lowerlip-height-decr"),
    (sym("cheek-volume-decr"), []),
]
FACE_LIMIT = 1.0
