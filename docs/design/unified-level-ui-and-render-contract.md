# 《沉睡学院》全关卡统一构建流水线、操作、渲染、台词与队友交互契约

所有现有关卡（公共大厅、战役房间、北翼远征 `Expedition-01`）以及未来新增的任何章节、房牌或实验关卡，**必须**接入同一套基础设施，**只允许通过显式能力开关声明关卡特例**（例如公共大厅不能跳跃：`allow_jump = false`）。

## 0. 分层与唯一入口（强制）

| 层 | 唯一入口 | 只认识 | 不允许 |
|---|---|---|---|
| 关卡逻辑 | `AcademyLevelRuntime.install(host, ui_parent, caps, opts)`（`scenes/components/shared/AcademyLevelRuntime.gd`） | 运行时 API：`interactions`、`handle_input`、`toast/say/thought`、`set_view_provider`、`set_wheel_options_provider` | 自建 HUD / 字幕 / 轮盘，直接调用 `sync_groups` |
| 场景可选物品 | `AcademyInteractable` + 子节点 `AcademyHotspot`（`scenes/components/interaction/`），或向 `runtime.interactions.register_provider()` 注册返回 `AcademyInteractionSchema` 描述的 Callable | 纯数据 + `activated` 信号 | 引用任何 UI 节点 |
| 交互调度 | `AcademyInteractionDirector`（运行时持有） | 描述数据 → `presenter.sync_groups`；激活 → `action_requested` / `dialogue_requested` | — |
| 交互 UI | `DualModeInteractionHud`（presenter） | 描述数据（id / title / anchor_world / hotspots[callback]） | 读取场景节点 |
| 渲染与后处理 | `AcademyLevelPipeline.bootstrap_viewport(vp, world_env, caps, attach_parent)` → `AcademyStage` | 环境、MSAA/阴影、HallInk、EssenceShift | 关卡自行 `Stage.environment()` / `ink()` / 创建后处理 Pass |
| 物品 | `AcademyFurnitureCatalog`（关卡清单）与 `ComponentFactory.load_catalog()/create_entry()`（ArchBuilder 目录） | 目录条目可带 `interaction` 默认值 | 直接读 `catalog.json`、绕过目录生成家具 |

解耦示例（场景可选物品 ↔ UI 展现）：

```gdscript
# 场景侧：只声明数据（也可在 ArchBuilder 组件库里点 “Make selectable” 后编辑同样的属性）
var it := AcademyInteractable.attach_to(chest, {"id": "chest", "title_en": "Chest", "title_zh": "木箱",
	"verb_en": "Search", "verb_zh": "翻找", "action_id": "search_container"})
it.activated.connect(func(hotspot_id, action_id): _open_chest())
# 关卡侧：安装运行时，提供视点；UI 自动发现并呈现场景里的 AcademyInteractable
var rt := AcademyLevelRuntime.install(self, ui_layer, AcademyLevelPipeline.capabilities_for("campaign_room"))
rt.set_view_provider(func(): return {"camera": cam, "rect": rect, "vp_size": rect.size, "player_pos": p, "can_show": true})
```

关卡清单（`AcademyLevelBase`）中的 `interactables[]` 会生成 `AcademyInteractable` 节点；`objects[]` 可写 `interaction: {from_catalog = true, action_id = ..., dialogue_id = ...}`，交互挂在物品节点上，审计同样校验认知防火墙与台词引用。

**强制门禁：** `AcademyArchitectureAudit`（`scenes/components/shared/AcademyArchitectureAudit.gd`）逐行扫描正式运行时目录，凡在白名单之外新建 HUD/字幕/轮盘、直接 `sync_groups`、自建渲染环境或后处理、依赖 `blue_prince_lab`、或直接读 `catalog.json`，`tools/test/architecture_unity_test.gd` 即失败；`python tools/inspect_level.py` 同时打印该门禁结果。

```powershell
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . -s res://tools/test/architecture_unity_test.gd
```

该测试还覆盖：场景节点 ↔ UI 只经描述数据与信号往返、解锁旗标、目录物品交互、ArchBuilder（BuildingSimulator）与组件库（物品属性检视器）加载共享目录并编辑物品交互属性。

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
- **台词与字幕**：所有角色对白、内心独白与过场字幕（大厅霍铎、16 居民、北翼远征、`StoryDirector`）统一走 `UnifiedDialoguePresenter`（底层复用 `AcademyCaptions.gd` 底部字幕条 + `VoiceSynth.gd` 纯人声共振峰）。
- **队友交互**：所有关卡统一按 **`Q`** 呼出 `UnifiedTeammateWheel`（底层复用 `AcademyCommandWheel.gd` 34px 中心取消死区 + 235px 径向扇区轮盘），支持鼠标悬停、滚轮、`1-5`、`E / Enter` 确认与 `Esc / Q` 取消。

## 6. 统一家具库与材质规范（`AcademyFurnitureCatalog.gd`）
- 入口：`scenes/components/shared/AcademyFurnitureCatalog.gd`
- 合并第一章（`ExpeditionKit` / ArchBuilder 配方）与主线（`PublicHallGothic` / KayKit CC0 / 学院定制 GLB）所有家具资产，禁止在单关卡内对整件家具强行平涂单一材质覆盖。
- 统一 9 套 1900s 欧洲官邸与哥特教堂 PBR 材质：`walnut_varnish`（三平面木纹法线 + 清漆）、`oak_aged`（陈年橡木）、`brass_antique`（拉丝古黄铜）、`iron_wrought`（哑光锻铁）、`linen_cream`（粗纺亚麻）、`wool_baize`（学院毛呢）、`leather_oxblood`（牛血红皮革）、`beeswax_candle`（暖蜂蜡）、`slate_honed`（精磨石板）。
