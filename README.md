# 沉睡学院 · The Sleeping Academy

第一人称规则怪谈肉鸽。每局从公共大厅出发，在固定大地图上选路，用途中带走的物资解机关，最后到同一座天文台敲响晨钟。

**[现役制作文档](docs/production/README.md)** · [路线与事件](docs/production/gameplay.md) · [单房与楼层布局](docs/production/layout.md) · [三渲二美术](docs/production/art.md) · [写实 6.5 头身人物](docs/production/characters.md) · [运行与测试](docs/production/verification.md)

## 开始游戏

直接运行 `Expedition.tscn` 与启动主游戏共用同一个公共大厅开场。主场景：[scenes/rogue/Run.tscn](scenes/rogue/Run.tscn)。准备好 Godot 4.7.2 .NET 与 .NET 8 后，在仓库根运行：

```powershell
dotnet build DualOntologyWorldReconstruct2.csproj
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64.exe --path . -- --run-seed=1
```

WASD 移动，点击画面控制视角，E 操作或过门，Tab 查手册，Esc 放下文件。可以独行或在大厅先招募居民。看路线图选西边的毛毡或东边的棘轮；到折返闸后可继续，也可回营休整一次，再从原处出发。

## 开发入口

- **[工具图解](docs/production/tools-guide.md)**：ArchBuilder、组件库（物品属性与交互配置）、F2 蓝图检视器、`inspect_level.py`，附实机截图。
- 建筑工具：ArchBuilder → Furniture → Open Component Library。[参数与生成代码](tools/building_construction/production/README.zh-CN.md)按线控结构、规则构件、复合装配分类。
- 设计参考：《蓝图王子》主导第一人称三渲二，《巴别塔圣歌》补充建筑色面与高差导向；《邪恶冥刻》主导分支连接与事件节奏。[视频帧与出处](docs/research/expedition/README.md)供同机位比对。
- [项目 MCP](mcp/game/README.md)从正式入口操作实机。实验场景独立启动；正式玩法和美术以制作文档为准。
