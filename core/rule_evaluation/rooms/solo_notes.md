# Rooms 01-02: teaching pair

## 01 | The Synchronizer

The lead and lag cams visibly rise into their engaged states. Both must be engaged when the player presses the center latch. The latch stays set after the cams separate; the player walks around the assembly to the exit. Pulling the latch out of phase is harmless. At 60 Hz the visible dwell is 160 ticks engaged and 80-120 ticks disengaged, with at least 100 ticks of simultaneous engagement every cycle. Seed variation changes the cam period, lag, and trim.

- First-person capture: compare cams at room tick 20 (lead only), tick 80 (both engaged), and tick 100 (both engaged, latch lowered). Include the entrance sightline and the right bypass.
- Intended discovery: read the phase plates from the entrance, then keep both cams in view from the center aisle, within reach of the latch.

## 02 | The Inspection Gallery

Four upright and arm silhouettes are presented in a row. The leftmost master establishes the high- or low-arm standard for this seed. One of the three production brackets reverses it. The corresponding REJECT button stays down when selected; a new selection replaces the previous one. The exit accepts the actual geometric mismatch. Fault bay, master polarity, and trim vary independently.

- First-person capture: entrance comparison, each silhouette polarity, then a depressed REJECT button from its approach lane.
- Intended discovery: scan across the front of the gallery; move sideways to align with a bay before pressing its button. The central gap is the route to the exit.
- Keep operation effect records engine-side. The visible control state is the selected button, and the arm geometry is the clue to the mismatch.

Both rooms use recoverable gates with no damage or random outcomes. Initial validation exercised 256 seeds against the draft contract using both phase-offset sign conventions, 275 mm horizontal collision clearance, center distance, and witness conditions. A second 256-seed scan used the shared integer ray and movement primitives. The entrance arrays at yaw 0, -7 and +7 degrees collectively hit every gallery arm; the unrotated array hit all witness interaction targets from their action positions. Forward+ screenshot review remains a separate checkpoint.

Shared World integration: 256 seeds, two replays per seed, identical state hashes at every decision, all reaching CAMP with zero panic and full sanity. The longest two-room witness takes 440 ticks (7.33 simulated seconds).

## Forward+ review and follow-up

One Astra review inspected the six `review-v1` runtime images. The reviewer could not read local scene files from its sandbox, so fixture and simulation behavior were cross-checked locally. The initial latch view cropped both cams; the cams now sit farther beyond the lower console, and the witness operates the latch from farther back. The gallery comparison sign now hangs in front of the bracket row. The selected button drops; public operation effects describe selection only. Both rooms expose the exit interlock without publishing the geometry answer.

Renderer follow-ups: fixed high-contrast alignment marks behind the cams; a mobile handle in a stationary latch housing; a persistent REJECT flag driven by a bay's `selected` bit; HUD placement that leaves labels clear; and a visible exit bolt or opening motion. For recapture, include an entrance view, both phase states from the same pose, an unsuccessful attempt, correct operation, and crossing the threshold. Use an entrance panorama or short master-to-bays sweep for the gallery.
