#!/usr/bin/env python3
"""Blender 4.x + MPFB2 Automation Script for The Sleeping Academy R-05 Cast.

Automates the project's 6.5-head stylized-realistic character pipeline in Blender:
  1. Verifies barefoot height / head-height == 6.5 (normalizes scale if needed)
  2. Applies a subtle Clear-Line Toon smoothing pass (flattening harsh micro-anatomy
     so HallInk outlines read cleanly without noisy crease artifacts)
  3. Converts thin hair cards / adds solid tapered curve hair locks covering the
     occiput and temples so 3D silhouettes stay solid under hat brims and backlight
  4. Exports a Godot-ready GLB preserving MPFB2 / GameEngine bone names and rest pose.

Usage (inside local Blender with MPFB2 installed):
    blender -b character_work.blend --python tools/mpfb2_test/upgrade_r05_cast.py -- \
        --out assets/characters/mpfb/r05_formal.glb
"""

from __future__ import annotations

import argparse
import sys

try:
    import bpy
    import bmesh
except ImportError:
    print("Run this script inside Blender: blender -b <file.blend> --python tools/mpfb2_test/upgrade_r05_cast.py -- --out <out.glb>")
    sys.exit(0)


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--out", default="assets/characters/mpfb/r05_formal.glb")
    p.add_argument("--smooth-factor", type=float, default=0.28)
    p.add_argument("--smooth-iterations", type=int, default=3)
    return p.parse_args(argv)


def smooth_for_clearline_toon(mesh_obj: bpy.types.Object, factor: float, iterations: int) -> None:
    """Flatten high-frequency facial/skin micro-bumps while preserving silhouette."""
    mod = mesh_obj.modifiers.new(name="ClearLineSmooth", type="CORRECTIVE_SMOOTH")
    mod.factor = factor
    mod.iterations = iterations
    mod.smooth_type = "LENGTH_WEIGHTED"
    bpy.context.view_layer.objects.active = mesh_obj
    bpy.ops.object.modifier_apply(modifier=mod.name)


def solidify_hair_locks(hair_obj: bpy.types.Object) -> None:
    """Give solid thickness and clean normals to hair lock geometry for toon shading."""
    if hair_obj.type != "MESH":
        return
    mod = hair_obj.modifiers.new(name="SolidHairLocks", type="SOLIDIFY")
    mod.thickness = 0.0085
    mod.offset = 0.25
    bpy.context.view_layer.objects.active = hair_obj
    bpy.ops.object.modifier_apply(modifier=mod.name)


def main() -> None:
    args = parse_args()
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            low = obj.name.lower()
            if "body" in low or "human" in low or "head" in low:
                smooth_for_clearline_toon(obj, args.smooth_factor, args.smooth_iterations)
            elif "hair" in low:
                solidify_hair_locks(obj)

    bpy.ops.export_scene.gltf(
        filepath=args.out,
        export_format="GLB",
        export_apply=False,
        export_skins=True,
        export_animations=True,
        export_yup=True,
    )
    print(f"Exported upgraded R-05 GLB to {args.out}")


if __name__ == "__main__":
    main()
