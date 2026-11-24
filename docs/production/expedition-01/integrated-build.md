# Expedition 01: integrated A + B build

The rework notes and optimization plan are the two original delivery records. This build combines their implemented features in the existing expedition scene. Proposed B6 and C2 rooms in the optimization plan remain proposals.

- Q aimed at Hale switches hold/follow. At a contextual choice, Q opens orders; scroll and press E, or press a numbered key. E aimed at Hale starts a conversation.
- Space jumps; Ctrl quiets and lowers the viewpoint; right mouse steadies aim. R toggles the lamp; F stomps with a six-second cooldown. Controls are shown on a separate system strip. The five-page Chinese manual records shaft inscriptions on page five as they are read.
- A2 provides a quiet oil cache and a second entrance to the archive. On the return ramp the pressure vault offers an inscription and a one-use oil reserve. The airlock supports a joint exit and an optional solo slide.
- The first watcher yields on the archive plate; the second holds through the hand-off. Running footfalls on iron count toward the hunter's memory. In the shaft, overlapping footsteps increase exposure and two lit lamps cost additional oil while both carriers are present.
- The service-walk oil rate and post-core chase speed account for the slower quiet gear and the longer southern approach. The bypass still costs oil even with the lantern out.

Godot 4.7.2 .NET: `ArchiveTest`, `HearingTest`, `ContractTest`, `FeelTest`, `NicheTest`, `NewVerbsTest`, and `WalkTest` (default, `--south`, `--clock-only`, `--oil-only`). The live-gaze tests use both witness orders; the lamp test moves Hale outside the shaft. Forward+ smoke check: 1280x720, actual game viewport, lamp input and HUD.
