# FreeSO 建筑绘制源码

这里是 FreeSO 提交 `4c6b3e8f5835b228723caea3c9f683c62f244f73` 的逐字节摘录，保留原目录、MPL-2.0 许可及 Git blob ID。原版客户端从 `vendor/FreeSO` 的同一修订构建。本目录便于在子模块尚未下载时也可检查原实现；Godot 的地块投影与 MonoGame 原版渲染是两个不同的显示端。

- `TSOClient/tso.world/Components/WallComponent.cs` 绘制墙片；`RC/WallComponentRC.cs` 为三维墙面生成网格，绘制时绑定墙面及样式遮罩。
- 窗户属于建筑对象。`TSOClient/tso.simantics/Entities/VMGameObject.cs` 根据 `ArchitectualWindow`、安装方向和物件 `WallStyle` 修改墙段，必要时从物件加载六组墙面精灵；`Components/ObjectComponent.cs` 和 `Utils/DGRPRenderer.cs` 管理对象显示及墙体切面状态。窗户外观取决于授权游戏资源。
- `Components/FloorComponent.cs`、`Components/RoofComponent.cs`、`Model/WallTile.cs` 是同一版本的地面、屋面及墙段原实现。`FSO.LotView.csproj` 是原项目编译清单。

运行 `python third_party_sources/FreeSO/verify.py` 核对内附源码；传 `--checkout vendor/FreeSO` 可同时核对完整上游工作树的相同文件（使用 Git blob，避免 Windows 工作树换行转换）。
