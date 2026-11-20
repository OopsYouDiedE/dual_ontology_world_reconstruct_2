# 仓库维护说明

- 仅在本仓库工作。交付使用 `main`；完成检查后提交、推送。临时输出放 `.runtime/`。
- 游戏模式为按种子生成的单局肉鸽。房间连接由约束塌缩确定，玩家可见文字以英文为测试基准。
- 建筑工具使用项目原有的 ArchBuilder；营地自主决策由项目自研，出征由队长指挥。
- Godot 使用 4.7.2 .NET / .NET 8、Forward+、SDFGI 与原分辨率 Lowpoly 呈现；室内氛围与时间光分开，只有外窗引入时间光。通过项目游戏 MCP 操作和检查真实画面；无头模式用于逻辑检查。
- `goal.md` 的运行窗口只在用户明确授权时修改。当前入口、运行和测试见 README。
- 项目生图首选 `image-2.6-sunburst`（已验证供应商的请求模型 ID：`gpt-image-2.6-sunburst`，`quality=high`）。使用项目已配置的专用生图接口，勿走当前会话接口或 `/v1/responses`。带参考图的编辑走供应商的 `/v1/images/edits`，调用方式见 [热厨生图记录](docs/design/kitchen-paintover/README.md#本机已验证的生图路径)。若专用接口未配置或无法确认，先向用户确认，再发起调用。
