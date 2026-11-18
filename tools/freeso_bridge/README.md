# FreeSO → Godot lot data handoff

This adapter reads FreeSO's complete `FSOv` VM snapshot (`.fsov`) via the pinned upstream `FSO.SimAntics.Marshals.VMMarshal.Deserialize`. The upstream sandbox loads the same marshal into an initialized VM with `VM.Load`; offline export deliberately projects the deserialized state directly so reset/ticks cannot change the saved positions. The four-byte header is case-sensitive: `FSOv`, followed by an Int32 version and a compression flag; FreeSO itself handles the compressed payload. This is for trusted local saves only.

An XML house blueprint contains build data, not running-avatar positions; a standalone-object/character export is also not a complete lot. For either input, open/import it in the original client and obtain a complete VM snapshot with the lot and avatars present. FreeSO's sandbox checks `FSOEnvironment.UserDir/LocalHouse/<lot>.fsov` alongside its lot entry. No generated substitute lot is used by the bridge.

## Run against the original client build

From repository root, after the original client build is available (see `tools/freeso/freeso.ps1`):

```powershell
pwsh -NoProfile -File tools/freeso_bridge/export.ps1 `
  -Snapshot 'C:/path/to/real-lot.fsov' `
  -Output '.runtime/freeso/lot.json'

& '.runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe' `
  --headless --path . --script res://tools/freeso_bridge/check_snapshot.gd `
  -- .runtime/freeso/lot.json
```

`-ClientRoot` defaults to `.runtime/freeso/client`; it expects the pinned build receipt and uses the client DLLs without modifying vendor or client output. The output parent must exist. An invalid input or unavailable dependency gives a nonzero exit; successful exports replace the JSON atomically. On failure, an earlier JSON remains in place; callers must check exit status before treating it as fresh.

## Godot contract

```gdscript
const FreeSOLot := preload("res://tools/freeso_bridge/LotSnapshot.gd")
var result := FreeSOLot.read_file(path)
if result.has("error"):
    push_error(result.error)
    return
var lot: Dictionary = result.snapshot.lot
for avatar in result.snapshot.avatars:
    if avatar.placed:
        var position := FreeSOLot.avatar_position(avatar)
        # Put the marker/model for avatar.object_id at position.
```

- `schema`: `freeso.lot-snapshot.v1`. `source.kind`: `fsov` or `live-vm`. `source` also carries `format_version`, snapshot `sha256` (null for live), and `ts1`. `tick` is the FreeSO VM clock tick.
- `lot`: `width`, `height`, `stories`; sparse `walls` and `floors` in level-major then row-major order. `x`, `y` are zero-based; `level` is one-based. Wall `mask` is the original `WallSegments` bitset, `segments` the original enum string, `patterns` = TL/TR/BL/BR and `styles` = TL/TR. Floor `pattern` is the original ID. Missing cells have no wall bits or have floor pattern zero, respectively. Preserve diagonal bits and deduplicate shared edges at rendering time, not during data transport.
- `avatars`: actual `VMAvatarMarshal` rows. `object_id` is VM-local; `persist_id` may be zero. `guid`, `heading_radians`, and signed `x16`/`y16`/`level` are native values. Keep `placed:false` rows for diagnostics but do not spawn them. Godot maps to `(x16/16, (level-1)*2.95, y16/16)`; heading remains in FreeSO convention.
- This format transfers saved wall and floor grids and avatar poses. Object-generated doors/windows, furnishings, terrain, outfits, animation and routing are outside v1.


Verified source revision: `4c6b3e8f5835b228723caea3c9f683c62f244f73` (`TSOClient/tso.simantics/Marshals/{VMMarshal,VMArchitectureMarshal,VMEntityMarshal}.cs`, `tso.simantics/VM.cs`, `tso.world/Model/LotTilePos.cs`, `tso.client/UI/Screens/SandboxGameScreen.cs`).

## Live sandbox integration

`tools/freeso/freeso.ps1 -Action Build` prepares a disposable tracked-source copy under `.runtime` and calls `install-hook.ps1 -UpstreamWorktree <copy>` before restore/build. The installer adds the adapter to `FSO.Client.csproj` and instruments the pinned `SandboxGameScreen.Update` around `vm.Update()`. No writes to the original submodule are needed. The hook checks `vm.Ready` and requires `vm.Context.Clock.Ticks` to have advanced across the update. It then calls `SnapshotBridge.ExportLive` on the same thread, after the original VM finishes its update. `VM.Update` drives native `Tick()`; `VMClock.Tick` advances the clock. Paused or non-advancing updates do not emit a new JSON.

```powershell
pwsh -NoProfile -File tools/freeso/freeso.ps1 -Action Check
pwsh -NoProfile -File tools/freeso/freeso.ps1 -Action Build
pwsh -NoProfile -File tools/freeso/freeso.ps1 -Action Launch -RoomId gallery
```

The Godot build button passes the room ID it captured at click time. The launcher sets **`FREESO_VM_SNAPSHOT_PATH`** only in the new FreeSO client process, to the absolute path of `.runtime/freeso/lots/gallery.json` for the example above. The hook reads it once and freezes the destination. `active-room.txt` is never consulted. The first advancing ready sandbox VM owns this binding; opening a different sandbox VM in that process stops export. Launch from the next Godot room to establish a new binding, and open the intended FreeSO lot in that client. The room ID labels the Godot destination; it does not auto-select a native sandbox lot.

The hook writes at most once per second, uses a process-held lock beside the output to prevent competing client writers, and atomically replaces JSON only after a full write. Failed exports leave the last complete file intact. The output adds `source.room_id` (destination basename) and `source.pid` (actual FreeSO client PID). A prior file may remain on disk, so runtime validation must match both the just-launched PID and room ID, and observe the `tick` increasing while that lot runs. Then move a Sim or edit a wall and check that the matching native row changes; switch rooms in Godot and verify the first process never writes the second room's file.

## Resident activity and freewill evidence

Every exported avatar can carry `lot_membership` and `activity`. For a residential TSO lot with a nonzero persistent ID, `lot_membership` checks the native owner and roommate lists: `owner`, `build_roommate`, `roommate`, or `not_listed`. Community lots repurpose those lists, so they return `unknown`; TS1 family membership and sandbox avatars without persistent IDs also return `unknown`. The bridge exports their real activity regardless. Godot may associate avatars with camp residents explicitly by stable identity; mere placement in a lot does not establish residency.

`activity.status` is one of:

- `active`: the native `VMThreadMarshal.ActiveQueueBlock` identifies the running queue entry. `action` carries the native UID, name, routine ID, interaction number, callee/stack object IDs, priority and queue mode.
- `no_active_action`: there is no active queue entry. `queued_count` can be nonzero and `stack` can still describe the BHAV that is running (routine ID, instruction pointer, object IDs and the `action_tree` flag). Treat this as “no active interaction,” not as evidence that the Sim is idle.
- `unavailable`: the format predates a serialized active index or the native thread/queue could not be matched. Older bridge JSON may omit `activity` entirely.

`action.autonomous_priority` reports the native priority enum, which scripted pushes can also set. The stronger optional `action.freewill_evidence` is `vm_find_best_action` only when the patched VM actually enqueued that same action object through its native `VMFindBestAction` primitive and it is active at sampling time. The observation is process-local: it is intentionally absent from `.fsov` bytes and network state, and becomes `null` if the bridge did not observe that selection in this VM. A one-second sample can miss brief interactions. The hook neither changes resident control settings nor runs a planner.

To verify freewill, use a real running sandbox whose assets and resident BHAVs invoke `VMFindBestAction` (with native autonomy enabled where the lot/game supports it), and let a Sim select an interaction without issuing a command. Observe a changing native `tick` and an active row with `freewill_evidence: "vm_find_best_action"`. A manually commanded action can have valid native activity without freewill evidence. If the local sandbox, lot, or network mode does not run that primitive in the client VM, display the activity and leave freewill unverified; do not synthesize a fallback.
