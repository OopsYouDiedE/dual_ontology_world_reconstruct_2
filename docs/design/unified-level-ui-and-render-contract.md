# 《沉睡学院》全关卡统一操作、渲染与交互 UI 契约

所有现有关卡（公共大厅、战役房间、北翼远征 `Expedition-01`）以及未来新增的任何章节、房牌或实验关卡，**必须**接入同一套操作、渲染与双模三态交互 UI 基础设施，禁止在单关卡内重复手写居中纯文本交互提示、自定义键位冲突或独立后处理参数。

## 1. 统一渲染与相机契约（`AcademyStage.gd`）
- 入口：`scenes/components/rendering/AcademyStage.gd`
- 所有第一人称关卡统一调用：
  ```gdscript
  var applied := AcademyStage.apply_to_viewport(viewport, world_env, true, attach_essence)
  ```
- 固定共享参数：`BASE_FOV = 73.0`、`EYE_HEIGHT = 1.57`、`LOOK_SENSITIVITY = 0.0022`、`PITCH_LIMIT = 1.48`、MSAA 4x、Filmic 色调映射、原生分辨率 `HallInk` 描边与 `gl_compatibility` 自动补光。

## 2. 统一按键与全局 UI 偏好契约（`AcademyUnifiedInput.gd`）
- 入口：`scenes/components/shared/AcademyUnifiedInput.gd`
- 全局无冲突标准键位：
  - `W / A / S / D`：移动；`Shift`：奔跑；`Ctrl`：静步；`Space`：跳跃 / 过场切句
  - **`E`**：全游戏唯一主交互键（集合式 C+ 与分散式底特律一致）
  - **`V`**：任意时刻热切换交互样式（**C+ 集合式** ↔ **底特律分散式**），自动持久化至 `user://academy_ui_prefs.cfg` 并跨关卡保持同步
  - **鼠标滚轮 / `1-4`**：仅在 C+ 集合式多动作目标（如傅科摆）锁定时切换/直选动作
  - `Q`：队友战术轮盘 / 快捷指令；`R`：提灯开关（独灯律）；`F`：跺脚试探；`Tab / I`：外勤手册；`F8`：中英文切换；`Esc`：释放鼠标 / 关闭叠层

## 3. 统一双模三态交互 UI（`DualModeInteractionHud.gd`）
- 入口：`scenes/components/shared/DualModeInteractionHud.gd`
- **三态视觉标准（全关卡一致）**：
  1. **潜在激活点（Potential，4.6m–9.5m）**：极微弱暗金呼吸微点 / 7px 淡金微菱形，零折线、零文字、右下角隐藏。
  2. **可激活点（Activatable，2.85m–4.6m 或非主热点）**：15px 空心黄铜菱形；C+ 右下角半透明预显（52%），底特律拉出极淡短折线与部位名。
  3. **当前选择点（Selected，≤2.85m 且准星夹角 ≤24°）**：高亮暖金双层菱形/圆环准星；C+ 右下角 100% 展开语境条，底特律拉出 45° 锐利折线与 `[E] 动作条`（同屏严格最多 1 个主锁定点）。
- **新关卡标准接入模板（10 行完成）**：
  ```gdscript
  const DualHud := preload("res://scenes/components/shared/DualModeInteractionHud.gd")
  var dual_ui := DualHud.new()
  # 挂入 UI CanvasLayer，然后在 _process() 传入当前关卡所有交互组：
  dual_ui.sync_groups(camera, viewport_rect, viewport_size, player_pos, groups, can_show)
  # 在 _input(event) 中委托处理 V / E / 滚轮 / 1-4：
  if dual_ui.handle_input(event): get_viewport().set_input_as_handled()
  ```
