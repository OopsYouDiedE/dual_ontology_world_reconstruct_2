# 建筑参考组件

这里保留从《蓝图王子》参考场景中提取的可复用资源。大楼梯厅及参考展厅的整景装配、固定镜头、启动开关和整景回放已移出项目；后续按[正式布局](../../docs/production/layout.md)和[美术标准](../../docs/production/art.md)重新组装。

| 可用组件 | 接入位置 |
|---|---|
| 拱顶、柱、墙和真实窗洞 | `HallShell.gd`；石材与织物用 `HallFinish.gdshader` |
| 装饰、门、柜、楼梯、灯、旗、齿轮 | `HallDecor.gd`、`doors/`、`stairs/`、`lamp/`、`banner/`、`gears/` |
| 陀飞轮与机芯 | `studies/Meridian.gd` 和 `reference/meshes/`，可由正式天文台的井口装配复用 |
| 模块化庭院、礼拜堂与室内件 | ArchBuilder → **Props → Open Component Library**：软垫长椅、彩窗、八辐圆窗、月门、矮墙、帐篷和云杉 |
| 场景配套图形与材质 | `reference/interface/`、`reference/*.gdshader`；规则评测继续使用 `reference/plates.jpg` 作为固定图版夹具 |

`tools/blue_prince_lab/reference/build.py` 生成网格和纸面图形，输出资源组件。测试通过 ArchBuilder 的组件工厂创建实际物件，并检查月门、圆窗的开口与碰撞：

```powershell
$g = (Resolve-Path .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe).Path
& $g --headless --path . -s res://tools/blue_prince_lab/reference_parts_test.gd
& $g --headless --path . -s res://tools/blue_prince_lab/meridian_well_test.gd
```
