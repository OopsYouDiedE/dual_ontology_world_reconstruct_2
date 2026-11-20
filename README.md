# The Sleeping Academy

规则怪谈、克苏鲁与梦核题材的单局肉鸽。Godot 4.7.2 .NET / .NET 8；唯一游戏入口是 `scenes/rogue/Run.tscn`。

## 一局怎么玩

- 第一人称，从一张印刷规则卡开始。**Tab** 收起或翻开；**WASD** 移动，点击场景控制视角，**Esc** 释放鼠标，**E** 交互。
- 玩家独自出发，在到达公共大厅前会遇到 1–2 名幸存者；解开房间后可邀请同行，也可以独自离开。前段会遇见回声走廊、时间雨和试图改写保命规则的馆长。照印刷版可保命；读懂环境证据可以抢到更多补给。死亡时能自写或编辑一条留给下任队长的规则边注。
- 名单共四名 NPC；在大厅手动招募未入队的人，招募与出征分开，出征可带至多三名。安排疗伤、用探索补给升级设施，或在滑块拼图中连接通向观测台的可选路线；常规路线一直开放。
- 查看[夜行学院重构说明](docs/design/night-expedition.md)，了解完整操作、系统和测试。

## 开发运行

```powershell
dotnet build DualOntologyWorldReconstruct2.csproj
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64.exe --path . -- --run-seed=1
```

`core/rogue_topology/` 实现连接约束的传播、带权塌缩与回溯。`scenes/rogue/HouseMap.cs` 负责营地、招募与营后的区域结构。`scenes/rogue_rules/` 保存房间线索、规则、队员专长及驻地观察界面。Godot 用 Forward+ 和 SDFGI 按画面显示尺寸渲染 Lowpoly 场景，文字用窗口分辨率绘制。

## 建筑、营地与美术

建筑使用项目原有的建筑编辑器。营地居民使用项目自研的需求与物件交互逻辑；出征后由队长指挥。FreeSO 客户端、原版游戏数据和 VM 快照不作为这两项功能的启动条件。

热厨的[白模、叠绘提示和复现命令](docs/design/kitchen-paintover/README.md)用于固定入口视角，再据图调节三维场景、物件动作和光照。

## 晚祷簿 · 可选双本体调查

在公共大厅选择 **Investigate Vesper Index**。翻书切换 1903 年火灾与 1907 年调查现场，转动煤油灯，把另一个年份的手轮或桥面照进当前房间。取回登记簿可为本局增加一条档案证据和一份补给。也可从建筑实验的 **Vesper Index** 直接试玩。[操作、实图参考与测试](scenes/blue_prince_lab/vesper/README.md)。

## 大楼梯厅美术实验

从正常入口附加 `-- --architecture-lab`，可对照九个固定机位：柱廊、礼拜堂、林门、营地、圆窗阁楼、倾台陀飞轮、蓝图选房、监控室和暗房检视。`H` 隐藏样板工具栏，仍可操作画面内的纸面界面。正式出征的 Public Hall 和 Observatory 在合适的地块内安装带玻璃的地面陀飞轮。见[实机九宫格、操作与复现步骤](scenes/blue_prince_lab/README.md)。

## 检查

```powershell
dotnet run --project core/rogue_topology/tests/DuelView.RogueTopology.Tests.csproj
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . -s res://tools/test/house_map_bridge_unit.gd
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . -s res://tools/test/night_expedition.gd -- --no-rule-save
```

[实机 MCP](mcp/game/README.md) 从正式入口启动真实 Forward+ 窗口；可通过界面点击检查画面，报告与截图写入 `.runtime/rogue-mcp/`。旧版 `rogue_run_e2e.py` 按第三人称流程编写，不是当前规则怪谈入口的回归测试。
