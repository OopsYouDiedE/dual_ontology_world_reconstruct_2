# A07 / Strata: The Harness Tower

Bring the reversible core to the Crown with enough bank to open the hatch. At an anchor, Copper turns stored harness strain back into charge; Ceramic vents more quickly without supplying the bank. The same core determines which path physically fits and whether the rack motor and hatch can draw power. Hand work builds strain to regenerate later; boost spends some of the bank to climb without an immediate overload. The top-level cue clock counts sustained load, separate from current strain.

Use `W` climb, `B` boost, `U` unload, `T` change core, `H` Crown hatch, and Space wait. `R` resets; `Tab` switches between the two overview sections and the tracking close view. HUD and site labels show the exact physical meters and available actions. One decision spans 20 ticks at 60 Hz.

| Key boundary | What to inspect |
|---:|---|
| 100–220 | Copper climbs the lower rack and returns strain to the bank at Switchback. |
| 240–300 | The press visibly interrupts the circuit before changing the core. |
| 380–460 | Ceramic advances along the narrow stair. The bank does not change on the span. |
| 600–700 | Back in Copper, boost spends bank to clear the steep rack. The Crown arrives without enough charge to open. |
| 840–920 | Copper regeneration fills the hatch reserve. The hatch begins its countdown, then opens at tick 901. |

The second tape starts in Ceramic and opens at tick 841, with a narrower charge margin. The control waits under preload: strain warning first, trip and Sump cradle next, then a clean retry. The counterfactuals in `tools/strata/README.md` include two paths with the same height, charge and strain but different live trip clocks.

The cast bronze, ceramic, stone, and iron all use the mainline HallFinish shader. Frame receipts attest the Forward+ 1280×720 native scene, Hall04 baseline, shared InkPass 0.40, MSAA 2× and SDFGI. The arch is generated the same way as other Gothic lab bays using ArchBuilder. Both materials and camera angles remain visually distinct without changing authoritative state.
