# Goal
Refactor the existing codebase, architect a comprehensive automated evaluation workflow, and implement a standardized Model Context Protocol (MCP) server to complete the engineering, visual alignment, and narrative testing tasks for the following repository:
https://github.com/OopsYouDiedE/dual_ontology_world_reconstruct_2

Your primary objectives are:
1. Provision the required Godot Engine environment and execute automated offscreen tests.
2. Build the **Story Loader**, **Automated Scene Tester**, and **MCP Evaluation Server** with real-time HTML reporting (`artifacts/review/index.html`), outputting code changes as clean commits/patches on the single main branch and embedding evaluation reports as required.
3. Implement **English Localization (`en`)** across the entire project and enforce an **Action-Over-Words Narrative Standard** (replacing descriptive text with real skeletal animations, IK, and PBR `Decal` surface traces, retaining only essential spoken English dialogue).
4. Establish an **Iterative Scene-to-Image (`obs()` -> `Astra` Img2Img -> Engine Parameter Alignment) Loop** to overcome LLM visual tuning limitations.
5. Refactor the **In-Situ Macro Interaction System**, **Art/Design Visual Assist Scene (`InteractionTest`)**, **Motion/Facial Alignment Pipeline**, and **Three-Stage Mind Deduction System**, prioritizing the **Main Storyline (Chapter 1 full walkthrough)** while testing specialized UI and assist scenes in parallel.
6. **Scope Boundary**: Do NOT alter core gameplay rules or underlying plot truths ("no game design scope creep"). Focus strictly on physical action presentation, decal rendering, camera work, localization, tooling, repository hygiene, and visual/performance compliance.

### SubAgent Orchestration
You are authorized to dispatch and coordinate the following specialized SubAgents:
- **`Terra`**: Responsible for runtime telemetry capture, blind playtesting as an independent English-speaking player, and quantitative rubric scoring.
- **`Astra`**: Responsible for taking current live scene captures (`obs()`) and generating enhanced aesthetic, lighting, facial expression, and UI reference renders (Img2Img Ground Truth). If built-in image generation tools are unavailable, invoke pre-configured CLI/API endpoints directly without pausing for human confirmation.
- **`Sol`**: Responsible for dependency resolution, deduplicating input/UI/state handling logic, enforcing strict repository and Git single-branch hygiene, and purging temporary/one-off tool scripts.

---

# Constraints

### 1. Engine, Localization & Runtime Environment
- **Engine Version**: **Godot Engine 4.7.2-stable (.NET / C# Edition)** (formerly Mono).
- **Mandatory English Localization (`en`)**:
  - Integrate Godot's native `TranslationServer` pipeline (`res://localization/translations.csv` or `.po`).
  - Enforce `TranslationServer.SetLocale("en")` at startup across all game modes and tests.
  - All UI labels, object nameplates, interaction prompts, character spoken lines, and MCP trajectory logs (`event_script`, `character_script`) MUST be written and evaluated **100% in English**.
- **Offscreen Virtual Display Rendering**:
  - MCP automatically selects a working native display and renderer when available. If no usable native display is available on Linux, MCP provisions and starts an isolated **Xvfb** display for rendered tests, and cleans up its owned display process.
  - **DO NOT pass the `--headless` CLI flag during visual or camera testing**, as `--headless` activates Godot's `Dummy` rendering driver and produces black/empty frames on `obs()` capture. Use the standard Godot Forward+ rendering pipeline with the available native renderer, or with Xvfb backed by hardware EGL or Mesa `llvmpipe`/`lavapipe` when needed, so PBR shaders, `Decal` projections, shadows, and post-processing render authentically.
- **Testing Interface Prohibition**: Strictly PROHIBITED from using OS-level `Computer-use` (GUI mouse/keyboard emulation) commands. All execution, stepping, and inspection MUST be performed exclusively via the project's MCP tools.
- **MUST use https to open local html**

### 2. Global Engineering Discipline, Repository Hygiene & Anti-Deadlock Laws (Highest Priority)
1. **Hard Directory Isolation**:
   - The ONLY legal working directory is `dual_ontology_world_reconstruct_2`.
   - **Strictly PROHIBITED** from launching, reading, referencing, or falling back to the legacy repository `dual_ontology_world_engine`. Every MCP entry point, startup script, screenshot handler, and telemetry logger must validate the workspace path and process PID upon initialization.
2. **Strict Repository & Git Hygiene (Zero-Bloat & Single-Branch Law)**:
   - **NO Git Branching**: Work exclusively on the current default branch. Creating side branches, temporary branches, or detached worktrees is strictly forbidden.
   - **Zero One-Off Tool/Test Residue**: Do NOT leave behind single-use Python/Bash scripts, temporary migration utilities, ad-hoc test scenes, raw unindexed screenshots, `.tmp`/`.bak` files, or orphaned `.import` artifacts in the repository. Any temporary helper script created during execution MUST be deleted immediately after its task finishes, and `Sol` must verify a clean working tree (`git status`) before every milestone commit.
3. **SubAgent Communication & Concurrency Protocol**:
   - SubAgents (`Terra`, `Astra`, `Sol`) may communicate with the Main Agent **ONLY at task initiation and task completion**. Mid-execution status chatter that interrupts the main thread is strictly forbidden.
   - Mainline bug fixing, code cleanup (`Sol`), and independent blind testing (`Terra`) must proceed in parallel, with `Terra` testing only verified, committed snapshots.
4. **Mandatory Separation of Fast Loop (Debugging) & Slow Loop (Acceptance)**:
   - **NEVER use a full-game playthrough from the Title Screen via `Terra` for routine bug hunting!**
   - **Fast Loop Self-Check (< 5 seconds execution time)**: Whenever modifying room door coordinates, NPC transforms, furniture tweens, decals, or evidence macro cameras, load the target room directly via `open_scene(path)` or `test_game(save_file)` with injected Mock state and run automated code pre-checks:
     - *Anti-Clipping & Pathfinding Pre-check*: Verify character spawn points and navigation corridors do not overlap (NEVER fallback-stack multiple actors at `(0,0,0)`). Verify `NavigationAgent3D` path continuity from room entrances to all interaction points without NPC collider blockage.
     - *Macro Camera Raycast Occlusion Pre-check*: When zooming `Camera3D` toward any interactable or evidence decal/node, cast a physics ray (`PhysicsRayQueryParameters3D`) from `Camera3D.GlobalPosition` to the target's `Aabb` center. If the ray hits a wall, door panel, or unrelated furniture first, programmatically adjust the camera offset or reparent the evidence node under its proper host mesh until the ray achieves a 100% unoccluded hit.
   - **Slow Loop Acceptance**: Only after all interactables and state transitions in a room pass the Fast Loop may you spawn a **fresh, context-isolated `Terra` instance** (provided ONLY with control rules, zero story spoilers) to perform a blind English playthrough from the Title Screen.
5. **Automated HTML Report Generation & Throttling**:
   - All scoring trajectories, before/after comparison screenshots, and diagnostic rationales must be batch-compiled into browsable HTML dashboards (`artifacts/review/index.html`) and Markdown (`artifacts/review/scoring_overview.md`) with zero broken local asset links.
   - **Throttling Rule**: During Fast Loop iterations, append only lightweight `.yaml` telemetry logs. Trigger full HTML rendering and link validation ONLY upon completing a room/chapter milestone or immediately prior to termination.
6. **8-Hour Circuit Breaker**:
   - Total cumulative execution time is capped at **8 hours**. Upon reaching the 8-hour boundary, immediately halt new feature edits, purge all temporary files, terminate all child Godot/Xvfb processes, export the final HTML evaluation report, commit all changes to the main branch, and output a structured handover manifest.

---

# MCP Specification

The project's MCP server must expose the following standardized tools (refactor or implement them if missing or non-compliant). The MCP layer must internally abstract all cross-platform CLI discrepancies, automatically provisioning Godot 4.7.2 .NET, a native display or `Xvfb` when needed, English locale flags (`--language en`), and process lifecycle handlers:

- `main_game()`: Launches the complete game in English starting from the Title Screen and save-slot selection menu.
- `test_game(save_file: str)`: Bypasses the Title Screen and save-selection UI, booting directly into a specific mainline story checkpoint defined by `save_file` (or injected Mock state payload).
- `open_scene(path: str)`: Boots directly into the specified `.tscn` scene path for Fast Loop verification, visual script inspection, and `Astra` look-dev loops.
- `step(decision: str) -> dict`: Executes a single agent decision/action step produced by prior reasoning and returns the subsequent observation state payload.
- `event_script(text: str)`: Appends non-dialogue narrative observations in English (character physical actions, decal inspections, environmental changes, sound cues, camera transitions) witnessed since the previous step to the current trajectory log.
- `character_script(text: str)` *(maintain alias `charactor_script` for backward compatibility)*: Appends essential spoken English dialogue observed since the previous step to the current trajectory log.
- `obs() -> Image`: Captures and returns the current offscreen framebuffer viewport as a PNG image.
- `quit()`: Gracefully terminates the active Godot instance and cleans up its associated `Xvfb` virtual display process.
- `add_score(trajectory_id: str, category: str, score: float, rationale: str = "")`: Appends a quantitative rubric score and diagnostic note to a specific recorded gameplay trajectory segment, triggering incremental updates to the HTML report pipeline.
- `see_score(trajectory_id: str) -> dict`: Retrieves the aggregated scoring handle and breakdown for `trajectory_id` (used by the Main Agent; omitted for blind `Terra` operators).

---

# Core Design & Engineering Specifications

### Section 1: Story Loader & Real-Time Telemetry HUD
1. **Real-Time Telemetry Overlay**: Mount a bottom HUD overlay during story testing (and record silently in the background during formal mainline runs) tracking:
   - **Framerate Metrics**: Average FPS (`Avg FPS`), `5% Low FPS`, and `1% Low FPS`.
   - **Frame Pacing & Hardware Telemetry**: Frame Time `P95` and `P99` (ms), `Draw Calls` per frame, and memory footprint (`VRAM MB` / `RAM MB` via Godot `Performance` and `RenderingServer`).
   - **Audio Loudness Telemetry (ITU-R BS.1770-4 / EBU R128 Standard)**: Measure K-weighted **Integrated Loudness (`LUFS`)**, **Short-Term Loudness (`LUFS`)**, and **True Peak (`dBTP`)** across the Master audio bus. Maintain a lock-free ring buffer of **at least 15 seconds** to guarantee zero dropped audio frames.
   - **Wall-Clock Timestamp**: Formatted as `YYYY-MM-DD HH:MM:SS`.
   - **Asynchronous Zero-Overhead Law**: Screenshot PNG encoding and audio analysis MUST execute on background worker threads (`WorkerThreadPool`), never blocking the main render thread.
2. **YAML Telemetry Persistence**: Serialize all telemetry metrics automatically into structured `.yaml` reports segmented by timeline and story room node (`bedroom`, `corridor`, `kitchen`, etc.).

### Section 2: Action-Over-Words Narrative, PBR Decals & In-Situ Macro Camera
Redesign the narrative delivery and interaction system around three foundational pillars:

#### Pillar A: Physical Skeletal Actions & Spoken-Only English Dialogue
- **Eliminate Descriptive Text**: Strictly PROHIBITED from using narration boxes, action brackets (e.g., *"[He nervously checks the jammed lock]"*), or inner-monologue walls of text to describe physical events.
- **Full-Body Animation + Procedural IK**: Convey character intent, hesitation, discovery, and physical struggle through **actual 3D skeletal animations (`AnimationTree` state machines)** combined with **`LookAtModifier3D` (head/eye tracking)** and **`SkeletonIK3D` (hand reach alignment to props)**.
- **Essential Spoken Dialogue Only**: Retain ONLY essential spoken lines that characters must verbally exchange to advance plot logic. All dialogue must be in **concise, natural English** (strictly **<= 12 words or <= 60 characters** per screen).

#### Pillar B: PBR Decal Rendering for Surface Traces & Micro-Details
- **Mandatory Use of `Decal` Nodes**: All environmental and bodily surface traces—including door-gap water stains, boot prints, chalk dust, blood/chemical splatters, wood gouges, and scratch marks—MUST be implemented using Godot 4 **`Decal` projection nodes** (or high-resolution localized detail normal/ORM masks on characters) rather than flat floating polygons or glowing spheres.
- **Full PBR Material Response**: Every `Decal` must bind **`TextureAlbedo`**, **`TextureNormal`**, and **`TextureORM`** (Ambient Occlusion, Roughness, Metallic) so traces react realistically to dynamic room lighting and macro camera specular highlights (e.g., wet water stains under the door must use `Roughness < 0.15` to catch grazing light; metallic copper shavings must use `Metallic > 0.85`).

#### Pillar C: In-Situ Macro Camera & Interaction Presentation
> **[In-Situ Interaction Iron Law]**: All interactions with furniture (wardrobes, beds, windows) and crime scene evidence (e.g., the 7 pieces of evidence in the kitchen) **MUST be executed 100% inside the original room using the primary scene camera (`Camera3D`) zooming into and driving the original scene nodes directly!**
> **Strictly PROHIBITED** from creating separate close-up `.tscn` scenes or duplicating evidence meshes inside isolated `SubViewport` containers. Evidence meshes and `Decal` nodes must be parented directly under their physical host nodes (doors, windows, cloth racks) to preserve exact spatial transforms, smoothly interpolating `Camera3D` back to the exploration perspective upon completion.

| Category | Prohibited Legacy Pattern | Mandatory 3D In-Situ Presentation (Skeletal Action + Decal + Tween) |
| :--- | :--- | :--- |
| **Furniture / Mechanisms**<br>*(Wardrobe, Ratchet Lock, Vent Grille)* | Character stands idle while a 2D text box pops up: *"The wardrobe is empty."* | **Skeletal Reach + Procedural Actuation (`Tween`)**: Character physically steps to the anchor and reaches out via IK; the original wardrobe door rotates open over `0.2s` with ease-out damping and wooden resonance SFX; `Camera3D` pitches and dollies forward so the player visually inspects the interior *(retaining the neatly hung coat inside the bedroom wardrobe as required by the plot)*. When inspecting the ratchet lock, the character jiggles the handle while the gear mesh exhibits micro-jitter, metallic clanking SFX, and scratch `Decal` wear, visually proving it is *"deadlocked from the inside."* |
| **Bodily Traces**<br>*(Back-of-hand Scratches, Torn Cuff, Palm Copper Shavings)* | Popping up a static 2D icon with text explanation. | **In-Situ 3D Pose Alignment & Surface Detail**: When inspecting the Detective, the character raises their 3D right-hand skeletal mesh directly into the primary `Camera3D` macro focal plane (with normal-mapped scratch `Decal` / detail textures catching the light as the wrist rotates). When inspecting Su Ling's cuff, dolly `Camera3D` to a macro framing anchored by her wrist; allow the player to drag the 3D `[Hand Scratch]` node into direct spatial alignment with her `[Torn Cuff]` mesh in-scene so both models physically interlock and reveal the *"pulled backward from behind"* force vector. |
| **Environmental Micro-Traces**<br>*(Door-gap Wet Linen Fibers, Boot Prints, Chalk Dust)* | Placing a glowing sphere on the floor that vanishes on click. | **PBR Decal + Swab/Sampling Micro-Interaction**: Render the puddle/boot print/chalk dust via a PBR `Decal` projected seamlessly onto the floor/board geometry. Transition `Camera3D` to an unoccluded 45-degree or top-down macro angle. Transform the cursor into a 3D "Fingertip / Tweezers" tool; dragging across the `Decal` surface physically lifts 3D wet linen fibers or purple-gold crystals into the macro foreground edge for direct visual comparison. |

---

### Section 3: AI Visual Enhancement Loop (Scene Capture $\rightarrow$ `Astra` Img2Img $\rightarrow$ Engine Alignment)
Because LLM code agents have weak innate visual/lighting intuition whereas generative image models (`Astra`) excel at composition, lighting, and material rendering, you MUST execute the following closed-loop workflow for all scene look-dev, UI alignment, and lighting tasks:

1. **Step 1: Baseline Scene Capture (`obs()`)**:
   - Load the target scene via `open_scene(path)` or `test_game(save_file)` and capture the current raw viewport (`raw_capture.png`) via `obs()`.
2. **Step 2: Structure-Preserving Reference Generation (`Astra` Img2Img)**:
   - Pass `raw_capture.png` along with the scene's narrative/atmospheric prompt to **`Astra` (Image-to-Image / ControlNet depth-guided conditioning)**.
   - Instruct `Astra` to preserve the exact 3D camera perspective, architectural layout, and prop silhouettes while generating a high-fidelity reference render (`target_ref.png`) featuring cinematic lighting, realistic contact shadows, proper color grading, and rich PBR surface textures.
3. **Step 3: Quantitative Vision Diff & Deterministic Engine Tuning (No Blind Guessing)**:
   - **Do NOT blindly guess Godot lighting numbers.** Run an automated image comparison pass between `raw_capture.png` and `target_ref.png` to extract concrete deltas:
     - **Luminance & Exposure Delta**: Compare mean luminance and 5th/95th percentile brightness histograms $\rightarrow$ deterministically adjust `WorldEnvironment.Environment.TonemapExposure`, `AmbientLightEnergy`, and `DirectionalLight3D.LightEnergy`.
     - **Color Temperature & Tint Delta**: Compare mean RGB channel ratios in lit vs. shadow regions $\rightarrow$ adjust `DirectionalLight3D.LightColor`, `FogLightColor`, and `AmbientLightColor`.
     - **Contrast, Specular & Surface Detail**: Compare high-frequency edge gradients and specular highlights $\rightarrow$ tune `SSAOEnabled`, `SSREnabled`, `GlowIntensity`, PBR material `Roughness`/`Metallic` values, and `Decal` `AlbedoMix`/`Normal` strength.
     - **Camera Framing Alignment**: Adjust `Camera3D.Fov` and local transform offset so key subject bounding boxes match `target_ref.png`.
4. **Step 4: Verification Iteration**:
   - Re-capture via `obs()` and compute perceptual similarity (SSIM / LPIPS + rubric evaluation) against `target_ref.png`. Repeat Steps 3–4 (typically 2–3 fast iterations) until the live Godot render achieves **>= 8.0 / 10.0** aesthetic similarity.

---

### Section 4: Quantitative Scoring Rubric (10-Point Scale, Pass >= 8.0)
**Never declare acceptance without full-process telemetry and blind evaluation data captured by an independent `Terra` SubAgent.**

1. **Gameplay Fluidity (`fluidity`)**:
   - `10`: Zero perceptible stutter throughout steady-state gameplay. `8`: Pass threshold.
   - `6` (Automatic Fail): Any human-perceptible frame pacing spike (**Frame Time > 33.3ms** or consecutive frame drops) during steady-state exploration, camera transitions, or interactions.
   - *Statistical Exemption*: The first `1.5 seconds` immediately following cold boot or cross-room scene loading are logged separately as a **Shader Warmup Window** and exempted from the 33.3ms veto rule.
2. **UI Text Density & English Compliance (`text_density`)**:
   - `10`: Zero narrative/prompt text on screen (100% pure visual/action storytelling).
   - `8`: Essential spoken English dialogue or prompt text **<= 12 English words (<= 60 characters)** on screen simultaneously, with zero untranslated non-English strings.
   - *Counting Rule*: Count ONLY dialogue and interaction prompt characters where `node.IsVisibleInTree() == true`, `Modulate.A > 0`, and bounding rect intersects the active viewport. Closed `Book UI` pages, persistent character overhead `Nameplates`, and single-key action icons (e.g., `E`) are excluded.
3. **Skeletal Action, Decal & SFX Completeness (`action_sfx_integrity`)**:
   - `10`: Physical skeletal animations, IK, PBR `Decal` traces, and spatial SFX completely replace text descriptions without flaw. `8`: Pass threshold.
   - `6` (Automatic Fail): Any visual defect including mesh clipping, two characters overlapping at the same coordinates, foot sliding, floating/Z-fighting decals, broken IK poses, or `Camera3D` line-of-sight occlusion by doors/walls.
4. **Audio Loudness Compliance (`audio_loudness`)**:
   - Target Integrated Loudness **< -20.0 LUFS** and background ambient peaks **< -20.0 dBTP**. Any digital clipping (`>= 0.0 dBTP`) results in immediate failure.
5. **Visual Narrative Substitution (`blind_narrative_match`)**:
   - An isolated `Terra` SubAgent (blind to source script text) must infer the story events in English purely from `obs()` frames (character actions, decals, expressions) and audio cues via `event_script()` and `character_script()`. The Main Agent compares `Terra`'s blind English transcript against the canonical plot outline. `10` = exact semantic match; `>= 8` = pass.
6. **Reference Aesthetic Similarity (`aesthetic_similarity`)**:
   - Compare live `obs()` captures against `Astra` Img2Img Ground Truth reference images via the Section 3 loop. Must achieve `>= 8.0 / 10.0` similarity.
7. **Narrative Pacing & Coherence (`narrative_flow`)**:
   - Scored independently by `Terra` based on end-to-end story progression. Transition zones (such as corridors) must maintain natural exploration pacing and are strictly prohibited from dumping spoiler summaries. Pass `>= 8.0`.

---

### Section 5: Art & Design Visual Assist Scene (Named: `交互测试` / `InteractionTest`)
Build an independent visual authoring and verification scene (`res://scenes/interaction_test.tscn`, UI titled `InteractionTest` in `en` locale) that shares 100% of the underlying interaction codebase with the main game.
- **Global Text Redline**: Any frame inside the assist scene is strictly prohibited from displaying **more than 20 English words (or 100 characters)**.
- **Module 5.1: Character-Prop Single Interaction Matrix**:
  - Programmatically iterate through every character-furniture skeletal interaction, downscale captures slightly, and stitch the **Start, Mid-Action, and End frames into a single horizontal contact strip (or grid image)** for evaluation.
  - **Single-Variable Fix Iron Law**: When fixing an interaction defect (clipping, offset, teleportation), **each iteration may modify EITHER the Character (animation/anchor/IK/avoidance) OR the Prop (collider/interaction marker)—NEVER both in the same commit.**
- **Module 5.2: Multi-Time-of-Day & Window Light/Fog Specification (Applied to Mainline & Assist Scene)**:
  - Support presets for **Morning (`08:00`)**, **Noon (`14:00`)**, **Night (`22:00`)**, and **Fog (`Fog`)**.
  - **Spatial Confinement of Fog & Sunlight**: Volumetric/surface fog MUST be confined strictly to **window glass surfaces and exterior zones** (zero unmotivated indoor fog). Direct sunlight (`DirectionalLight3D`) must enter interiors exclusively through window apertures and designated openings.
  - **Virtual Shadow-Caster Ceiling Fix**: Eliminate indoor light leakage caused by open-top room meshes by adding an invisible ceiling mesh configured with `CastShadow = GeometryInstance3D.ShadowCastingSetting.ShadowsOnly`. Window close-ups must preserve clear window frames and indoor/outdoor exposure separation without blown-out white clipping (`>= 8.0` match against `Astra` Img2Img reference).
- **Module 5.3: Procedural Architectural & Decal Component Traversal**:
  - Programmatically traverse all states and combinations of **Walls, Half-Walls, Windows, Doors, Stairs, Floors, Light Fixtures, and Surface `Decal` Traces**, generating stitched comparison grids scored against `Astra` Img2Img references (`>= 8.0` pass).

---

### Section 6: Character Animation & Facial Expression Pipeline
1. **Video-to-Skeletal Motion Pipeline**: Implement and verify an automated motion import pipeline accepting video motion capture or standard `FBX/BVH/GLB` clips, performing Godot `SkeletonProfileHumanoid` retargeting and root-motion displacement calibration. Validate end-to-end using a test motion clip first, ensuring temporary conversion intermediates are cleaned up upon import.
2. **Facial Expression Alignment**: Align character blendshapes/facial rigs against `Astra` Img2Img Ground Truth expression sheets (`>= 8.0` similarity score).

---

### Section 7: Three-Stage Mind Deduction System (In-Situ Visual Performance)
Replace text-based deduction menus with an in-situ 3D visual performance answering **What happened (Truth)** and **Why it happened (Motive)** using physical animations and surface decals:
1. **Stage 1: Doubt Anchoring & Entry**: Smoothly dolly `Camera3D` into a key crime-scene prop or PBR `Decal` micro-trace to trigger the deduction state transition (ensuring unmistakable visual guidance once all required clues in a room are collected so players never get stuck).
2. **Stage 2: Truth Reconstruction (What)**: Use in-situ phantom/character skeletal replay animations and procedural furniture tweens to physically re-enact the objective sequence of events without narrative text blocks.
3. **Stage 3: Motive & Force-Vector Verification (Why)**: Pull into a tight macro close-up highlighting emotional posture, facial expression blendshapes, and physical force vectors (e.g., direction of struggle, deliberate sabotage `Decal` gouges) to lock in the motive and cleanly trigger the chapter progression state.
- **Acceptance**: Refine all three stages through the Section 3 `Astra` Img2Img loop until achieving `>= 8.0` similarity and narrative clarity.

---

### Section 8: Main Menu & Formal Exploration UI Alignment
1. **Clean Exploration Viewport**: The 3D scene must fill 100% of the screen during formal exploration, retaining ONLY localized English object/NPC nameplates and proximity interaction prompts (e.g., `E`). **Strictly purge all legacy top bars and sidebars from the old project.**
2. **Title & Book UI Alignment**: Pass current **Title Screen UI** and **Book UI** captures through `Astra` Img2Img to generate high-craft target designs, then align the layout, English typography, PBR/UI materials, and lighting in Godot to achieve `>= 8.0` similarity.

## User update — 2026-11-17: test reports and delivery

- All tests are tests of record. Do not classify reports as formal/informal, development/acceptance, or use those labels to hide scores.
- One test publishes all seven score dimensions together under one test ID, with a reason per dimension. Record missing measurements explicitly; never fill them using another test or revision.
- The report homepage shows the latest test per segment. Delete obsolete report pages and duplicated historical report content; do not move clutter to a history page.
- After every revision, complete the relevant checks, commit all completed revisions on the existing main branch, and push to its configured remote. This is standing authorization; no repeated confirmation is needed. Report any failed commit or push accurately.

## Benchmark scheduling — 2026-11-17

- Batch multiple gameplay segments into one rendered session and collect all seven dimensions per segment. This amortizes startup and audio analysis across the day.
- Reserve performance measurement windows for one rendered Godot instance. Finish builds, other engine runs, audio postprocessing and bulk image exports before the window; run those jobs between measurement windows. Lightweight orchestration may continue.
- Concurrent functional runs must retain their concurrency observations with their scores. Performance reports identify overlap explicitly. No numeric safe instance limit has been measured yet.
- To calibrate a limit, repeat the same committed revision, renderer, resolution, seed, scene and action trace with 1, 2 and 3 instances. Alternate single-instance controls between trials, exclude the same 1.5-second warmup windows, and compare per-instance P95/P99, low FPS and steady frames above 33.3 ms. Keep each trial's raw metrics; do not combine independent sessions into a baseline.
- After the optimization checks and commit, hand gameplay testing to a fresh isolated Terra. Terra owns its MCP sessions, observations, complete score batches and shutdown. Keep the committed source fixed for the duration of its test.

## Latest user scheduling and report update — 2026-11-17

- This scene batch permits up to three concurrent test-owned rendered instances, each capped at 60 FPS. Record concurrent load alongside performance scores. This supersedes single-instance scheduling for this batch.
- Run every planned scene, record exact failed or stalled phases, and publish all seven score fields together with evidence or explicit missing-measurement reasons.
- Keep only `artifacts/review/index.html`; delete `gameplay.html`. Update the already-open local report automatically when scene states or scores change.
- The user stopped the GPT-5.6 Terra tester. Do not resume or recreate that model for this task.

## 同一次测试同步完整采评硬要求 — 2026-11-17

- 用户指定首页“最新测试 · 全部七项评分”的 11 个剧情分段为重新评测与发布单位。使用 MCP 的分段场景或检查点入口，三路分配不同分段；禁止把三个代理都从标题页、新游戏或章节开头启动。同段多个场景保持同一测试 ID、实例与连续采集，结束时统一结算七项评分。上方 25 场景清单只作为对应分段的证据明细，不再独立展示一套重复评分。

- **每次测试必须从启动起同步采集全部七项评分所需证据，并在该次测试结束时一次性输出全部目标场景的完整七项评分。** `fluidity`、`text_density`、`action_sfx_integrity`、`audio_loudness`、`blind_narrative_match`、`aesthetic_similarity`、`narrative_flow` 的采集器、负责代理、独立盲玩观察和有效参考图必须在启动前全部就绪；各项采集与评判流程必须覆盖同一次实际测试过程，共用明确的测试 ID、源码版本、场景和时间轴。运行期间同步记录性能、可见文字、动态动作与音效、音频响度、盲玩叙事及节奏观察，并采集参考图对比所需画面；结束时使用本次同步采集的证据完成统计结算与评分，一次性将七项数值、理由、证据链接和失败卡点写入唯一首页并自动更新、核验、提交推送。**禁止先执行场景测试，再另开盲玩、音频、视觉或人工评测来拼成“一次完整测试”；禁止以事后补评计划、七个空字段或“场景执行结束”代替同步完整采评。** 测试前缺少任一采评条件，应先补齐测试配置与依赖；运行中出现采评中断，必须如实保留该次不完整记录并标为未完成，修复采集链路后重新执行受影响的完整场景测试，七项随重测一同采集，禁止跨测试或跨版本拼分。实测失败按量表和证据给失败分，禁止猜测分、默认分或将缺测强填零分。既定时间上限继续生效，到期保留未完成状态与具体阻塞，本条不自动延长测试窗口。

## Seven-score ownership and publication -- 2026-11-17

- Collectors calculate fluidity, text density, and loudness; observers classify text as needed and score action/SFX, aesthetic similarity, and narrative flow. After the segment, the main agent compares the blind observer's account with the canonical story, scores narrative match, and publishes the results. Keep evidence in the same test; do not repeat other reviewers' assessments.
- Always publish all seven numeric scores together for each test ID, with reasons, evidence links, and any problems annotated beside the affected scores. Score observed failures according to the rubric. If evidence for a score is unavailable, record 0 as a clearly labeled provisional missing-evidence penalty, state the cause and mark the test incomplete; do not present that value as a measured game-quality result or invent evidence. Repeat the affected test when the collection is repaired. This rule supersedes earlier instructions to leave scores blank or pending.

## Scoring clarification — 2026-11-17

- Compute text density from visible on-screen text automatically; exclude nameplates and single-key icons. Count unclassified visible text conservatively. Flag script issues without requiring per-string observer confirmation.
- Score `action_sfx_integrity` on visible physical action only; retain the field name for compatibility. Capture sound separately for audio evidence and loudness. These rules supersede earlier text-classification and action/SFX requirements.

- Use one gameplay observer for blind interpretation, physical action, narrative flow, and visual similarity. Record the blind interpretation before viewing story-revealing references; assess visual similarity against frames from the same session.

## Standard blind test flow — 2026-11-17

- One test agent plays and records its own English interpretation from the observed visuals and gameplay, including uncertainty, without access to the canonical plot. After the agent completes its account, it evaluates the same session against the visual reference. At the end, the main agent compares the recorded blind account with the true plot and scores narrative match. Keep all assessments tied to the same test ID and session.

- In blind gameplay the test agent uses MCP images and visible English UI for decisions and story interpretation. Hide internal scene, controller, navigation and story-state fields from the observer; transport identifiers and collection records are for the main agent.

## Mandatory segment entry — 2026-11-18

- Start every run for the current segment-testing task, including MCP startup/shutdown diagnostics, redaction checks and blind gameplay, at the explicitly assigned segment scenario or checkpoint. For the wake segment, use `assets/data/test_scenarios/wake.yaml` with its matching simultaneous assessment plan.
- Verify the segment entry arguments before launching. If the scenario/checkpoint or required assessment configuration is missing, stop and prepare it before starting a process. Never fall back to the title screen, new game or chapter opening.
- Calling `on(backend="godot")` without an explicit segment entry is prohibited for these tasks. Lifecycle diagnostics follow the same entry requirement as gameplay tests.
- Launch from the title screen only when the user explicitly requests a title/menu test. This rule supersedes earlier title-start instructions for segment testing.


## Latest user testing override — 2026-11-18

- Continue all remaining story segments in parallel with up to three test-owned rendered instances at 60 FPS. This supersedes the earlier single-observer scheduling for this batch. Each worker remains context-isolated from canonical story and owns its segment sessions.
- Use Terra with low reasoning for subsequent gameplay observers (available subagent selector: `gpt-5.6-terra`). This latest user selection supersedes the earlier restriction on that model.
- The user extended the execution window by eight hours: the deadline is now **2026-11-18 10:43:39 Asia/Taipei**, replacing 02:43:39.
- Disable audio recording and loudness postprocessing for the remaining batch. Mark audio as skipped by user request; preserve the seven-field report schema with an explicitly labeled provisional 0 for that unmeasured field. Evaluate the other six categories from each same-session test. Audio is no longer a launch prerequisite or reason to repeat a segment in this batch.
- Complete the remaining tests before giving the user the results; avoid interim result reports.
