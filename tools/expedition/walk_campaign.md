# Expedition WalkTest campaign (Windows)

From the repository root in PowerShell, with the project-local Godot 4.7.2 .NET runtime and a ready Godot import cache:

```powershell
python tools/expedition/walk_campaign.py launch --workers 2
python tools/expedition/walk_campaign.py report
python tools/expedition/walk_campaign.py stop
# Wait until report says idle before resuming:
python tools/expedition/walk_campaign.py resume --workers 2
python tools/expedition/walk_campaign.py resume --workers 2 --retry-infra
python tools/expedition/walk_campaign.py replay 6
```

`launch` and `resume` start the same hidden, detached supervisor. One supervisor owns the ledger; 2–4 workers are allowed, with the supervisor and Godot children restricted to that many logical CPUs. The Windows job terminates campaign children if their owner exits. Each slot has private `APPDATA` and `LOCALAPPDATA`. `stop` lets current cases finish and checkpoint. The ledger commits each result; an interrupted in-flight case is rerun on resume. `--retry-infra` also requeues `script_error` and `engine_error`. A sequence of infrastructure faults halts scheduling so a broken Godot setup cannot consume the campaign. Windows reboot/sign-out may stop the process; use `resume` afterward.

## Coverage and output

- Witness/skip: `2 × 4 loadouts × 3 crossings × 9 arrival radii × 8 stair radii × 12 settle intervals = 20,736`.
- Transit: `4 × 2 crossings × 9 × 8 = 576`. Transit skips the settle phase, so settle is recorded as `null`. The north-order refusal subtest remains available in ordinary WalkTest, outside this grid. The seed stays fixed because here it labels archive facts rather than changing the route.
- Arrival radius is 0.08–0.16 m in 0.01 m steps. Stair radius is 0.96–1.10 m in 0.02 m steps; it moves the 41 spiral waypoints on every completed route. Settle is 116–160 physics ticks in steps of four. The stair default remains 1.02 m. Cases exercise full headless WalkTest including its existing assertions. The separate collision fixture probe is outside this run.
- `.runtime/walk-campaign-v2/results.sqlite3` holds one row per recorded ID. Workers stream diagnostics in memory, retain a bounded excerpt per case, and reuse at most four profile directories with rotating Godot logs. The batch collects no screenshots or per-case trace files. `supervisor.log` records why a supervisor stopped. ETA uses throughput for the current session.
- `gameplay_death` requires a valid `WALK_DEATH` receipt with `fail_reason` and a route-relative physics tick. Script/shader errors, infrastructure failures, engine errors on a nominal exit, route/assertion failures and passes are separate categories. For other early failures a tick of zero means the test did not emit a completion/death tick.
- `replay ID` prints the exact Godot invocation with the same policy parameters and explicit paths for the opt-in route and archive traces. Run the printed command in PowerShell; use `&` before a quoted executable path. For comparison, replay against the same worktree/runtime and wait for the campaign to be idle if you need to preserve the total CPU cap.

## Keep inputs fixed

The supervisor stamps Git-visible files (tracked and nonignored untracked, excluding documentation) by path, size, mtime and file identity, plus the engine executable. It compares that baseline at resume and before committing each finished batch. Detected drift halts scheduling and discards uncommitted results. Keep the worktree, Godot import cache and runtime dependencies fixed for the whole campaign: ignored/generated files and edits reverted between checks are outside the detector. A deliberately changed baseline needs a fresh campaign ledger/version; preserve the old ledger for comparison.
