# Human-like Sol playtest

Standalone first-person exploration of `Sortie.tscn`. Run from the repository root in PowerShell:

```powershell
$godot = '.runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe'
New-Item -ItemType Directory -Force .runtime/human-sol | Out-Null
& $godot --headless --fixed-fps 60 -s tools/expedition/human_sol_test.gd
& $godot --headless --fixed-fps 60 -s tools/expedition/human_sol.gd -- --rogue-mcp-dir= --run-seed=31 --profile=curious --ticks=24000 --output=.runtime/human-sol/curious.json
& $godot --rendering-method forward_plus --max-fps 75 -s tools/expedition/human_sol.gd -- --rogue-mcp-dir= --profile=curious --ticks=4900 --capture=.runtime/human-sol/curious-forward.png
```

The empty MCP directory argument enables the game's existing look InputMap actions without installing an external MCP controller. All movement and interaction use player inputs. The scene runs normally, including collisions, acceleration, and game-rule updates.

| Profile | Sensory reaction | Style |
| --- | ---: | --- |
| `cautious` | 12 physics ticks | Quiet input, shorter commitments, moderate heading persistence |
| `curious` | 16 physics ticks | Right-hand wall following by default, with short visible-floor steps, three-height scans, and stuck recovery |
| `direct` | 21 physics ticks | Walking, longer commitments and stronger straight-ahead preference |

Policy receives one snapshot per decision, held for the profile's reaction delay. Current pose is used by the input actuator for pitch feedback. The policy uses own planar odometry and heading, local samples through the active camera, displayed interaction prompts, command-wheel titles and captions. Screen depth is approximated by rays on visible collision-backed geometry (9 m); decorative meshes without colliders, shading and pixel-level legibility are outside this model. `Label3D` text passes projection, range, apparent size, facing, and depth checks; the sensor emits only text and bearing. Returning to an earlier sign uses the player's own previously observed viewpoint and the current safe lanes. There is no route table, access to puzzle flags, stored landmark coordinate, or use of node names for navigation.

`curious` estimates wall offset from screen-visible flank rays, prefers to keep about 0.78 m of offset, and still requires supporting floor for each movement. It stops to sample low, middle, and high reticle angles during exploration and recovery. Recovery watches its own displacement (including turns and stationary decisions); it remembers movement attempts stopped by collision as local cell/heading penalties. It only resumes walking along a lane supported by the delayed camera sample. A full recovery sweep can switch the wall side.

`SOL_RESULT` / JSON includes visible prompts, captions and milestones, sampled player trail, elapsed ticks, displacement, and outcome. Interaction events include the originating observation tick. `longest_dwell` is the start/end of the longest post-start period without clearing 0.65 m from the displacement anchor. `sampled_heights` reports actual sampled pitch ranges and how often a prompt appeared, independently of the requested motor pitch. `0` means an ending card appeared, `1` means failure card or exhausted budget, and `2` means invalid invocation or report output error. Read the Godot log alongside the report for engine/script errors. The default policy is exploratory; an observed area or prompt alone does not count as a mechanic cleared.

After a visible Hale caption confirms a blocked route and suggests the archive or a side door, all three profiles can rewind up to 72 decisions along their own recent odometry breadcrumbs. They inspect both flanks at successive stations, steer toward a currently readable `ARCHIVE` sign only along visible supported lanes, and drop the detour search when its budget is spent. A confirmed dead end is penalized based on the feet position where Sol heard the confirmation. Collision-stopped headings are remembered locally, and the same reading prompt is consumed once per run. These memories are cleared with every new policy instance.

When a nearby companion explicitly invites Sol along, the policy can follow a person currently visible through the camera. The sensor checks several height bands on visible skinned figures against the viewport and depth rays. Only a bearing and approximate range enter the delayed snapshot. A lost silhouette allows a short stationary search; walking still requires a visible floor lane. No actor destination or quest flag is used. Per-run reports record `visible_person_samples` and pursuit decisions.
