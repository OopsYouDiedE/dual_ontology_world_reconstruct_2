# Night Watch · Room Review

夜班主线的 11 种关卡白模，按流程顺序排成独立的审查路线。每种关卡只搭一间可测布局；种子生成的地块变体、关卡谜题和存档由原版主线保留。

```powershell
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64.exe --path . res://scenes/rubber_whitebox/room_review/RoomReview.tscn
```

在 Godot 打开 `RoomReview.tscn` 后也可按 **F6**。**N / B** 逐间前后切换，**M** 打开房间目录，**Tab** 在第三人称和斜俯视之间切换。走到出口地贴按 **E** 进入下一间；最后一间在晨钟地贴按 **E** 完成本轮审查。沿用测试角色的 WASD、滚轮、鼠标环绕、Backspace 复位和 H 隐藏 HUD。

| 序号 | 房间 | 白模检查重点 |
| --- | --- | --- |
| 01 | Night Dispatch | 入口能看到发放柜；排队护栏、退件架和直行出口 |
| 02 | Undeliverable Office | 退件围栏的门洞、接件台和侧边出口 |
| 03 | Blind Switchboard | 两个独立话亭、共用话线、中央通路 |
| 04 | Pump Archive | 湿区、泵控、干路穿过高位滴盘的净高 |
| 05 | Counterweight House | 吊笼与配重的占位、卷筒前空间、右侧逃生通道 |
| 06 | Dry Ward | 两条晾干通路、公共储物柜、传递柜 |
| 07 | Curator’s Barrier | 铃标与等待区、主闸口、检修旁路 |
| 08 | Public Hall | 集合通道、证人桌、康复区、勘察卷 |
| 09 | Fixing Room | 湿式冲洗和干式接触印的分区与进出 |
| 10 | Dispatch Exchange | 两条投递线、分隔与汇合、回执台净距 |
| 11 | Observatory | 晨钟视线、登记台和手摇轮的占位 |

`RoomPlans.gd` 以米记录房间边界、门洞、隔墙、机关占位和路线。`RoomBlockout.gd` 使用 ArchBuilder 的建筑文档、墙体开洞和多边形板几何生成实际碰撞；前墙做低墙剖切，屋顶留空便于检查。琥珀色地贴是主路线，青色是另行标出的支路。墙地与 Rubber Yard 共用 `RedRubber.tres`、`BlueRubber.tres` 和贴片着色器；`floor_grid_ink = 0` 可关掉浅色网格。统一固定中性审查灯，只用于读形、看地板和比较尺度。

## 检查与截图

```powershell
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . -s res://tools/testing/room_review_layout.gd
& .runtime/python/Scripts/python.exe tools/testing/room_review_capture.py
```

逻辑检查覆盖 11 个落地出生点、11 条主路线、3 条标记支路以及 10 个出口侧墙的角色胶囊碰撞。截图脚本使用项目游戏 MCP 的 `room_review` 模式，为每间保留走路视角和俯视图，生成 `.runtime/room-review/all-walk.png`、`all-plan.png` 和 `report.json`。实机还检查逐间切换、移动、第一间穿门切换、最后一间完成与复位。
