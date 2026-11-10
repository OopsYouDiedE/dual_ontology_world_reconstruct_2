# Dual Ontology World Reconstruct 2

Godot .NET 4.7.2 / .NET 8。当前 Godot 入口为建筑模拟器；共用 C# 包含 DV、Reasoning 与 Runtime，并保留正式 CLI 数日自主决策宿主。

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

## 数日自主决策

从 VSCode 运行 `run: five-day autonomous CLI (600s)`，或在项目根执行：

```powershell
.runtime/python/Scripts/python.exe mcp/game/run_auto.py --backend cli --duration-seconds 600 --receipt .runtime/runs/latest-auto-receipt.json
```

此入口保持正式 CliMCP 连接，包含构建、内容验证和正式新局。所有角色由引擎决策，DV 观察窗从首日 07:00 至第五日结束；达到墙钟时限会停止宿主，不能视为完成观察窗。逐动作日志含候选评分、需要贡献、行动意图、本人认知依据与实际结果，位于 `.runtime/runs/<run>/actions.yaml`；同目录保存状态变化、可读日志与报告。模型迁入范围为五人；正式 DV 推演保留完整人物关系与其他角色。

AI／人工 CLI 输入使用 `.runtime/python/Scripts/python.exe mcp/game/input_client.py`，通过 `on`、串行 `step`／`observe`、`close` 操作。环境准备入口为 `.runtime/python/Scripts/python.exe mcp/game/run_environment.py --local-copy`，Python 依赖见 `mcp/game/requirements.txt`。

## 五人角色模型

建筑器顶部点击“角色模型”，查看侦探、雀儿、卢西安、阮清月、沈鼐，可左右旋转并返回。也可在 Godot 打开 `tools/characters/CharacterGallery.tscn` 运行当前场景。模型映射、高度和朝向由 `assets/data/character_models.dv` 声明，经 C# DV 解析器读取；GLB 保留原网格、内嵌纹理、蒙皮与动画资源。本预览不运行游戏规则，模型尚未接入正式 Godot 游戏会话。

## 建筑组件加载

`tools/building_construction/BuildingConstruction/` 使用纯 `.gd` 组件。设计软件通过 `catalog.json` 和 `Shared/ComponentFactory.gd` 加载脚本、设置参数并加入场景树，组件自行生成网格、碰撞与交互节点，不维护同名 `.tscn`。参数来自导出属性或配方的动态属性，具体布置由设计文件保存。旧设计文件中的组件 `.tscn` 路径在加载时映射到同名 `.gd`。

设计软件自身的入口场景、编辑界面及候选导出场景仍由设计软件管理。

## 自动检查

建筑器当前设计见 [建筑器优化说明](docs/建筑器优化说明.md)，验证入口、实际范围与交付包测试脚本的边界见 [实施与验收](docs/33%20实施与验收.md)。
