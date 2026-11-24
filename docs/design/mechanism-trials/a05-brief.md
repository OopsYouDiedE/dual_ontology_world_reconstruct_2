# A05 · The Afterimage Carriage

**Experimental round.** Check `decision.json` for the current gate status before review. This pack contains the exact frozen code and real Game MCP screenshots; it can be read entirely from files.

## What the player does

A dark channel divides the Hub from the Exit. A rotating carriage can dock West or East, and it only bears the player on the gangway visible in the active prism form. A powered move needs light and sound on the same beat, from distinct fixtures. The lamp's route goes through the prism in its **current** form. Wiring makes old fixed-fixture pulses survive; the carriage bell only sounds when operated live. The room has a one-way service ladder back to the Hub.

## Read the sequence

| tick | State and material evidence |
|---:|---|
| 0 | Neutral carriage, transmitting prism, West outline only. No walkable bridge. |
| 160 | Eight notches contain two wired pulses; the rewind control is ready. |
| 180–220 | The reel warns for 40 ticks, restores the position and prism, and starts the echo on the next beat. The spring clock stays outside the splice. |
| 260 | An echoed and a live pulse pair at the West receiver. The receiver lights; the swing is announced for 40 ticks. |
| 300 | West gangway carries weight; board the carriage. A timed return starts. |
| 320–360 | The prism warns for 40 ticks, then becomes reflective. The West gangway stops carrying the player and the East outline appears. |
| 360 | Echoed lamp light is routed to East and pairs with the present carriage bell. A 40-tick swing warning gets priority over the simultaneous spring deadline. |
| 400 | The East gangway is solid; the standard move reaches the Exit. |

## Counterfactuals and art

The original-size PNGs are in `frames/`. In `control-unpowered-bridge.png`, the West outline is plainly distinct from a physical gangway, and a normal move is refused. The headless report additionally checks a late bell, an absent past flash, wrong material state, continued spring time and late-but-valid timing. `golden.json` contains both equivalent recordings; `live-trace.json` includes each corresponding Game MCP decision and observed signals. There is no lethal step.

Opaque materials use the mainline HallFinish shader; Hall04, the 0.40 shared Ink pass and native-scale Forward+ are attested in `render-receipt.json`. Glass, route previews and light are special transparent surfaces. Alongside the physical route, inspect the live token, translucent echo, the bright receiver, the same-beat confirmation line and the reel. At a small thumbnail size, consult the original station-label frames.
