# 《沉睡学院》全关卡统一构建流水线、操作、渲染、台词与队友交互契约

所有现有关卡（公共大厅、战役房间、北翼远征 `Expedition-01`）以及未来新增的任何章节、房牌或实验关卡，**必须**接入同一套基础设施，**只允许通过显式能力开关声明关卡特例**（例如公共大厅不能跳跃：`allow_jump = false`）。

## 1. 统一关卡构建流水线与特例能力表（`AcademyLevelPipeline.gd`）
- 入口：`scenes/components/shared/AcademyLevelPipeline.gd`
- 所有关卡通过以下两行完成标准引导：
  ```gdscript
  var caps := AcademyLevelPipeline.capabilities_expedition() # 或 capabilities_hall() / capabilities_campaign_room()
  var stage := AcademyLevelPipeline.bootstrap_viewport(viewport, world_env, caps)
  var ui := AcademyLevelPipeline.bootstrap_ui_stack(self, ui_layer, caps)
  ```
- **显式特例能力对照**：
  - **公共大厅（`capabilities_hall`）**：`allow_jump = false`（大厅不能跳）、`allow_lamp = false`、`allow_stomp = false`、`is_safe_hub = true`；其余（双模三态交互 UI、底部字幕、Q 队友轮盘、渲染与相机）100% 统一。
  - **战役房间（`capabilities_campaign_room`）**：`allow_jump = false`、`allow_lamp = false`、`allow_stomp = false`；其余 100% 统一。
  - **北翼远征与后续探索关（`capabilities_expedition`）**：`allow_jump = true`、`allow_lamp = true`、`allow_stomp = true`；其余 100% 统一。

## 2. 统一渲染与相机契约（`AcademyStage.gd`）
- 固定共享参数：`BASE_FOV = 73.0`、`EYE_HEIGHT = 1.57`、`LOOK_SENSITIVITY = 0.0022`、`PITCH_LIMIT = 1.48`、MSAA 4x、Filmic 色调映射、`HallInk` 原分辨率描边、`EssenceShiftPass` 与 `gl_compatibility` 自动补光。

## 3. 统一操作键位与跨关卡持久化偏好（`AcademyUnifiedInput.gd`）
- **`E`**：全游戏唯一主交互键（C+ 集合式与底特律分散式一致）
- **`V`**：任意时刻热切换交互样式（**C+ 集合式** ↔ **底特律分散式**），自动持久化至 `user://academy_ui_prefs.cfg` 并跨关卡同步
- **鼠标滚轮 / `1-4`**：仅在 C+ 集合式多动作目标锁定时切换/直选动作
- **`Q`**：全游戏统一呼出队友径向轮盘（大厅、战役房间、北翼远征一致）
- `R`：提灯开关（受 `allow_lamp` 门控）；`F`：跺脚试探（受 `allow_stomp` 门控）；`Space`：跳跃（受 `allow_jump` 门控，大厅禁用）；`Tab / I`：外勤手册；`F8`：中英文切换；`Esc`：释放鼠标 / 关闭叠层

## 4. 统一双模三态交互 UI（`DualModeInteractionHud.gd`）
- 全关卡共用「**潜在激活点（4.6–9.5m）→ 可激活点（2.85–4.6m）→ 当前选择点（≤2.85m 且准星 ≤24°）**」三态标准，禁止任何单关卡另写居中纯文本交互提示。

## 5. 统一台词字幕与队友交互（`UnifiedDialoguePresenter.gd` + `UnifiedTeammateWheel.gd`）
- **台词与字幕**：所有角色对白、内心独白与过场字幕（大厅霍铎、16 居民、北翼远征、`StoryDirector`）统一走 `UnifiedDialoguePresenter`（底层复用 `ExpeditionCaptions.gd` 底部字幕条 + `VoiceSynth.gd` 纯人声共振峰）。
- **队友交互**：所有关卡统一按 **`Q`** 呼出 `UnifiedTeammateWheel`（底层复用 `CommandWheel.gd` 34px 中心取消死区 + 235px 径向扇区轮盘），支持鼠标悬停、滚轮、`1-5`、`E / Enter` 确认与 `Esc / Q` 取消。
