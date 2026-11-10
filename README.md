# Dual Ontology World Reconstruct 2

Godot .NET 4.7.2 / .NET 8。当前入口为既有建筑模拟器，C# 工程引用 `core/dv`。

## VSCode 构建

在 VSCode 打开本目录，按 `Ctrl+Shift+B` 执行默认增量构建。可按扩展建议安装 C#、C# Dev Kit 和 Godot Tools。

命令行入口：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/build/Build.ps1
```

VSCode 的 `open: Godot .NET editor` 任务先编译再打开项目内的 Godot .NET 编辑器。也可执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/build/OpenEditor.ps1
```

此启动器使用引擎目录下的自包含设置，将 C# 外部编辑器设为 VSCode。C# 文件在 VSCode 编辑，编译由任务调用 .NET SDK 完成；Godot 自身的构建也继承共享编译设置。

构建保留增量依赖检查和正常 NuGet 还原，启用并行 MSBuild、节点复用和 Roslyn 编译服务器。优先使用引擎自带 NuGet 包。Core 产物在 `.runtime/build/`，Godot 托管产物由 SDK 放在 `.godot/mono/`，构建日志及二进制日志在 `.runtime/build-logs/`。

环境要求：本目录 `.runtime/godot/4.7.2/` 中的完整 .NET 引擎及 .NET SDK 8.0.4xx；不使用标准版 Godot。SDK 由 `global.json` 限定 .NET 8 补丁系列。

迁移计划、逐批状态与验证边界见 [实施与验收](docs/33%20实施与验收.md)。

## 建筑组件加载

`tools/building_construction/BuildingConstruction/` 使用纯 `.gd` 组件。设计软件通过 `catalog.json` 和 `Shared/ComponentFactory.gd` 加载脚本、设置参数并加入场景树，组件自行生成网格、碰撞与交互节点，不维护同名 `.tscn`。参数来自导出属性或配方的动态属性，具体布置由设计文件保存。旧设计文件中的组件 `.tscn` 路径在加载时映射到同名 `.gd`。

设计软件自身的入口场景、编辑界面及候选导出场景仍由设计软件管理。

## 自动检查

建筑器当前设计见 [建筑器优化说明](docs/建筑器优化说明.md)，验证入口、实际范围与交付包测试脚本的边界见 [实施与验收](docs/33%20实施与验收.md)。
