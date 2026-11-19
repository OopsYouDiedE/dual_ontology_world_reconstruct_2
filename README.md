# The Sleeping Academy

规则怪谈、克苏鲁与梦核题材的单局肉鸽。Godot 4.7.2 .NET / .NET 8；唯一游戏入口是 `scenes/rogue/Run.tscn`。

## 一局怎么玩

- 玩家独自进入学院。通往大本营的路上会遇到 1–2 名同行者，他们自动入队。初次抵达营地约经过 10–20 个不同房间（含入口与营地）；折返会增加移动次数。
- 营地可休整、了解专长，选 0–3 名同伴出发。探险时玩家担任队长：读房间里的线索、选择全队行动，也可以把符合专长的任务交给一名队员。每名队员回营休整后可再次出手。
- 用原来的第三人称操控走进房间，靠近现场按交互键调查，再决定全队的行动。例如，热厨里要比对水汽与哨声；行动后可翻阅记录的规则。错误选择扣 3 点生命，同一房间只结算一次。抵达最终房间并记录三条不同规则即可唤醒学院；通关或死亡后可重玩同一种子或另开新局。
- 学院是一张超自然连接图。门连接到哪个空间由本局种子和房间连接约束决定；两个地块的外墙、楼层与现实距离无需对得上。

## 开发运行

```powershell
dotnet build DualOntologyWorldReconstruct2.csproj
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64.exe --path . -- --run-seed=1
```

`core/rogue_topology/` 实现连接约束的传播、带权塌缩与回溯。`scenes/rogue/HouseMap.cs` 负责营地、招募与营后的区域结构。`scenes/rogue_rules/` 保存房间线索、规则、队员专长及驻地观察界面。Godot 用 Forward+ 和 SDFGI 按画面显示尺寸渲染 Lowpoly 场景，文字用窗口分辨率绘制。

## 建筑、营地与美术

建筑使用项目原有的建筑编辑器。营地居民使用项目自研的需求与物件交互逻辑；出征后由队长指挥。FreeSO 客户端、原版游戏数据和 VM 快照不作为这两项功能的启动条件。

热厨的[白模、叠绘提示和复现命令](docs/design/kitchen-paintover/README.md)用于固定入口视角，再据图调节三维场景、物件动作和光照。

## 大楼梯厅美术实验

从正常入口附加 `-- --architecture-lab` 可打开独立样板，查看 Blue Prince 参考构图、第一人称和可交互机关。见[操作、几何节点生成与验收](scenes/blue_prince_lab/README.md)。

## 检查

```powershell
dotnet run --project core/rogue_topology/tests/DuelView.RogueTopology.Tests.csproj
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . -s res://tools/test/house_map_bridge_unit.gd
& .runtime/python/Scripts/python.exe tools/testing/rogue_run_e2e.py --seed 1
```

[实机 MCP](mcp/game/README.md) 从正式入口启动真实 Forward+ 窗口；测试通过界面点击操作，报告与截图写入 `.runtime/rogue-mcp/`。
