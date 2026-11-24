# Expedition rule sweep

Run from the repository root with the project-local Godot 4.7.2 .NET console build:

```powershell
$godot = '.runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe'
& $godot --headless --path . --script res://tools/expedition/rule_sweep.gd -- --run-seed=101
```

The harness instantiates the production `ExpeditionContracts` and `ArchiveFacts` scripts directly. It exercises their API with deterministic inputs, without loading the expedition scene, traversing a route, or running a player policy. The seed is archive log metadata; it does not select test cases.

| Suite | Exhaustive domain | Measured edges | Replayed action calls | Suite time |
|---|---|---:|---:|---:|
| `a` | All nonempty traces through length 5 over 12 actions | 271,452 | 1,332,588 | 4.31 s |
| `b` | All paths through length 22 over 6 actions, modulo equivalent states | 444 | 5,256 | 0.011 s |
| `archive` | All nonempty traces through length 5 over 8 actions | 37,448 | 181,896 | 2.52 s |

Measured in one passing run with `--run-seed=101`; times exclude Godot startup. An edge is one checked extension of a trace. Replayed calls also include rebuilding its prefix from a fresh production object. B visited 74 states, including the initial state, and exhausted the reachable graph within the bound. Its breadth-first search retains the shortest representative for each state: the scalar progress, quiet time, spent pardon, and breach count reconstruct every B field used by future B actions. Every outgoing edge is checked against those production fields **before** merging a revisited state.

- **A:** A timestamp oracle checks custody events, active role, blackout remaining, and breach ledger. `both_p` and `both_h` nominate the first seer on entry; `p_*` and `h_*` hold only that observer for the indicated milliseconds. Includes grace crossing, interrupted holds, blackout expiry, abandon, retry, and hard reset.
- **B:** A scalar nine-step ladder predicts calls, bead decay, memory, and single-use pardon, including denial after a second remembered event. Retry and hard reset distinguish transient steps from the expedition ledger.
- **Archive:** A local prerequisite table and first-source evidence ledger check every gate and fact after each prefix, plus ordered evidence/decision rows, per-intent deduplication, and snapshot isolation. Later observations use distinct source strings so duplicate facts cannot silently overwrite the first source. The synchronous sweep expects tick zero and verifies the configured seed.

This finite domain targets rule transitions and archive gates. Geometry and frame integration belong to scene tests; trust awards, handbook text, and arbitrary time deltas are outside the sweep.

## Replay and regression

Exit codes: `0` pass, `1` first oracle mismatch, `2` invalid arguments. `COUNTEREXAMPLE` JSON includes expected and actual output, the shortest failing action prefix within the suite, and `replay_args` to append after the script path. Use `--suite=a|b|archive` to run one suite; add `--trace=` with comma-separated action names to run just that sequence.

```powershell
& $godot --headless --path . --script res://tools/expedition/rule_sweep.gd -- --suite=a --trace=both_p,h_250,both_p,h_375
```

Before the fix, this trace released custody: Hale's 250 ms and 375 ms solo samples were added across a renewed overlap. The continuous solo hold after the overlap is 375 ms, below the 620 ms threshold. The fix clears the hold on renewed overlap; the replay now stays in `overlap`.
