"""Second look pass: signed deltas to each actor's own MPFB local-fit recipe."""

DETAIL = {
    'detective': {
        'measure-waist-circ': -.10, 'torso-muscle-pectoral': .07,
        '{side}-lowerarm-muscle': .10,
    },
    'halvard': {
        'measure-shoulder-dist': .11, 'measure-neck-circ': .13,
        'measure-calf-circ': .07, 'chin-width': .33,
        'chin-height': -.12, 'nose-point-width': .18, '{side}-eye-height2': -.12,
    },
    'jane': {
        'measure-waist-circ': .09, '{side}-upperleg-muscle': .15,
        'measure-calf-circ': .11, 'head-scale-horiz': .08,
        'chin-height': -.22, '{side}-cheek-volume': .21, '{side}-eye-height2': .19,
    },
    'qingyue': {
        'measure-waist-circ': -.12, 'measure-neck-height': .13,
        'torso-scale-depth': -.13, 'head-scale-vert': .11,
        'chin-width': -.17, 'nose-scale-horiz': -.10, '{side}-eye-height2': -.16,
    },
    'lucian': {
        'measure-shoulder-dist': -.14, 'torso-scale-depth': -.15,
        'measure-waist-circ': -.12, '{side}-upperarm-muscle': -.08,
        'chin-width': -.09, '{side}-cheek-volume': .09,
    },
    'ward': {
        'measure-shoulder-dist': .18, 'torso-vshape': .16,
        'measure-upperarm-circ': .12, 'torso-muscle-pectoral': .11,
        'chin-width': .12, '{side}-cheek-bones': .07,
    },
    'shending': {
        'torso-scale-depth': .19, 'measure-waist-circ': .20,
        'torso-muscle-dorsi': .15, '{side}-lowerarm-muscle': .16,
        '{side}-cheek-volume': .11, 'nose-point-width': .09,
    },
    'caretaker': {
        'measure-neck-height': .21, 'measure-neck-circ': -.14,
        'torso-scale-horiz': -.15, '{side}-hand-fingers-length': .12,
        'chin-height': .09, '{side}-cheek-volume': -.09,
    },
}


R05_FACE = {'nose-point-width': -.08, 'chin-prominent': .12, '{side}-eye-height2': -.08}


def refine(current, deltas):
    updated = dict(current)
    for target, delta in deltas.items():
        updated[target] = round(updated.get(target, 0) + delta, 4)
        assert abs(updated[target]) <= 1, (target, updated[target])
    return {name: weight for name, weight in updated.items() if weight}
