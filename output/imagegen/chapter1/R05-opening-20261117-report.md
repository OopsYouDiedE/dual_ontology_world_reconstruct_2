# Chapter 1 R05 opening: visual reference, 2026-11-17

Status: development reference; generated image reviewed visually, engine alignment and independent acceptance pending.

## Evidence

- [Runtime baseline](R05-opening-20261117-baseline.png) (1440 × 900), SHA-256 `e83ae34b42d348a23f2df2b77920eb755474233af799dded18e859ed27f697fb`.
- [Runtime provenance](R05-opening-20261117-baseline.png.json): current project root, Boot.tscn to Main.tscn, Godot PID 42528, MCP server PID 42144. The `step(start)` observation recorded Chapter 1, R05, opening/look, 07:00. This is a Windows native-rendered capture; Xvfb isolation was unavailable and was not used.
- [Generated target](R05-opening-20261117.png) (1586 × 992), SHA-256 `6b008c56fddf04360164b8a961a271ed8c7475886396f75cdd1c521118b43240`. Generated with the original imagegen CLI edit, model `gpt-image-2.6-sunburst`, high quality, configured provider, 33.2 seconds; [submitted prompt](R05-opening-20261117-prompt.txt).
- Both Godot sessions used for this task exited gracefully. Their captures and observations reside under `.runtime/input-client/6a463445932c4da0/`.

## Visual reading and bounded next step

The reference keeps the major room layout and seated figure, lifts dark wardrobe and doorway surfaces, reduces the red-orange wood cast, and softens the floor light contrast. The model also changes fine furniture, picture, pose, material and camera details; keep actual geometry, animation and framing authoritative. Use this image as a material/lighting direction for this opening shot, then capture the same shot after each isolated engine change.

Full-frame image statistics, 0–1 sRGB channel-weighted luma (not linear scene exposure):

| Image | Mean | P05 | P95 | Mean R / G / B |
| --- | ---: | ---: | ---: | --- |
| Baseline | 0.2547 | 0.0142 | 0.8661 | 0.3433 / 0.2382 / 0.1601 |
| Reference | 0.2954 | 0.0864 | 0.7251 | 0.3856 / 0.2790 / 0.1999 |

The measured whole-frame delta is +0.0407 mean, +0.0722 P05, and -0.1410 P95. The reference is a generative edit at a slightly different resolution and contains changed details, so these values are diagnostic targets rather than calibrated Godot parameter values. No SSIM/LPIPS match score or 8/10 claim was calculated. A scene-matched before/after and independent evaluation remain required.
