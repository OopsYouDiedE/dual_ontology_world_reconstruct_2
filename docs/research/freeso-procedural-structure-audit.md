# FreeSO 程序化结构代码审查

基线：`riperiperi/FreeSO@4c6b3e8f5835b228723caea3c9f683c62f244f73`。本文审查固定源码树中从输入数据推导**地块、地形、建筑拓扑与几何、植被、城市和远景**的路径，此外区分原型与生产入口。除特别注明，源码路径相对于上游 `TSOClient/`。上游的全仓入口见[架构分析](freeso-source-analysis.md)。

## 结论与发现

FreeSO 的结构生成以**手工蓝图或市政图层为输入**：房间身份由墙与地板派生，屋顶由房间图派生，地形和道路由城市地图采样，网格、阴影和远景由已知结构再编译。模板选取和植被摆放会使用随机数。以沙盒、线上常规地块和职业地块的入口追踪，未找到从一个种子合成整栋房屋平面或探索房间图的生产路径。

| 优先级 | 发现与影响 | 复核点 / 建议 |
|---|---|---|
| P2 | **远景 FSOF 用首层索引计算合并网格的法线。** `GetFSOF` 将首层、半层、水平方向复用的上层网格及屋面合并到 `tVerts` / `tInd`；计算时却传入 `FloorIndices`。追加的顶点保持零法线直到归一化；在浮点实现上可得到 NaN。`FSOF` 会把法线写入文件。可观察的瑕疵取决于着色器怎样使用法线。 | `tso.world/Facade/LotFacadeGenerator.cs:483–514`、`tso.files/RC/DGRP3DVert.cs:68–88`、`tso.files/RC/FSOF.cs:234–246`。用 `tInd` 计算，并对退化三角形、孤立顶点提供可控的法线回退；用含斜屋面的多层地块检查所有索引引用的顶点法线有限。 |
| P2 | **两条缩略图重建路径丢失斜墙砖的半砖地板。** `FullReset` 从墙格 `TopLeftPattern` / `TopLeftStyle` 各生成一块三角地板；`SliceReset` 和 `BuildableReset` 只读 `Floors[j].Pattern`，用整格几何或略过空 pattern。带斜墙的地块可出现实时视图正确、2D/3D 缩略图错色或缺地板。 | `tso.world/Components/3DFloorGeometry.cs:68–143`；调用处 `tso.world/Platform/WorldPlatform2D.cs:78–79`、`WorldPlatform3D.cs:88–89`。让三条路径共用单格生成器，仅传入各自的裁剪谓词。 |
| P2（尺寸扩展） | **地形恢复隐含 77×77 正方形。** `RestoreHeight` 的列反转用了 `target.Height - ox`，而噪声数组固定为 77×77。64×77 的首个采样索引为 `4940`，已超过目标数组最大索引 `4927`；78×78 的首个索引为 `6083`，高于噪声最大索引 `5928`。77×77 的主路径不触发这两个反例。 | `tso.simantics/Utils/VMLotTerrainRestoreTools.cs:477–499`、`tso.simantics/Model/VMArchitectureTerrain.cs:28–29`。要么明确约束支持尺寸；要么用 Width 反转列坐标，并按当前尺寸重采样或生成独立的噪声网格。 |
| P3（可复现性） | **空地块植被走无显式种子的 RNG，城市远景树木走按格种子。** 相同地图坐标和相同地块输入，从空白重新生成可得到不同树木。缺少邻地快照时，3×3 周边重建也会走空地植被路径。已有存档继续以其保存的对象为准。 | `tso.simantics/Utils/VMLotTerrainRestoreTools.cs:962–982,1056–1073`、`tso.client/Rendering/City/CityFoliage.cs:196–204`。如果用途要求可复现，把世界种子、城市和统一地块坐标折叠进显式的 `lot_decor` 子种子，同时保留已保存实例。 |

## 生成路径清单

### 1. 地块起点、模板与城市数据

- **新地块和职业地块**：`FSO.Server/Servers/Lot/Domain/LotContainer.cs` 的 `BlueprintReset` 选择 `empty_lot_fso.xml` 或由职业/等级选中的房屋模板。职业路径会裁切楼板矩形、偏移对象并扩到 77 格；某些等级可在两个模板之间取样。`VMBlueprintRestoreCmd` 分流 TS1 IFF 与 XML，在 `VMWorldActivator.LoadFromXML` 或 `VMTS1ActivatorNew.LoadFromIff` 实例化建筑。TS1 旧 Activator 也在树中；上述命令的活跃分支明确选用 `New`。
- **城市图层**：`tso.content/CityMapsProvider.cs`、`tso.content/Model/CityMap.cs` 提供服务端地块采样；`tso.client/Rendering/City/CityMapData.cs` 读取客户端地图的高程、地类、路网、森林种类与密度。`LotContainer.GenerateTerrain` 包装中央及周边的 3×3 地类/道路和 4×4 高程样本；离图特殊岛屿使用中心沙地、周边水域的规则分支。地图编辑/街区导入属于内容生产，可见上游 `Documentation/Crafting a City.md`。

### 2. 地块地形、边界、道路与周边

- **地形生成**：`VMLotTerrainRestoreTools.RestoreTerrain/RestoreHeight` 用邻域高程做两轴三次插值，固定种子生成的标量网格用来扰动采样坐标；`GeneratePerlinNoise` 的实现是多尺度随机值网格及双线性叠加。基准高度由中央样本推得；存在邮箱时可按邮箱高度整平指定建造区域。`VMArchitectureTerrain.RegenerateCenters` 生成四顶点平均高程与斜坡标记。
- **地表材质与道路**：同一个工具用邻接位标识混合地类和水边，按边界或角落把模板压进楼板栅格；`RestoreRoad` 按道路和转角掩码铺设预制路面。`EnsureCoreObjects` / `PositionLandmarkObjects` 放置或重排地块基础对象。`VMArchitectureTools.RaiseTerrain` 则是编辑系统的一部分，负责玩家改变高度的规则处理。
- **周边**：`RestoreSurroundings` 优先载入邻地精简快照；缺失时组合临时空地建筑、地表和植被，注册为显示子地块。`tso.world/Components/TerrainComponent.RegenTerrain` 把高度/地表格转换为可绘制顶点、三角形及材质数据。应把这类周边视觉合成与由服务器模拟的当前真地块分开。

### 3. 建筑命令、房间图、墙、楼板和屋顶

- **建筑编辑**：`VMArchitectureTools` 提供直线墙、矩形墙、擦除、油漆/地板填充、填土和视角切墙。`VMArchitecture` 保存分层墙段、地板、支撑和脏状态，由 `BlueprintChanges` 转发渲染重建。此链路保留玩家和模板给定的结构。
- **房间衍生**：`VMArchitecture.RegenRoomMap → VMRoomMap.GenerateMap`，逐层从墙、地板栅格做 flood fill；斜墙一格分成两个区域，按两组边传播。房间结果关联室内外、边界障碍和房间内障碍；`VMContext` 再导出门户、光照及实体关系。这里生成的是已知建筑的语义拓扑。
- **墙与窗**：`tso.world/Components/WallComponent` 生成等角墙片显示；`tso.world/RC/WallComponentRC.Generate` 从分层墙段和墙贴/遮罩生成网格，处理边、角、裁切和地形高度。窗/门物件参与墙样式和墙段逻辑；依据墙格抽模型时需要一起考虑对象朝向及附着关系。
- **楼板与水池**：`FloorComponent` 属于较旧的楼板显示路径，实际当前地表楼板从 `TerrainComponent` 和 `_3DFloorGeometry` 进入。`FullReset` 按材质分批、分层，斜墙两侧分别取材质；水池等从相邻格掩码选择边、角或替换几何。
- **自动屋顶**：`RoofComponent.RegenRoof` 在每层半格网格扫描；`IsRoofable` 根据下层室内格、半格出檐和当前层是否室内或铺砖来筛选。`RoofSpread` 按固定顺序向四边扩张矩形，`MeshRectData` 把矩形转换为坡面、屋脊、檐口和材质顶点。其几何受贪心扫描与矩形分解支配，适用于格状自动屋顶。斜墙小房、L/U 形、相邻楼层露台和坡地是高价值验证用例。
- **派生光影**：`tso.world/LMap/GPURoomMaps` 上传房间标签，`LMapBatch` 和 `ShadowGeometry` 从墙线、物件范围和照明产生投影网格。它们属于渲染派生层，适合放在拓扑和主网格的后面。

### 4. 城市近远景、立面与物件重建

- **城市地表与街区**：`tso.client/Rendering/City/CityGeometry` 以高程和地类生成大网格，并对局部切片重细分；`CityNeighGeom.Generate → Graph/VoronoiCellGraph` 接收手工街区中心并生成城市边界显示。`CityNeighGeom.RandomData` 是随机样例，构造函数中的调用已注释。
- **城市植被**：`CityFoliage.GenerateChunk` 以图层定树种/密度，用格索引播种，避开已有地块及道路边，插值贴地后在后台生成顶点，交主线程上传。
- **地块远景**：`FSOFacadeWorker.Program → LotFacadeGenerator.GetFSOF`，烘焙墙、楼面、屋顶和日夜纹理，供城市缩放视图使用。可另导出 OBJ/MTL；它是当前模型的远景表示，不能用来还原互动状态。
- **精灵→网格**：`tso.content/RCMeshProvider.Get → tso.files/RC/DGRP3DMesh` 优先查替换网格和版本缓存；重建路径从带深度的精灵生成物件表面与纹理、法线数据。`DGRP3DGeometry` 处理单组几何。人物装配、粒子和天气会有运行时变化，属于角色/特效系统，未计入空间结构生成。
- **道路与高程原型**：`tso.common/WorldGeometry` 包含 `SVGParser/LinePath`、`RoadGeometry`、`TS1RoadTemplates`、`MeshProjector`、`TriangleSet` 和 `SimplifiedHeightmap`。它们处理导入路径、道路交叉/截面、三角投影和四叉树高程简化；在固定树中搜到的这条组合调用位于 `tso.client/Utils/TestFunctions/ProjectionTest.cs`。当前线上地块的道路生成入口仍是 `RestoreRoad`。旧 `Other/tools/CityRenderer` 另有工具版城市地表管线。

## 对本项目的取舍与复核

最值得移植的是 **逻辑建筑数据 → 可通行拓扑 → 若干视觉派生物**。用同一批门槛与槽位做图连通、碰撞与可达性验证，屋顶、缩略图、远景共用逻辑源数据和三角地板规则。营地、折返闸和天文台继续作为固定锚点；现有种子选择的房牌与可选连线继续由本作生成。借用程序化建筑规则时，把内容、拓扑和装饰各自的随机数流分离。

本次静态检查追踪了调用点并验证了尺寸反例与生成分支。运行验证依次推荐：① 同一斜墙两侧不同材质，对比实时与两种缩略图；② 多层/斜屋面 `.fsof` 逐面检查法线有限性；③ 两块邻地共用边缘，对比高程和道路；④ 固定种子重复生成，比较几何、物件标识和排序。游戏和 GPU 画面未在本次启动。

```powershell
$rev = '4c6b3e8f5835b228723caea3c9f683c62f244f73'
git -C vendor/FreeSO show "${rev}:TSOClient/tso.world/Facade/LotFacadeGenerator.cs"
git -C vendor/FreeSO show "${rev}:TSOClient/tso.world/Components/3DFloorGeometry.cs"
git -C vendor/FreeSO show "${rev}:TSOClient/tso.simantics/Utils/VMLotTerrainRestoreTools.cs"
```
