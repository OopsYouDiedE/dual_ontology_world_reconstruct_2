# Human Sol batch benchmark

From the repository root, with the project's Godot 4.7.2 .NET runtime and imported assets ready:

```powershell
# Set this if Godot does not find the Windows .NET 8 runtime on its own.
$env:DOTNET_ROOT = 'C:/Program Files/dotnet'
python tools/expedition/human_batch.py run --seeds 31 113 --ticks 24000 --jobs 2 --timeout 150
python tools/expedition/human_batch.py summary .runtime/human_batch/<batch-id>
python tools/expedition/human_batch.py summary .runtime/human_batch/<batch-id> --require-completion
```

`run` defaults to all three profiles; `--profiles cautious curious` restricts the matrix. `--godot` (or `DV_GODOT`) selects another executable. On Windows, the official `_console.exe` is resolved to its sibling engine executable so the timeout owns the actual Godot process. `--jobs` accepts 1–12 independent Godot processes. By default the strategy fixture uses the smallest of 8, the available logical CPU count, and the number of cases. The full fixture defaults to one process. This limit applies per batch: run the four reading arms sequentially to share the same machine budget. `--timeout` is per process in wall seconds, starting at launch; timed-out cases are killed and the remaining cases continue.

The runner passes `--strategy-light` to Human Sol by default. Use `run --full` to pass `--full` and request the full rendering-effects fixture. Both modes remain headless; the batch manifest and summary record the requested fixture.

Every case instantiates the real `Sortie.tscn` with the ordinary Human Sol sensor, policy, and input path. `--headless --fixed-fps 60` advances the scene without real-time pacing; the script checks that physics is also 60 Hz. Each case has its own user-data root, engine and console logs, `report.json` (when returned by Godot), and `case.json` (process result and timing). The batch writes `batch.json` as cases finish; the summary sorts by requested matrix order. Aggregate throughput is the sum of validated reported ticks / 60 divided by the elapsed wall time of the matrix, including engine startup and teardown. If logs flag engine errors alongside a valid report, the summary also prints throughput for clean cases alone. Individual wall times overlap at `--jobs > 1`.

A local seed RNG selects a reaction delay (cautious 12–14 ticks, curious 15–17, direct 19–21), a locomotion hold offset of −3…+3 ticks, and an initial side of ±1 (curious wall flank; other profiles' initial turn bias). The base holds are 41/43/48; curious's depth-based wall strides also receive the offset. Scripted interaction holds retain their usual behavior. `policy_parameters` records the effective settings. `decision_trace` records every applied policy intent with the decision tick, observation tick, and effective hold. Standalone Human Sol invocations keep the original settings. Replay with the same profile, seed, tick budget, project and Godot build; the parameter space is finite, so different seeds can select the same tuple.

By default both commands exit 0 when every case produces a valid, error-free diagnostic, including `tick_budget` and in-game `failed` results. Timeouts, engine errors, invalid reports, and incomplete batches exit 1. Add `--require-completion` to either command to also require `completed` for every case. This is a headless policy/physics benchmark: pixel-level rendering and scripted playthrough coverage are separate checks.
