# The Sleeping Academy

规则怪谈、克苏鲁与梦核题材的单局肉鸽。Godot 4.7.2 .NET / .NET 8；唯一游戏入口是 `scenes/rogue/Run.tscn`。

## 一局怎么玩

- 玩家独自进入学院。通往大本营的路上会遇到 1–2 名同行者，他们自动入队。初次抵达营地约经过 10–20 个不同房间（含入口与营地）；折返会增加移动次数。
- 营地可休整、了解专长，选 0–3 名同伴出发。探险时玩家担任队长：读房间里的线索、选择全队行动，也可以把符合专长的任务交给一名队员。每名队员回营休整后可再次出手。
- 越过会模仿说话的空泳池、决定该相信哪一面镜子，把观察到的规律记进可随时翻阅的手册。错误选择扣 3 点生命，同一房间只结算一次。抵达天文台并记录三条不同规则即可唤醒学院；通关或死亡后可重玩同一种子或另开新局。
- 学院是一张超自然连接图。门连接到哪个空间由本局种子和房间连接约束决定；两个地块的外墙、楼层与现实距离无需对得上。单个原版地块仍使用 FreeSO 的原生数据格式。

## 开发运行

```powershell
dotnet build DualOntologyWorldReconstruct2.csproj
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64.exe --path . -- --run-seed=1
```

`core/rogue_topology/` 实现连接约束的传播、带权塌缩与回溯。`scenes/rogue/HouseMap.cs` 负责营地、招募与营后的区域结构。`scenes/rogue_rules/` 保存房间线索、规则、队员专长及驻地观察界面。Godot 用 Forward+ 和 SDFGI 渲染 384×216 的场景，最近邻放大，文字用窗口分辨率绘制。

## FreeSO 原版建筑与人物

**Open FreeSO build tools** 从当前房间启动原版客户端。建筑编辑使用它的 Build Mode 与建筑命令；居民交互、寻路、自主行为交给原版 SimAntics。Godot 管理探险队伍与规则选择，显示来自原版地块的墙、地板、角色位置；没有地块时明确显示 *Topology navigation map*。一个客户端只向启动时选定的房间导出。营地对应 `camp.json`。可用 `--lot-dir=<绝对路径>` 更改默认目录 `.runtime/freeso/lots/`。

详见[客户端构建与启动](core/rogue_sim/README.md)、[原版 VM 快照](tools/freeso_bridge/README.md)。需要完整的原版依赖和本机授权的 TSO 游戏资产才能打开原版 UI 并观察真实人物。单独运行 Godot 可以验证肉鸽流程。

## 检查

```powershell
dotnet run --project core/rogue_topology/tests/DuelView.RogueTopology.Tests.csproj
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . -s res://tools/test/house_map_bridge_unit.gd
& .runtime/python/Scripts/python.exe tools/testing/rogue_run_e2e.py --seed 1
```

[实机 MCP](mcp/game/README.md) 从正式入口启动真实 Forward+ 窗口；测试通过界面点击操作，报告与截图写入 `.runtime/rogue-mcp/`。
