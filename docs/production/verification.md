# 验证｜先锁规则，再走进房间

在仓库根目录运行。首次从干净检出启动，先用项目环境的 `prepare` 准备 Godot 4.7.2 .NET 和 .NET 8。Windows PowerShell：

```powershell
$g = (Resolve-Path .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe).Path
dotnet build DualOntologyWorldReconstruct2.csproj
& $g --headless --editor --import --path .
```

**规则测试回答「每种选择是否成立」。** 固定营地、闸、天文台，检查 256 个种子各生成两次、六张房牌不重、全部可达、每条边向前。战役集成实际做招募、过实体门、返营、恢复和敲钟。检查退出码及日志内的错误；正常结算应走完三局。

```powershell
dotnet run --project core/rogue_topology/tests/DuelView.RogueTopology.Tests.csproj
& $g --headless --path . -s res://tools/expedition/route_test.gd
& $g --headless --path . -s res://tools/test/night_watch.gd -- --no-rule-save
```

**资产测试回答「实际放进房间的东西是否正确」。** 建筑测试覆盖调参、连接与墙洞；改墙时还应从洞中央和两侧实体分别测通行。光照检查普通室内灯与外窗的分工。人物检查正式加载器、骨架、测量记录与逐表面 Toon；非无头运行另拍三视图。活动角色按[人物放行标准](characters.md)验证动作与身份迁移。人物检查覆盖 16 位居民的变体、骨骼动作与侦探三视图，使用真实 Forward+。

```powershell
& $g --headless --path . -s res://tools/building_construction/tests/production_pipeline_test.gd
& $g --headless --path . -s res://tools/test/room_daylight.gd
& $g --path . --rendering-method forward_plus -s res://tools/expedition/production_cast_test.gd
```

**实机测试回答「人能否看懂并走过去」。** [游戏 MCP](../../mcp/game/README.md) 用 `on(scene="rogue", seed=2)` 进真实 Forward+，查看 `room=camp`、`phase=camp`、`moves=0`、手册已发、两个可选出口。通过 `step` 操作、`observe` 查看、`close` 回收本次进程。自动走线复用同一输入桥，项目 Python 需已装 MCP 依赖与 Pillow：

```powershell
$env:DV_GODOT = $g
& .runtime/python/Scripts/python.exe tools/expedition/viewport_run.py --seed 1 --lane east --out .runtime/route-east
& .runtime/python/Scripts/python.exe tools/expedition/viewport_run.py --seed 2 --lane west --out .runtime/route-west
```

每局保存六张 1080×720 JPG 和一份 `frames.json`。先核对折返前后库存与结局，再按[入口全景、走近操作](art.md)复看画面。沿[布局](layout.md)记录入口、操作位和出口回望；检查路线图预告、门牌与实体门指向一致。给第一次玩的玩家遮掉提示，问「哪边能回营？为什么留这个工具？」把答错的位置记到该房的修改单。独立物理实验、规则解题基准在各自场景验证，不能代替这条出征测试。
