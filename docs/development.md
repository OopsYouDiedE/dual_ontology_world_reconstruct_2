# 开发手册

构建与工具链见[仓库 README](../README.md#工具链与构建)。本手册覆盖 Godot 启动、源码定位和主线验证；建筑器的几何规则见[建筑房间拓扑](building-topology.md)。

## 启动入口

`project.godot` 启动 `Boot.tscn`。`LaunchRoute.gd` 先选择正式标题、隔离分段、检查点或工作台。`Main.tscn` 提供标题与书桌案卷；`New Game`／`Continue` 加载 `DualWorldMain.tscn`，并共享同一套剧情和存档规则。`Continue` 只查主线存档。

| 入口 | 用途 |
| --- | --- |
| 默认启动 | 正式标题，进入五日主线、建筑器或生活模拟 |
| `--dv-scenario=<项目内 YAML/JSON>` | 用正式剧情渲染器进入隔离分段，使用独立测试存档 |
| `--dv-snapshot=<项目内 JSON>` | 恢复本项目的实机开发检查点及演出状态 |
| `--dv-workbench --scenario=<项目内 YAML/JSON>` | 道具、灯光、表情、建筑等开发预览 |
| `--dv-campaign-lab` | 旧 C# 剧情原型；用于历史兼容检查 |

以上参数放在 Godot 命令行的 `--` 后。每次只选一个入口；工作台的 `--scenario` 用于选配置。需要周期检查点时显式传入 `--dv-checkpoint-output=<项目内 JSON>`；该路径配置后 `F6` 可保存手动快照。剧情存档和开发检查点分别保留各自的格式。

## 源码与目录

| 路径 | 内容 |
| --- | --- |
| [`assets/data/dual_world/`](../assets/data/dual_world/) | 剧情节拍、房间、人物、证物、争执与结局定义 |
| [`scenes/main/`](../scenes/main/) | Godot 启动与标题；生活模拟的 C# 桥接 |
| [`scenes/dual_world/`](../scenes/dual_world/) | `DualEngine` 消费剧情数据和存档；`DualWorldMain` 同步房间、输入、对话与演出 |
| [`scenes/components/`](../scenes/components/) · [`assets/materials/`](../assets/materials/) | 共用交互、角色、材质、世界与检查点组件 |
| [`core/`](../core/) · [`assets/data/scenarios/`](../assets/data/scenarios/) | 独立的生活模拟 CLI、DV 声明、运行时与推理 |
| [`assets/data/test_scenarios/`](../assets/data/test_scenarios/) | 有名称的分段和开发夹具、巡检清单、评估配置 |
| [`mcp/`](../mcp/) · [`tools/`](../tools/) | 项目操作协议、构建、开发探针和内容工具 |
| `artifacts/` · `.runtime/` | 实机证据和评审产物；本机运行、缓存与临时输出 |

修改剧情先定位稳定的节拍、房间或资源 ID。房间素材和场景引用沿用原 `res://` 路径，例如同一厨房道具继续承担原有取证和复演。改变地图、动作或视角后，在实际房间复测动线、角色重叠、证物视线和英文提示。

## 剧情流程与验证

主线合并[四区开场](../assets/data/dual_world/opening.json)与 [`dual_world.json`](../assets/data/dual_world/dual_world.json) 的时间线推进。`DualEngine` 逐拍处理房间限制、取证门槛、选择和分支；界面负责把这些状态呈现为对话、现场交互、复演和转场。第一天的结算在 **22:00** 后、晚间分工已落实且待办清空时出现。玩家点 `Chapter 2` 后，第二天从 R05 接续。

### 按交接点检查

| 起点 | 重点核对 |
| --- | --- |
| 标题到厨房 | `New Game` → R05 起身 → 走廊 → B-P。采样时检查进入近景、手势、返回、入账和后续提示。 |
| `kitchen-reconstruction` | 看复演、试错、调整顺序并确认。回到房间后检查时钟继续和下一拍出现。 |
| `service-maintenance`、`cross-c-window`、`cross-d-pressure`、`shaft-question` | 记录实际开放的门、线索和角色；能换序时对照两种可达顺序，检查主线交接与回访。 |
| `poem-stakeout` / `poem-expose` / `poem-indulge` | 复现各预选结果；测试选择本身需从 `d1_poem_hint` 之前的玩家保存点开始。 |
| `dinner-plan` | 从分工前开始，等到 22:00，点 `Chapter 2` 并观察 R05。`chapter-night` 用于定位已结算界面。 |
| `day2-wind`、`day3-case`、`day4-control` / `day4-valve`、`day5-morning` | 逐日定位风窗、案件、风险处置和最终选择，实际推进一个交接；结局以页面和规则状态共同核对。 |

分段入口在 [`segments/`](../assets/data/test_scenarios/segments/) 中，以 `before_beat` 标记起点。批量巡检按 [`mainline_survey.json`](../assets/data/test_scenarios/mainline_survey.json) 选择场景。改一个节拍或镜头时，先从最近检查点复现；验证相邻段交接优先沿用上一段玩家操作形成的真实存档。

### 结果按测试方法记录

- **规则回归**：`tools/test/story_contract.gd` 验证五天节拍、章节边界、存档与取证规则；记录供给证物和选择的测试条件。`tools/test/story_navigation.gd` 检查阀廊取证路径和名录库门口净空。
- **定点与巡检**：游戏 MCP `focus_open` / `focus_step` 或评估 MCP `scene_survey`，分别记录起点、操作、到达状态和截图。诊断夹具保留在测试证据中。
- **连续实玩**：从正式标题用普通操作通关，同一会话保留时间、房间、动作和待办；参照[第一天连续路线](../mcp/evaluation/day-one-route.md)。验 `Continue` 时另启独立回读记录，引用原存档来源。
- **正式分段**：冻结提交后按[评估手册](../mcp/evaluation/README.md)准备独立观察者、参考图和七项同步采集。分段状态、缺测和原始失败由[评审流程](../mcp/review/README.md)发布。
