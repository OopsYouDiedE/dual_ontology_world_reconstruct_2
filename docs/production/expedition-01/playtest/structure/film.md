# Sol entrance comparison film

Run at the repository root with the existing Godot 4.7.2 .NET asset cache and `ffmpeg` / `ffprobe` on PATH:

```powershell
$env:DOTNET_ROOT = 'C:/Program Files/dotnet'
python -B docs/production/expedition-01/playtest/structure/film.py
```

The runner defaults to `.runtime/structure-565b9cfbef` (override with `--run`). It reads each `cautious-31-{A,B}/report.json`, renders the real Expedition scene using a visible Forward+ viewport, and installs the same experimental portal in B. Both renders use the stock environment and separate user-data directories. It writes `.runtime/design-review/A.mp4` and `B.mp4` after validating both streams. The printed scratch directory preserves Godot logs, frames, ffprobe reports, and decoded checks at 1, 8 and 10 seconds.

| Video time | Camera |
|---|---|
| 0–3 s | Matched static first-person entrance view, at the sampled spawn, facing +X. |
| 3–12 s | Sol's sampled player path, with Hale's sampled positions, from tick 235 at one simulation second per video second. A common level +X heading makes the portal and the change in lateral approach comparable. |

The film is a spatial replay with interpolated positions and editorial framing, not a recording of the original inputs, gaze, NPC animations or audio. First sampled crossings in the source reports (A 612, B 636) map to approximately 9.28 s and 9.68 s, respectively. Output: silent H.264, 960×540, 30 fps, 360 frames, 12 seconds per arm.

## New live controller capture

```powershell
$env:DOTNET_ROOT = 'C:/Program Files/dotnet'
python -B docs/production/expedition-01/playtest/structure/film_live.py
```

`live-A.mp4` / `live-B.mp4` start at live simulation tick 0. The staged Human Sol driver supplies normal game inputs at fixed 60 Hz to the full Expedition scene, using the original first-person camera and HUD. The recorder takes one frame after draw every four ticks through tick 716 and encodes the resulting 180 frames at 15 fps (12 seconds, 1280×720, silent). No historical coordinates drive these versions, and the frontend adds no editorial opening shot. The runtime evidence includes the exact command, new decision traces and geometry probes, plus decoded frames at 2, 7 and 11 seconds.
