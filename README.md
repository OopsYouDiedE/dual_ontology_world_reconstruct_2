# Dual Ontology World Reconstruct 2

Godot .NET 4.7.2 / .NET 8。正式入口为 `scenes/main/Boot.tscn`，启动自检通过后进入 `scenes/main/Main.tscn`，提供五人生活新局、双本体新局与建筑设计工具；C# DV、Reasoning、Runtime 共用于 Godot 和 CLI。

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

构建保留增量依赖检查和正常 NuGet 还原，启用并行 MSBuild、节点复用和 Roslyn 编译服务器。NuGet 源使用 nuget.org，不依赖项目内的引擎包目录。Core 产物在 `.runtime/build/`，Godot 托管产物由 SDK 放在 `.godot/mono/`，构建日志及二进制日志在 `.runtime/build-logs/`。

Linux / macOS / WSL 可执行 `tools/build/build.sh` 构建，或设置 `GODOT_MONO` 后执行 `tools/build/run.sh` 构建并运行。

环境要求：本目录 `.runtime/godot/4.7.2/` 中的完整 .NET 引擎及 .NET SDK 8.0.4xx；不使用标准版 Godot。SDK 由 `global.json` 限定 .NET 8 补丁系列。

迁移、融合实施与验证边界见 [实施与验收](docs/33%20实施与验收.md)。

剧情设定查阅：[灾变前后时间轴（Gemini 设定）](docs/灾变前后时间轴（Gemini设定）.md)，包含灾变前 23:20 至次日 00:12 的具体时刻与次晨现场。

后续日程见[第一至四天剧情与分支（Gemini 设定）](docs/第一至四天剧情与分支（Gemini设定）.md)：第一天下午黑板诗与傍晚包饺子、第二天打谱布局、第三天三套候选案、第四夜救援及策略。

## 五人生活新局

运行 VSCode 任务 `run: five-person life (Godot)`，在主菜单选择“开始生活新局”。侦探、雀儿、卢西安、阮清月、沈鼐通过 Core 自主选择日常行动和互动，Godot 负责实际路径移动。左侧是作者检查器，可以查看本人目的、需要与有向关系，并提交 Core 当前允许的行动。顶部提供暂停、倍率、存读档、兼容内容重载和墙体显示。

建筑器顶部“生活模拟”使用当前未保存建筑开启独立新局；退出后恢复原建筑器实例。建筑先导出到工具候选区，经 C# DV 解析器加载，不覆盖正式资源。当前支持首个包含封闭房间的单层；GLB 保留原姿态，坐卧骨骼动画尚未接入。

生活入口为 `assets/data/scenarios/life_simulation.dv`，规则与宅邸位于 `assets/data/life_simulation/`。五人的个人目的、职业记忆和动机初值引用正式 `daily-life.dv`；新增生活偏好明确写在 DV 中。有限口粮、库存补给、六种回应（接受、勉强答应、延后答应、婉拒或拒绝、冷处理、对抗斥责）、延期与条件承诺、实际座位履行及关系账本均由 C# Core 执行。

正式五日生活自动入口为 VSCode 任务 `run: five-day life CLI (720s)`；原剧情 CLI 入口仍使用下述 campaign。截止时长包括构建启动，达到截止时间不代表通过五日验收。

## 数日自主决策

从 VSCode 运行 `run: five-day autonomous CLI (600s)`，或在项目根执行：

```powershell
.runtime/python/Scripts/python.exe mcp/game/run_auto.py --backend cli --duration-seconds 600 --receipt .runtime/runs/latest-auto-receipt.json
```

此入口保持正式 CliMCP 连接，包含构建、内容验证和正式新局。所有角色由引擎决策，DV 观察窗从首日 07:00 至第五日结束；达到墙钟时限会停止宿主，不能视为完成观察窗。逐动作日志含候选评分、需要贡献、行动意图、本人认知依据与实际结果，位于 `.runtime/runs/<run>/actions.yaml`；同目录保存状态变化、可读日志与报告。模型迁入范围为五人；正式 DV 推演保留完整人物关系与其他角色。

AI／人工 CLI 输入使用 `.runtime/python/Scripts/python.exe mcp/game/input_client.py`，通过 `on`、串行 `step`／`observe`、`close` 操作。环境准备入口为 `.runtime/python/Scripts/python.exe mcp/game/run_environment.py --local-copy`，Python 依赖见 `mcp/game/requirements.txt`。

## 五人角色模型

建筑器顶部点击“角色模型”，查看侦探、雀儿、卢西安、阮清月、沈鼐，可左右旋转并返回。也可在 Godot 打开 `tools/characters/CharacterGallery.tscn` 运行当前场景。模型映射、高度和朝向由 `assets/data/character_models.dv` 声明，经 C# DV 解析器读取；GLB 保留原网格、内嵌纹理、蒙皮与动画资源。同一套模型用于生活会话；独立模型预览不运行游戏规则。

## 建筑组件加载

`tools/building_construction/BuildingConstruction/` 使用纯 `.gd` 组件。设计软件通过 `catalog.json` 和 `Shared/ComponentFactory.gd` 加载脚本、设置参数并加入场景树，组件自行生成网格、碰撞与交互节点，不维护同名 `.tscn`。参数来自导出属性或配方的动态属性，具体布置由设计文件保存。旧设计文件中的组件 `.tscn` 路径在加载时映射到同名 `.gd`。

设计软件自身的入口场景、编辑界面及候选导出场景仍由设计软件管理。

## 自动检查

建筑器当前设计见 [建筑器优化说明](docs/建筑器优化说明.md)，验证入口、实际范围与交付包测试脚本的边界见 [实施与验收](docs/33%20实施与验收.md)。
