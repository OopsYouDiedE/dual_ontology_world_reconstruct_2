# A06 authority and verification contract

**Gap 6A + 6B.** The Listener charges from the walkway's tread. The watcher advances on its rail whenever the parapet hides it from the player's eye. One stride samples both; one drawleaf spans the only gap and changes the sound of that stride. The only route is a straight row of twelve strides. The renderer API and cue anchors are in the sibling room's `VIEW_CONTRACT.md`.

## Reading the crossing

From cover, throw the lever and watch for the flat detent. On iron, go tall while the ear spring is quiet; duck when it rattles and the watcher's ratchet has time left. The watcher's approach is visible on the side rail. A ratchet at full stroke stays charged under gaze; make space while tall before ducking again. Stay tall across the felt to hold the watcher while the ear spring settles, then use both readings again on the last iron stretch. Backward strides use the same postures. The porch breaks the chase. A failed run returns through the service passage in 60 ticks, with the leaf's clock still running.

**Reproduce through normal inputs.** At tick 0 use `lower`; take four `wait` decisions. Once the leaf is flat, use the following from porch toward exit (`W` = `watch`, `C` = `creep`). The same inputs work when the initial throw is delayed and the crossing starts at the flat detent.

| Route | First four iron spans | Four felt spans | Last four iron spans |
|---|---|---|---|
| Normal | W C W C | W W W W | W C W C |
| Alternate | C W C W | W W C W | C W W C |

## Integer rules

- Decisions every 20 ticks; step velocity is 3 cm/tick on either posture. Integer physics ticks run at 60 Hz.
- Iron: tall adds 4 ring units/tick; low sheds 2. Felt: tall sheds 3; low sheds 4. Range is 0–240. At 80 or more the ear spring starts a 60-tick warning; dipping under 80 releases it. A warning that remains present at its deadline catches.
- Tall gaze locks the watcher's position. Low posture lets it move up to 9 cm/tick toward the player's projection on the rail. At a longitudinal gap of 100 cm or less, an unobserved watcher starts a 60-tick wind-up. Opening the gap past 100 releases it. Gaze holds a charged watcher stationary; the existing visible wind-up remains live and can strike on the first unobserved tick once mature.
- Lowering: 60 ticks of steam, 40 in motion, then the gap becomes passable. Return steam starts after 300 ticks at the flat detent, and the pawl raises the leaf 60 ticks later or as soon as it is clear after that. The gap blocks at the start of the raise. Reaching cover takes precedence over sensor contact that tick. The two sensor updates are simultaneous in effect; hearing is the stable primary cause if both commit on the same tick.

## Headless check

```powershell
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . --script res://tools/duet/verify.gd
```

`golden.json` stores run-length encoded public inputs, semantic checkpoints, committed signposts and SHA-256 of the full tick tape. The verifier compares the fixed-tick and batched APIs, audits cue lead and linkage, checks footing and freeze math, and runs a policy using the public markings and live readings after a delayed throw. All-watch, all-creep and blind alternation each fail. A same-state fork shows the opposite sensor effects of one iron stride; substituting iron response for felt on the normal trace leaves the Listener's warning armed to its deadline. The replays also cover voluntary retreat, automatic recovery followed by a win, and an occupied leaf at its return deadline.
