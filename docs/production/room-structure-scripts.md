# 房间建筑结构：从画面找到生成脚本

以 Pump Archive 为例：**平面决定墙在哪，房间建造器决定墙放多高、朝哪边，截面配方决定墙长什么样。** ArchBuilder 编辑器里的路径墙有自己的入口；改泵房里看见的墙裙，请从下表的普通房间入口开始。

## 1. 普通出征房间：泵房、大厅等原生地格模板

[泵房蓝图](../../content/academy_lots/valve_gallery.xml) → [NativeBlueprint.gd · `read()`](../../scenes/rogue_view/NativeBlueprint.gd)（地格、墙边、窗标记和物件朝向）→ [RogueRoomView.gd · `_rebuild_architecture()`](../../scenes/rogue_view/RogueRoomView.gd)（放置、合批与碰撞）。下表中的网格配方集中在 [LotSections.gd](../../scenes/rogue_view/render/LotSections.gd)；门单独走 [LotDoors.gd](../../scenes/rogue_view/render/LotDoors.gd)。

| 画面中的结构 | 生成函数 | 要改什么就找它 |
|---|---|---|
| 实墙、踢脚、墙裙压条、顶角线 | `LotSections.wall_finish(width, height, glazed)` | `glazed == false` 分支按高度叠放不同厚度的水平带。调线脚的高度和出挑量改这里；墙的位置改蓝图，整房墙高改 `_rebuild_architecture()`。|
| 窗洞、窗台和过梁 | `LotSections.wall_finish()` 的 `glazed` 分支 | 建下墙、上墙和两侧墙垛，中央留洞。窗台与窗头标高分别由 `SILL`、`HEAD` 控制。|
| 窗框、窗棂、玻璃 | `LotSections.window_joinery(width)` | 按同一窗洞宽度生成边框、横竖棂和四片玻璃；建造器把它们与墙段按同一中心、同一朝向放置。|
| 地板、砖缝 | `LotSections.floor_finish()` | 一格由基层和四块略微抬高的面砖组成。单砖倒退的边距形成砖缝；房间建造器按地格花纹合批。|
| 吊顶、内凹面板、叠级边条 | `LotSections.ceiling_finish()` | 定义一格吊顶的局部截面，第一人称出征视图沿可走格在墙顶标高铺设。|
| 池格、池沿 | `LotSections.pool_finish(cell, patterns)` | 花纹 `65535` 代表池格。检查四邻，只在邻接非池格的边上生成池沿；连续水格共用水线。|
| 门套、门扇、装饰面板、门槛 | `LotDoors.install()`、`inward()`、`build()`、`panel_mesh()`、`threshold()` | 前两者找入口标记与朝向，后面负责造型。门外能选哪条路线由出征系统决定。|
| 地板与墙碰撞 | `RogueRoomView._rebuild_architecture()` → `_add_shape()` | 普通地格有地板盒体；普通墙段按长、高、厚放盒体，窗墙也沿整段阻挡。改窗洞外观不会自动打开通行。|

**举例：把窗台降低。** 从 `LotSections.SILL` 入手，墙洞和窗框都读取它，因此会一起调整。若要把窗移到隔壁墙段，改蓝图中的窗边标记；若想让人物翻窗，还要改墙段碰撞与通行逻辑。这三项改动分别对应截面、布局和玩法。

**网格底层。** [OrthogonalShell.gd](../../scenes/rogue_view/render/OrthogonalShell.gd) 的 `prism()` 记录长方体范围，`compile()` 求外露面，`mesh_of()` 输出 Godot 网格。一般只调上表配方；需要改变多块正交实体的拼接算法时，再看这个底层脚本。

## 2. 指定房间额外调用的结构

| 场景 | 入口 | 职责 |
|---|---|---|
| 热厨 `kitchen` | [HotKitchen.gd](../../scenes/rogue_view/render/HotKitchen.gd) · `build()`、`shell_prisms()`、`_build_frames()`、`_build_openings()` | 有厨房方案时，建造器转入专用分支。墙壳和开口在这里生成；`fit_prep()` 和 `_build_furniture()` 处理备餐台布局与家具。改热厨的墙先看这里。|
| 高门厅 `foyer` | [FoyerJoinery.gd](../../scenes/rogue_view/render/FoyerJoinery.gd) · `_ready()` | 在普通墙壳之上添加门厅专属横梁、连续檐线、支撑、吊灯等。`foyer` 是特定模板名。|
| 公共大厅、天文台的井区 | [MeridianWell.gd](../../scenes/rogue_view/render/MeridianWell.gd) · `plan()`、`install()` | 建造器先计算井区，再安装专用结构，并在该区域跳过普通地砖表面。|

## 3. ArchBuilder 组件库：编辑器放置的建筑构件

从[组件工厂](../../tools/building_construction/BuildingConstruction/Shared/ComponentFactory.gd)的 `create_entry()` 进入。要追踪某个目录条目，按其 `production.generator` 找实际脚本。下表是制作脚本，不是普通出征房间逐格铺墙的调用顺序。

| 组件 | 真实生成脚本及入口 |
|---|---|
| 平面路径墙、带洞智能墙 | [WallPathGeometry.gd](../../tools/building_construction/production/line/WallPathGeometry.gd) `build()`；[SmartWall3D.gd](../../tools/building_construction/production/line/SmartWall3D.gd) `register_opening()`、`rebuild()` |
| 路径墙配方、扶手栏杆 | [ArchitectureRecipes.gd](../../tools/building_construction/production/line/ArchitectureRecipes.gd) `gen_wall_path()`、`gen_railing()` |
| 石砌墙、砌缝 | [MasonryRecipes.gd](../../tools/building_construction/production/rule/MasonryRecipes.gd) `gen_stone_wall()`、`gen_masonry_joints()` |
| 铺砖地面 | [FloorRecipes.gd](../../tools/building_construction/production/rule/FloorRecipes.gd) `gen_tiled_floor()` |
| 楼梯、梁、柱 | [StaircaseRecipes.gd](../../tools/building_construction/production/rule/StaircaseRecipes.gd) `gen_staircase()`；[StructuralRecipes.gd](../../tools/building_construction/production/rule/StructuralRecipes.gd) `gen_beam()`、`gen_column()` |
| 拱窗、闭合门、院门 | [OpeningRecipes.gd](../../tools/building_construction/production/rule/OpeningRecipes.gd) `gen_arched_window()`、`gen_closed_door()`；[GateRecipes.gd](../../tools/building_construction/production/rule/GateRecipes.gd) `gen_courtyard_gate()` |
| 管道、灯具 | [PipeRecipes.gd](../../tools/building_construction/production/line/PipeRecipes.gd) `gen_pipe_run()`；[LightingRecipes.gd](../../tools/building_construction/production/rule/LightingRecipes.gd) `gen_wall_lantern()`、`gen_pendant_lamp()` 等 |

**同名文件如何判断：** 例如旧位置的 [Walls/WallPathGeometry.gd](../../tools/building_construction/BuildingConstruction/Walls/WallPathGeometry.gd) 只继承 `production/line/WallPathGeometry.gd`，供已有场景继续加载。要改算法，进它继承的实现文件。要改墙面的颜色、受光或描边，则先看[正式美术规范](art.md)，保留几何配方。
