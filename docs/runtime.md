# 运行时与目录

## 主线从哪里进

`project.godot` 启动 `Boot.tscn`。`LaunchRoute.gd` 先选择正式标题、隔离分段、检查点或工作台。`Main.tscn` 提供标题与书桌案卷；`New Game`／`Continue` 加载 `DualWorldMain.tscn`，并共享同一套剧情和存档规则。`Continue` 只查主线存档。

| 入口 | 用途 |
| --- | --- |
| 默认启动 | 正式标题，进入五日主线、建筑器或生活模拟 |
| `--dv-scenario=<项目内 YAML/JSON>` | 用正式剧情渲染器进入隔离分段，使用独立测试存档 |
| `--dv-snapshot=<项目内 JSON>` | 恢复本项目的实机开发检查点及演出状态 |
| `--dv-workbench --scenario=<项目内 YAML/JSON>` | 道具、灯光、表情、建筑等开发预览 |
| `--dv-campaign-lab` | 旧 C# 剧情原型；用于历史兼容检查 |

以上参数放在 Godot 命令行的 `--` 后。每次只选一个入口；工作台的 `--scenario` 用于选配置。需要周期检查点时显式传入 `--dv-checkpoint-output=<项目内 JSON>`；该路径配置后 `F6` 可保存手动快照。剧情存档和开发检查点分别保留各自的格式。

## 改动该放哪里

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
