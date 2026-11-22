# The Sleeping Academy

规则怪谈、克苏鲁与梦核题材的单局肉鸽。Godot 4.7.2 .NET / .NET 8；唯一游戏入口是 `scenes/rogue/Run.tscn`。

## 一局怎么玩

从 **Public Hall** 起步。先找居民组队、阅读随身手册，再在路线图上看候选房间和物资。西线房间产毛毡：消回声、防潮，结算时多保住物资；东线房间产棘轮：固定传动轴，缩短慢速通路。每间机关限装一件，徒手也有解。

全局地图的营地、折返闸和天文台位置固定。沿途六个位置从七种机关房里取六种；每局走其中三个。在 **Return Junction** 解闸后可以直接前进，也可以坐一次车返营休整，再从此处继续。终局在同一座观测台敲响晨钟。**WASD** 移动，点击场景控制视角，**E** 操作或过门，**Tab** 查手册，**Esc** 放下文件。也可点有名字的出口按钮选路。

[给下一位 AI 的定稿 PDF](docs/handoff/expedition/expedition-handoff.pdf) · [现役工作流、证据与专项入口](docs/handoff/expedition/README.md)。

## 开发运行

```powershell
dotnet build DualOntologyWorldReconstruct2.csproj
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64.exe --path . -- --run-seed=1
```

`core/rogue_topology/` 实现连接约束的传播、带权塌缩与回溯。`scenes/rogue/HouseMap.cs` 固定宏观站位，并为支路分配连线和房卡。正式关卡、证据和设备动作位于 `scenes/rogue_crossing/`。Godot 用 Forward+ 和 SDFGI 按画面显示尺寸渲染 Lowpoly 场景，文字用窗口分辨率绘制。

## 建筑、营地与美术

建筑使用项目原有的建筑编辑器。营地居民使用项目自研的需求与物件交互逻辑；出征后由队长指挥。FreeSO 客户端、原版游戏数据和 VM 快照不作为这两项功能的启动条件。

热厨的[白模、叠绘提示和复现命令](docs/design/kitchen-paintover/README.md)用于固定入口视角，再据图调节三维场景、物件动作和光照。

## 大楼梯厅美术实验

从正常入口附加 `-- --architecture-lab`，可对照九个固定机位：柱廊、礼拜堂、林门、营地、圆窗阁楼、倾台陀飞轮、蓝图选房、监控室和暗房检视。`H` 隐藏样板工具栏，仍可操作画面内的纸面界面。正式出征的 Public Hall 和 Observatory 在合适的地块内安装带玻璃的地面陀飞轮。见[实机九宫格、操作与复现步骤](scenes/blue_prince_lab/README.md)。

## 检查

```powershell
dotnet run --project core/rogue_topology/tests/DuelView.RogueTopology.Tests.csproj
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . -s res://tools/expedition/route_test.gd
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . -s res://tools/test/night_watch.gd -- --no-rule-save
& .runtime/python/Scripts/python.exe tools/expedition/viewport_run.py --seed 1
```

[实机 MCP](mcp/game/README.md) 从正式入口启动真实 Forward+ 窗口；可通过界面点击检查画面，报告与截图写入 `.runtime/rogue-mcp/`。旧版 `rogue_run_e2e.py` 按第三人称流程编写，不是当前规则怪谈入口的回归测试。

## 十关规则博弈评测

[评测说明](docs/design/rule-evaluation.md)包含独立第一人称场景、Forward+ 审查入口、确定性见证、基准运行和黑盒选手协议。
