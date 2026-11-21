"""Artist-directed phenotype and surface choices for the four newer MPFB actors."""
from array import array
from math import atan2, cos, hypot, sin
from pathlib import Path

import bpy

from build import LocationService, coat, material

# Stock MPFB macro weights, applied as a normalized blend; used as visual starting points.
RACE = {
    'lucian':    {'asian': .14, 'caucasian': .77, 'african': .09},
    'ward':      {'asian': .11, 'caucasian': .72, 'african': .17},
    'shending':  {'asian': .83, 'caucasian': .11, 'african': .06},
    'caretaker': {'asian': .31, 'caucasian': .55, 'african': .14},
}
SKIN = {
    'lucian': (.46, .335, .276), 'ward': (.43, .303, .237),
    'shending': (.397, .279, .195), 'caretaker': (.438, .342, .303),
}
IRIS = {'lucian': 'grey', 'ward': 'bluegreen', 'shending': 'brown', 'caretaker': 'brownlight'}


def amber_slit(source):
    """Draw vertically slit irises in the two UV islands of the stock CC0 eye atlas."""
    width, height = source.size
    pixels = array('f', [0.0]) * (width * height * 4)
    source.pixels.foreach_get(pixels)
    for u, v in ((.293, .298), (.707, .705)):
        for j in range(int((v - .12) * height), int((v + .12) * height) + 1):
            y = (j + .5) / height - v
            for i in range(int((u - .12) * width), int((u + .12) * width) + 1):
                x = (i + .5) / width - u
                r = hypot(x, y)
                if r >= .109:
                    continue
                influence = min(1.0, (.109 - r) / .012)
                angle = atan2(y, x)
                fleck = 0.76 + 0.12 * cos(angle * 38 + r * 63) + 0.10 * sin(angle * 59 - r * 86)
                limbus = min(1.0, (.119 - r) / .034)
                value = (0.84 * fleck * limbus, 0.45 * fleck * limbus, 0.12 * fleck * limbus)
                if (x / .010)**2 + (y / .050)**2 < 1.0:
                    value = (.025, .014, .010)
                idx = (j * width + i) * 4
                for k in range(3):
                    pixels[idx+k] += influence * (value[k] - pixels[idx+k])
    image = bpy.data.images.new('Caretaker amber slit iris', width, height, alpha=True)
    image.pixels.foreach_set(pixels)
    image.update()
    image.pack()
    return image


def review_skin(obj, actor):
    coat(obj, material('Warm gray study clay' if actor not in SKIN else f'{actor.title()} skin',
                       SKIN.get(actor, (.44, .37, .31))))


def review_eyes(eyes, actor):
    if actor not in IRIS:
        return
    path = Path(LocationService.get_user_data())/'eyes'/'materials'/f'{IRIS[actor]}_eye.png'
    image = bpy.data.images.load(str(path), check_existing=True)
    if actor == 'caretaker':
        image = amber_slit(image)
    mat = material(f'{actor.title()} iris', (.94, .94, .94))
    nodes = mat.node_tree.nodes
    tex = nodes.new('ShaderNodeTexImage')
    tex.image = image
    surface = nodes.get('Principled BSDF')
    surface.inputs['Roughness'].default_value = .38
    mat.node_tree.links.new(tex.outputs['Color'], surface.inputs['Base Color'])
    coat(eyes, mat)
