# The Sleeping Academy

规则怪谈、克苏鲁与梦核题材的单局肉鸽。Godot 4.7.2 .NET / .NET 8；唯一游戏入口是 `scenes/rogue/Run.tscn`。

## 一局怎么玩

- 第一人称。从 **Night Dispatch** 的实体递件柜领取夜班守则。**WASD** 移动，点击场景控制视角，**Esc** 释放鼠标或放下文件，**E** 检查、操作、穿门，**Tab** 翻开随身手册。**Q / R** 也可转身。
- 公共大厅前会遇到 1–2 名幸存者，他们带着另一版守则。面对冲突可以分开工位、错开时段，或由玩家临时按同行者的一版操作。到大厅以后，证词与现场记录或队伍的信任才能推动统一守则。
- 通过公共大厅，去观测台为本局队伍鸣响晨钟。每个关卡都有多条做法；勘察、工具准备与风险选择的代价不同。16 名可交谈居民加侦探继续用仓库原有的 17 个模型。[完整设计与解法](docs/design/night-watch.md)。

## 开发运行

```powershell
dotnet build DualOntologyWorldReconstruct2.csproj
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64.exe --path . -- --run-seed=1
```

`core/rogue_topology/` 实现连接约束的传播、带权塌缩与回溯。`scenes/rogue/HouseMap.cs` 负责种子分支、入队节点和大厅前后的连接结构。正式关卡、证据和设备动作位于 `scenes/rogue_crossing/`。Godot 用 Forward+ 和 SDFGI 按画面显示尺寸渲染 Lowpoly 场景，文字用窗口分辨率绘制。

## 建筑、营地与美术

建筑使用项目原有的建筑编辑器。营地居民使用项目自研的需求与物件交互逻辑；出征后由队长指挥。FreeSO 客户端、原版游戏数据和 VM 快照不作为这两项功能的启动条件。

热厨的[白模、叠绘提示和复现命令](docs/design/kitchen-paintover/README.md)用于固定入口视角，再据图调节三维场景、物件动作和光照。

## 大楼梯厅美术实验

从正常入口附加 `-- --architecture-lab`，可对照九个固定机位：柱廊、礼拜堂、林门、营地、圆窗阁楼、倾台陀飞轮、蓝图选房、监控室和暗房检视。`H` 隐藏样板工具栏，仍可操作画面内的纸面界面。正式出征的 Public Hall 和 Observatory 在合适的地块内安装带玻璃的地面陀飞轮。见[实机九宫格、操作与复现步骤](scenes/blue_prince_lab/README.md)。

## 检查

```powershell
dotnet run --project core/rogue_topology/tests/DuelView.RogueTopology.Tests.csproj
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . -s res://tools/test/house_map_bridge_unit.gd
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . -s res://tools/test/night_watch.gd -- --no-rule-save
& .runtime/python/Scripts/python.exe tools/night_crossing/viewport_run.py --seed 1
```

[实机 MCP](mcp/game/README.md) 从正式入口启动真实 Forward+ 窗口；可通过界面点击检查画面，报告与截图写入 `.runtime/rogue-mcp/`。旧版 `rogue_run_e2e.py` 按第三人称流程编写，不是当前规则怪谈入口的回归测试。

## 十关规则博弈评测

[评测说明](docs/design/rule-evaluation.md)包含独立第一人称场景、Forward+ 审查入口、确定性见证、基准运行和黑盒选手协议。
