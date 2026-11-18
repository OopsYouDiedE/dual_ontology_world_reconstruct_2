# Dual Ontology World Reconstruct 2

Godot 从 `scenes/main/Boot.tscn` 进入书桌标题。`New Game`／`Continue` 对应五日主线；建筑器和生活模拟各有独立入口。源码位置、开发启动参数及各目录职责见[开发手册](docs/development.md)。

## 工具链与构建

使用 Godot 4.7.2 .NET 和 .NET 8 SDK（见 [global.json](global.json)）；项目环境 MCP 提供 `prepare`。在仓库根目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/build/Build.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/build/OpenEditor.ps1
```

第一条构建，第二条打开编辑器。VS Code 中默认构建任务可用 `Ctrl+Shift+B`。在安装好 SDK 的 Linux 环境使用 `bash tools/build/build.sh`；编辑器与测试运行所需的 Godot 另行准备。托管构建产物在 `.runtime/build/` 和 `.godot/mono/`。

## 测试与结果

- [游戏定点测试 MCP](mcp/game/README.md)：五类快捷实机入口、单测试者判项、按需截图和实时验收。
- [评估 MCP](mcp/evaluation/README.md)：房间快检、检查点、盲玩分段计划、采集与预算。
- [评审 MCP](mcp/review/README.md)：七项评分提交、缺测记录与导出。
- [评审首页](artifacts/review/index.html)：每段最新结果与证据。浏览器通过配置好的本地 HTTPS 服务打开首页。
- [文档索引](docs/README.md)：剧情交接、建筑拓扑和历史档案。

服务回归可从根目录用已准备的 Python 运行：`python -m unittest discover -s mcp/game -q`，另对 `mcp/evaluation`、`mcp/review` 和 `tools/testing` 分别运行同一命令。剧情与存档规则用 `godot --headless --path . --script res://tools/test/story_contract.gd` 检查。渲染与实际操作通过项目 MCP 验证；参照[剧情流程与验证](docs/development.md#剧情流程与验证)。
