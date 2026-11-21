# Kinetic pilot / author packet

You write a QuickJS `function decide(o)` (128 KiB source, 16 MiB heap). Sol has **40 minutes to author a program**. Only the frozen program competes. No network, OS, timestamps or seed. The referee accepts one integer each 1/60 s tick, up to 36,000 ticks per independent sample; wall limits 20 ms/step and 100 ms per aligned 20-step cycle. Timeout gives 0; the guest may restart at the next scan. These two rooms start with the first companion already present. Score is both bodies on the floor exit, not a ten-room campaign win.

## Perception

`{t,stage,feet:[x,z],yaw,manuals,rays}`. The two native sheets are known at briefing. The currently remembered companion sheet, sanity, panic and order are readable only on a lit crew hit. Local scanner origin `feet + (0,1.45,0)`; range 12 m; 3 elevations (−15°, 0°, +15°), each with 9 yaw offsets −60°…60° inclusive in steps of 15°. Zero faces −Z, positive yaw faces +X. Every 20th tick `rays` holds the 27 slots; otherwise `null`. A shadowed nearest hit occludes objects behind it and returns the same `null` as a miss. Sensor illumination = unobstructed vertical key or direct line to the inspection lamp within 5.8 m. Renderer ambient bounce and spectator overlays carry no information to the bot.

Environment hit: `id,kind,t,ticket,at` (world hit), `size` (local XYZ extents), `pose` (3 world basis columns then origin), `geometry` (mesh key). Published `mesh.mjs`/`studio.mjs` define all shapes and motion; the bot receives no instance seed or unobserved transforms. Driven parts expose period and handedness; indexed parts expose index. Bell has `k,bottom,pulse`; flywheel adds `tiltMax,spinRatio,axialHeight`; plate `loaded`, lever `latched`, door `open`, trolley/lamp `travel`. The local interlock AST is engraved on the plate, lever or trolley. Crew hit uses `center,size,at,rules,order,panic,sanity`. See `rules.mjs` for the rule operators (prefix `or,and,not,gt,eq`). `narrow` means within 0.55 m of the crosswall's Z; one memory variant widens separation there to .76 m.

## Physical actions

|Code|One tick of input|
|--:|---|
|0|Wait; an outstanding companion walk continues.|
|1,2,3,4|Captain steps −Z,+X,+Z,−X respectively, .08 m. Walls, bodies and the trolley block movement.|
|5,6|Captain turns scanner ±15°. Translation is in room axes.|
|8,9|Slide the inspection lamp left/right .04 m up to ±1.25 m. Captain must be within 1.4 m horizontally.|
|10…14|Order the companion to stand still or walk in one of the four cardinal directions, respectively, until replaced.|
|`1000+(round(10*x)+90)*181+round(10*z)+90`|Companion walks toward this tenth-metre coordinate, −9…9. Every tick checks its handbook and physical occupancy. No pathfinding, teleportation or through-wall reach.|
|15 / 18|Ask companion to pull the yellow lever / push the blue trolley one increment. Wrong object, out of reach, blocked or refused → no effect.|
|16 / 17|Unsupported tool order, 20-step override and +40 panic / reassure on scan boundary (−6 panic). Every beat panic can restore the native sheet, interrupt movement and erode sanity. Forced orders still check reach, interlocks and physical hazards.|

## Installation notes

18 m square; metres; body separation .58 m, solid wall clearance .23 m. Layout is public; initial phase and the selected assembly, optics and current positions must be sensed. The pilot admits 32 construction classes, selected by `seed mod 32`; the active class is not announced.

03: ten short arms start at radius .87, y=3.08; ten long canopy arms at .54, y=3.54. The ring drives have a temporal phase offset of 1.4 radians. Root motors spin about their own radial axes. Each cable is an .85 m damped pendulum with a moving pivot. Spring plate `(hand*2.4,4.75)`, lever `(0,2.96)`, reach .59. A gloved person can latch it while the plate is occupied. Once latched, the normalized shutter position tracks `clamp((min(bottom17,bottom18)-1.65)/.84,0,1)`, advancing at most .025 per step in either direction; it holds against a body beneath. Passage opens above .66. Exit strip `(0,−8.48)` lies beyond the shutter. Start `(0,6.55)` and `(1.5,6.55)`.

06: a single turned top on its tip, with 44 angular sections and three cuts (0,15,29). All three cuts go through the original turned body. Width 18.36 m; height 7.73 m along the axis. The model origin is 2.04 m up the tilted axis from the tip. Tilt `.16+.014*sin(2*a)` radians, self-spin `hand*spinRatio*a`; ratio 2, 3 or 4. Station `(5.05+trolleyTravel,4.97)`, reach .94 m. Trolley travel 0…2 m, .04 per successful push; it physically blocks the gap centered on `(6,4.4)`. `lookout` = captain north of z=4.02 (the far side). Two bodies must reach the marked area centered on `(8.1,3.15)`. Start `(5.8,8.1)` and `(7,8.35)`. Illustrations, unmeasured hazard bits, the referee implementation and reference bot are excluded from the author packet.

## Evidence is a checked inference

`cite(node,u,v,law,band)` in `starter.js` encodes a companion AST clause index (zero based), two **different scans of the same component**, an inference and a proposed clearance. A slot ticket is `(27*t/20 + slot)%1024`; oldest reading ≤680 steps ago, strictly ordered. Claim bands `[1.88,1.90,1.96,2.08]` metres. A reading outside the relevant work sector cannot establish the claim. No success flag is sent; observe your companion or the device.

* Law 0: at the flower's +Z handle between short-arm bells 2 and 3, one of the bounding bell bottoms is above the claimed height; show its change in height exceeds .045 m. Claim at least 1.88 m. This rejects a universal prohibition on handling a marked latch; it says nothing about the other sectors.
* Law 1: use two flywheel poses (sum of absolute changes in Y components of the basis axes ≥.012) and a measured hit `q`. Let `n` be the second basis column and `h = axialHeight = dot(q−poseOrigin,n)`. On the working annulus the mesh underside stays above local axial coordinate −.18 m. A conservative lower bound over the work area around the handle `s` is `q.y − (n.x*(s.x−q.x)+n.z*(s.z−q.z)+h+.18)/n.y − 1.2*tan(.175)`. Claim at least 1.90 m. The second measurement's bound must exceed the claim.
* The original clause must actually reject the measured operating case, and the proposed amended AST must accept it. The patch is `or(old, and(eq(site, thisTool), gt(workClearance, claim)))`. It is re-evaluated with the **current** space, tool, position and clearance on each operation. All other handbook clauses and the physical interlock stay in force. Two photographs at the same time, a strong claim without adequate clearance, or a correct claim about the wrong body produce no amendment.
