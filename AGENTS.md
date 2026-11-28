# 仓库维护说明

- 仅在本仓库工作。交付使用 `main`；完成检查后提交、推送。临时输出放 `.runtime/`。
- 新局直接从公共大厅出发；营地、折返闸和天文台的位置与机制固定。种子决定沿途房牌与可选连线，玩家可见文字以英文为测试基准。
- 建筑工具使用项目原有的 ArchBuilder；营地自主决策由项目自研，出征由队长指挥。
- Godot 使用 4.7.2 .NET / .NET 8、Forward+、SDFGI 与原分辨率三渲二 Toon。美术以《蓝图王子》为主、《巴别塔圣歌》补充建筑色面，房间连接与事件节奏参考《邪恶冥刻》。正式人形统一写实 6.5 头身，走同一加载管线（见 docs/production/）；室内氛围与时间光分开，只有外窗引入时间光。通过项目游戏 MCP 操作和检查真实画面；无头模式用于逻辑检查。
- `goal.md` 的运行窗口只在用户明确授权时修改。当前入口、运行和测试见 README。
- 项目生图首选 `image-2.6-sunburst`（已验证供应商的请求模型 ID：`gpt-image-2.6-sunburst`，`quality=high`）。使用项目已配置的专用生图接口，勿走当前会话接口或 `/v1/responses`。带参考图的编辑走供应商的 `/v1/images/edits`，调用方式见 [热厨生图记录](docs/design/kitchen-paintover/README.md#本机已验证的生图路径)。若专用接口未配置或无法确认，先向用户确认，再发起调用。
- 全关卡统一构建流水线、操作、渲染、台词与队友交互铁律：所有现有关卡与未来新增关卡必须统一走 `AcademyLevelPipeline`（`AcademyStage` 渲染/相机 + `AcademyUnifiedInput` 无冲突键位 + `DualModeInteractionHud` 双模三态交互 + `UnifiedDialoguePresenter` 底部字幕与共振峰语音 + `UnifiedTeammateWheel` Q 键队友径向轮盘），仅通过显式 `level_capabilities` 声明关卡特例（如大厅 `allow_jump = false`），详见 `docs/design/unified-level-ui-and-render-contract.md`。
