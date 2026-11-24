# Evidence Register

Batch A candidate: a standalone cutaway room for Academy 4A (blind handoff) + 4B (evidence persuasion and override). The revised manual expresses a narrow, explicit exception. The scene opens directly to play, without a campaign save or seed.

## Run from the repository root (PowerShell)

```powershell
$godot = '.runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe'
& $godot --path . --rendering-method forward_plus res://scenes/physics_lab/evidence_register/EvidenceRegister.tscn
& $godot --headless --path . --script res://tools/evidence_register/Verify.gd
```

Start on the Moon plate by appending `-- --register-plate=2` to the launch command. The plate only changes the mark. The renderer uses `Hall04.tres` as its baseline, HallFinish for all opaque room geometry, and shared InkPass at 0.40 with 2× MSAA at native scale. Standard materials are confined to the status lens and the two translucent diagnostic cones. The set uses the shared room geometry helpers and ArchBuilder's pointed-rib recipe.

## Controls and routes

Click stations and contextual buttons, or use the keys printed on them. The blue Runner moves between four stations; the Clerk is an independent deterministic rule reader at a fixed desk. `V` toggles indicative view cones. `R` resets the current plate; `Tab` opens the alternate plate and resets the case.

| Station | InputMap actions and keys |
|---|---|
| `register_survey` (1) | `register_take_prism` (Q), `register_take_wax` (W) |
| `register_drawer` (2) | `register_send` (E), `register_show` (F), `register_sun` (Z), `register_moon` (X), `register_release` (U), `register_override` (O) |
| `register_proof` (3) | F, Z, X, U, O (same actions as above) |
| `register_threshold` (4) | `register_brace` (B), `register_file` (Enter) |
| Global | `register_optics` (V), `register_reset` (R), `register_plate` (Tab) |

- **Clean:** pick up amber and load it at the Drawer. After the 30-tick blind slide, confirm the mark on the dial. At Proof, raise the slide for 40 consecutive visible ticks. Request Release under the revised Edition IV, then stamp at Threshold once the latch settles (24 ticks after release).
- **Counterfactuals:** the hidden live sample registers its mark yet fails as optical proof. The wax copy registers the same mark and is fully visible at Proof; it never revises the rule. Lowering or moving breaks an incomplete proof. The revised rule requires a matching receipt for the live sample; substituting wax closes the latch.
- **Override:** breaking the seal releases the latch immediately, adds one debt and starts a 120-tick warning. Move to Threshold and fit the brace to keep the latch open when the Clerk pulls the shutter, then stamp the emergency docket. With no brace, the Clerk jams the latch; live proof and a regular Release can recover the filing while preserving the debt.

## Harness / MCP handoff

- Scene ID suggestion: `evidence_register`. Entry: `res://scenes/physics_lab/evidence_register/EvidenceRegister.tscn`. The root exposes a read-only `mcp_observe() -> Dictionary`. Register the route and scene allowlist externally; this candidate leaves the shared MCP files unchanged.
- `mcp_observe()` reports the exact 60 Hz model tick, separate Runner/Clerk vision results, tray/receipt/dial state, proof streak, manual AST, pressure and shutter countdown, latch, stamp, outcome and the most recent receipt events. Its `render` object reports native scale, MSAA sample count, ink opacity, actual SDFGI state, viewport size, renderer and shared resource paths. Drive with the `register_*` InputMap actions. Poll `walk_ticks_left`, `drawer_ticks_left`, `proof_ticks` and `stamp_ready` for interactive replay; Godot process-frame counts may vary relative to 60 Hz physics ticks.
- `golden.json` contains a canonical clean Sun sequence and counterfactuals for hidden amber, interrupted proof, visible wax, mismatched dial, emergency, recovery and wax substitution. Each row issues its action on the first tick and idles for the remaining model ticks. `Verify.gd` replays every case twice, checks exact transitions and render material bindings, and exercises the scene through real input dispatch.
- To run the same harness with a real Forward+ viewport, optionally capturing arrival/proof/filed images under `.runtime/academy-mechanisms/evidence-register/`:

```powershell
& $godot --path . --rendering-method forward_plus --resolution 1280x720 --script res://tools/evidence_register/Verify.gd -- --register-images
```

The two figures are abstract role markers. The 27-ray optics use deterministic segment tests against the partition and hood; the optional cone overlay illustrates viewing direction. Station movement and the Clerk's panic are scripted; autonomous teammates are outside this candidate. Pending: shared MCP registration and the independent full 20-hour red-team run.
