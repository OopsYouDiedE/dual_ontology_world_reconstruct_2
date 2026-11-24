# A05 · The Afterimage Carriage

**Scope:** one room, five walkable pads, one carriage, no damage. This is the model prototype. The scene, input mapping, audio, collision and viewport checks belong to the view build. See [the integration contract](VIEW_CONTRACT.md) for the public API and rendering responsibilities.

## What the player can read

- **Wiring plate:** “Same beat: light + sound. Clear → West. Silver → East.” The lamp points into the prism; both bells feed the same sound line. The prism reveals the matching pickup and the outline of its gangway. A solid gangway requires the carriage to align with the revealed outline.
- **Reel plate:** “Last eight beats. Wired pulses replay. Your footing and prism return to the first mark. The carriage runs on its own spring.” Engrave the fixed anchor marks in the shore pads, draw real wires on the floor fixtures, and visibly omit the rewind wire from the carriage bell. A printed film strip shows filled beats and the read head. A rewinding player sees the anchor and destination phase before the splice.
- **Dock plate:** “West spring returns to neutral. The service ladder always leads down to Hub.” Use a spring indicator, receiver flags and a separate down-arrow ladder. A failed crossing or missed pulse leaves the player on safe footing; there is no health counter or death state.

## Complete semantics

| Part | Rule |
|---|---|
| Clock | Initial tick 0, at Hub, clear prism, neutral carriage. Simulate exactly 60 ticks/s. One action per 20-tick decision; idle is `wait`. Deadlines commit before that beat's action. Moving is atomic between adjacent pads. |
| Light and sound | Successful `pulse` at Lamp emits light; either bell emits sound. A pulse lives in `[t, t+20)` and the next decision discards it. A replayed pulse is injected before the live action on the same boundary. At least one pulse of each channel in the same beat requests the receiver lit through the *present* prism. |
| Rewind | The film rolls over the most recent eight decisions. The anchor is the state immediately before the oldest recorded decision, after any mechanical deadlines at that boundary. A full film with a fixed shore anchor can wind while the prism and powered swing are idle. For 40 ticks input is locked; on commit the pawn and prism return to the anchor. The exterior carriage and its spring keep their own clock. |
| Causal survival | Only a successful pulse from the fixed Lamp or Bell leaves a contact on the film. Each of those contacts emits locally, once, eight beats at the original relative spacing. Walking, prism commands, waits, failed contacts and the unwired carriage bell leave blank beats. The head plays back or records, one at a time. The first playback beat is 20 ticks after the splice; recording resumes on the boundary after beat eight. |
| Optics | `prism` at Hub or Carriage starts a 40-tick change of the same shared prism. Clear exposes the West pickup and West gangway; silver exposes the East pickup and East gangway. A gangway is traversable only when the revealed pickup also matches the settled carriage alignment. The two shore paths stay usable in either form. |
| Carriage | A valid pair to a different alignment starts a 40-tick powered swing. A pair during an armed swing cannot replace it, and pairing to the settled alignment cannot renew it. West settles on a 100-tick spring lease, with a return cue for its final 40 ticks. When a powered swing and the spring are due together, the swing takes precedence. If the spring is due first, the carriage rests at neutral until the powered swing completes. The carriage holds the rider in all alignments. |
| Exit and recovery | `move exit` succeeds only from the carriage with the East gangway solid. `escape` takes a one-way ladder to Hub in any phase; eight fresh shore decisions can always fill a new reel. The terminal result holds until `reset()`. |

The **rewind**, **prism**, **powered swing** and **spring return** each get a continuous cue from start through `due_tick - 1`, a full 40 ticks. The cue previews the specific change. At the deadline, the authoritative path set changes at once; no action can begin in the old topology and finish in the new one.

## Causal shape

A single player can emit only one channel per beat. The West rendezvous can swap the live and recorded roles across the two shore fixtures. Getting on requires a settled West swing *and* the clear prism. The East rendezvous needs a recorded flash already on the erased branch, a live carriage bell and the transformed prism at that beat. The two timelines join twice. Even with identical current geometry and a live ring at the same tick, erasing the past flash removes the East swing.

West cannot be saved as a partial solution for a later reel. The latest West request is playback beat 8; it settles at beat 10 and returns by beat 15. At best recording resumes on beat 9, and a subsequent rewind can start on beat 17. The escapement is physically outside the splice, and the player can restore only to a shore pad. The entire room and all rules are public: a solver can plan across the film, the present timeline and deadlines. No puzzle step depends on looking up a seed, hiding a route or making a graph larger.

## Model receipts

[golden.json](golden.json) contains two replays, using opposite channels on the original branch for the West rendezvous. Both wind at 180, splice at 220, pair West at 260, board at 300, throw the prism at 320, pair East at 360, and cross at 400. The check also validates a second East rendezvous one beat later: the spring returns the rider to neutral at 400, and the warned East swing carries them across at 420.

Counterfactuals cover a one-beat-late ring, two lights on the same beat, deleting only the historical final flash, skipping the prism, trying to walk the outlined gangway early, and attempting to bank a late West docking for another rewind. The verifier also checks rolling expiry, filtering of the unwired bell, safe escape, pending cue precedence, and action isolation at rewind.

Run the model tests from the repository root, with the project-local Godot 4.7.2 .NET binary:

```powershell
& .\.runtime\godot\4.7.2\Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . --script res://tools/afterimage/verify.gd
```

These are model results. Keep the golden fixture and verifier out of the independent white-box handoff; use the rule file, view wiring and public semantics for it.
