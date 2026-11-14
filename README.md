# Dual Ontology World Reconstruct 2

Godot .NET 4.7.2 / .NET 8。正式入口为 `scenes/main/Boot.tscn`，启动自检通过后进入 `scenes/main/Main.tscn`，提供正式游戏（双本体新局，标题菜单第一项「开始新游戏」）、测试场景（五人生活推演）与建筑设计工具；C# DV、Reasoning、Runtime 共用于 Godot 和 CLI。

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

环境要求：Godot .NET (mono) 4.7.2 及 .NET SDK 8.0.4xx；不使用标准版 Godot 运行完整游戏。SDK 由 `global.json` 限定 .NET 8 补丁系列。Windows 开发者可把引擎放在 `.runtime/godot/4.7.2/`（该目录被 `.gitignore` 忽略，干净克隆里不存在，自行下载）；其他情况用环境变量 `GODOT` / `GODOT_MONO` 指向引擎可执行文件即可。

## Linux 快速开始

```bash
# 1. 工具链
./dotnet-install.sh --channel 8.0 --install-dir ~/dotnet && export PATH=$HOME/dotnet:$PATH
curl -LO https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_mono_linux_x86_64.zip
unzip Godot_v4.7.2-stable_mono_linux_x86_64.zip
export GODOT=$PWD/Godot_v4.7.2-stable_mono_linux_x86_64/Godot_v4.7.2-stable_mono_linux.x86_64

# 2. 构建与导入
git clone https://github.com/OopsYouDiedE/dual_ontology_world_reconstruct_2 proj && cd proj
dotnet build DualOntologyWorldReconstruct2.sln
$GODOT --headless --path . --import

# 3. 项目自带验证（正式双本体部分是纯 GDScript，标准版 Godot 也能跑）
$GODOT --headless --path . --script res://tools/dual_world/dual_verify.gd     # 规则 + 设计校验 + 回归用例
$GODOT --headless --path . --script res://tools/dual_world/dual_smoke.gd      # 界面冒烟
$GODOT --headless --path . --script res://tools/dual_world/dual_autoplay.gd   # 真实时间下的自动搜证
$GODOT --headless --path . --script res://tools/dual_world/dual_actions_verify.gd -- --dv-save-slot=actions-verify # 动作循环、起床、床面落位
$GODOT --headless --path . --script res://tools/characters/character_motion_verify.gd -- --dv-save-slot=motion-verify # .NET 角色动作回归
dotnet .runtime/build/bin/DuelView.Cli/Debug/net8.0/DuelView.Cli.dll --verify-character-actions
```

`dual_verify.gd` 退出码非 0 即失败，可直接接入 CI。其中的「设计校验」会按真实门锁检查：每个推演在其节拍时刻可达的证物数 ≥ `minEvidence`。新增或挪动节拍、开门时间后必须跑一遍。

## 正式游戏流程（双本体）

新局默认暂停并弹出一次性引导：**取证 → 推演 → 争执**。推演弹窗显示「已取得 X / 至少需要 N」，证物不足时假设按钮不可点，可「先去取证」（时间保持暂停，证物齐了推演自动弹回）；判错的推演可在右侧案卷抽屉的「推演」页「重新推演」。字幕按游戏内计时（随时间缩放），空格 / 回车推进，菜单里有「自动跳过字幕」。

角色开场保持躺卧，首次移动或点击调查时播放完整起床动画，再接行走；对话、争执、指认、思考、挥手与工作分别驱动骨骼姿态。五人生活场景按 Runtime 当前行动显示行走、用餐、取书、阅读、交谈、工作和坐卧动画。动作回归同时检查主循环覆盖、动画持续播放与实际生活场景；家具支撑碰撞验收仍由姿态驱动流程负责。

躺姿按骨骼与床垫实测落位，起床按片段时长平滑移向床外可走位置；持续对话、工作和挥手使用循环片段。合并内容与验证范围见 [人物动作修复说明](docs/人物动作修复说明.md)。

迁移、融合实施与验证边界见 [实施与验收](docs/33%20实施与验收.md)。

剧情设定查阅：[灾变前后时间轴（Gemini 设定）](docs/灾变前后时间轴（Gemini设定）.md)，包含灾变前 23:20 至次日 00:12 的具体时刻与次晨现场。

后续日程见[第一至四天剧情与分支（Gemini 设定）](docs/第一至四天剧情与分支（Gemini设定）.md)：第一天下午黑板诗与傍晚包饺子、第二天打谱布局、第三天三套候选案、第四夜救援及策略。

## 五人生活新局（测试场景）

> 标题菜单里的「测试场景 · 生活推演」是开发用的测试场景，不是正式开局。正式游戏是「开始新游戏」（双本体 · 门的这一侧）；「继续游戏」读取最近一份存档（正式游戏自动存档优先于测试场景）。

运行 VSCode 任务 `run: five-person life (Godot)`，在主菜单选择“开始生活新局”。侦探、雀儿、卢西安、阮清月、沈鼐通过 Core 自主选择日常行动和互动，Godot 负责实际路径移动。左侧是作者检查器，可以查看本人目的、需要与有向关系，并提交 Core 当前允许的行动。顶部提供暂停、倍率、存读档、兼容内容重载和墙体显示。

建筑器顶部“生活模拟”使用当前未保存建筑开启独立新局；退出后恢复原建筑器实例。建筑先导出到工具候选区，经 C# DV 解析器加载，不覆盖正式资源。当前支持首个包含封闭房间的单层；角色已按行动播放骨骼动画，家具支撑与坐卧接触仍需物理验收。

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
