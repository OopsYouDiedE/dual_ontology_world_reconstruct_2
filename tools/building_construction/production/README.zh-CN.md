# 建筑与模型生产管线

从 ArchBuilder → **Props → Open Component Library** 进入。目录 `catalog.json` 的 `production.kind` 显示生产类别，`production.generator` 指向实际运行的 GDScript。`id`、`path`、`mount` 分别保留组件标识、可实例化入口和安装语义。编辑器插件和组件库共用 `ComponentFactory.create_entry()`；ArchBuilder 从同一目录恢复已保存的配方道具。原有脚本路径和 UID 留在原位，旧场景、导出的建筑和历史配方可以继续加载。

| 类别 | 真实生产代码 | 可调参数示例 |
| --- | --- | --- |
| `line/` | `WallPathGeometry`、`SmartWall3D` 和 `ArchitectureRecipes` 沿轴线生成墙体、扶手和立柱；`PathRecipes` 提供采样、偏移和距离查询。 | 路径点、墙高、厚度、开口范围、扶手高、立柱间距。`PipeRecipes` 用同一条采样中心线生成管壳和装配端口；`nodes` 接受 Z-up 折线，`radius` 控制截面半径。 |
| `rule/` | `FloorRecipes` 按网格裁切地砖，`StaircaseRecipes` 按高差排踏步，`MasonryRecipes` 按行排列砌块并避开开口，`OpeningRecipes` 和 `VariantRecipes` 生成门窗轮廓；`LightingRecipes`、`StructuralRecipes`、`PublicGeometryRecipes` 与 `GearTrain` 分别提供灯、梁柱、浑仪和可调齿轮组。 | 砖缝、踏步高、门窗宽高、灯杆长度、梁截面、柱半径、浑仪半径和齿数。 |
| `assembly/` | `FurnitureRecipes` 等组合板件和构件；`ReferencePart` 实例化已导入部件；`ComponentAssembly` 处理墙装、端点、机件与支撑对接。 | 椅宽、深度、座高、扶手开关。门窗几何归 `rule`，墙洞对位和挂装沿用 `ComponentAssembly`。 |

**参数入口。** 配方适配脚本声明 `recipe_parameters` 和参数顺序，组件库属性面板读取动态属性；Smart 组件使用 Godot 的 `@export`。代码可调用 `create_entry(entry, {"width": 0.84})`，每个实例独立使用参数。已放置的单件修改后会重建网格与碰撞；已安装附件的根组件保留原有尺寸锁定，需拆开后修改并重新装配。


**场景专用件。** `HallGears` 从目录进入 `rule/GearTrain.gd`，复用大厅的渐开线轮面，齿数同步改变中心距和传动比。旧齿轮路径仍用于历史候选和大厅场景。`HallDoor`、`HallLamp` 继续复用大厅原脚本里的门扇雕刻与吊杆规则；目录指定类别并保留真实外部路径。其余规则灯走本地 `LightingRecipes`。

**墙洞与碰撞。** 门窗的安装轮廓继续交给 Smart Wall 生成开口；墙段网格与墙体碰撞仍由同一次切分构建。ArchBuilder 平面墙继续走 `WallPathGeometry.build()`。安装、取消、导出、撤销沿用原有工作流。

**验证。** 在仓库根目录用 Godot 4.7.2 .NET 运行：

```text
godot --headless --path . --script res://tools/building_construction/tests/production_pipeline_test.gd
godot --headless --path . --script res://tools/test/building_candidate_unit.gd
godot --headless --path . --script res://tools/blue_prince_lab/gear_check.gd
```
