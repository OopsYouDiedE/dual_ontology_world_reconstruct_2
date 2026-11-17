# Evaluation MCP 测试手册

快速单点人工测试使用 [游戏定点测试 MCP](../game/README.md)；本手册适用于开发批处理与完整分段评估。

## 定点检查

先用环境 MCP `prepare` 检查工具链。`evaluation_start` 返回 `run_id`；用 `evaluation_status` 读取状态、各任务阶段和证据，必要时用 `evaluation_cancel` 由 worker 清理自己的进程。

| `profile` | 用途 | 参数 |
| --- | --- | --- |
| `room_fast` | 房间站位、路径、宏观镜头视线 | `snapshot_path`；需要画面时设 `rendered: true` |
| `kitchen_click` | 厨房直接调用交互处理器 | `snapshot_path`，可选 `interaction_id`；无画面 |
| `scenario` | 单场景问题复现 | 显式提供项目内 `scenario_path`，视觉检查设 `rendered: true` |
| `chapter1_flow` / `chapter1_ui` | 第一章流程或 UI 探针 | 以工具 schema 为准；用于定位流程和界面问题 |
| `scene_survey` | 批量场景诊断 | `rendered: true`，可选 `segments`；结果按场景记录 |

保留定点检查结果和失败阶段。探针只提供实际测得的字段，不能替代从同一次分段实测采集的完整评分。评估服务从 [goal.md](../../goal.md) 读取带时区的起止时间，并以与持久收据及八小时上限相容的最早截止为准。截止后拒绝该服务启动新批次；只有明确授权才建立新窗口。

## 第一天完整剧情

采用 [连续实玩路线与风险补测](day-one-route.md)。以下分段入口保留用于历史评估和局部复测。

## 原分段评估入口

1. 从 [主线分段计划](../../assets/data/test_scenarios/gameplay_review_plan.json) 选择一个分段，冻结已提交的修订。用 `python mcp/game/segment_plan.py <分段ID> <观察者ID> <测试ID>` 生成计划；该工具校验场景和参考图来源，输出首场景路径、计划路径及准备凭证位置。
2. 在启动前配置七项采评渠道，准备有效参考图、独立盲玩观察者和匹配的准备凭证。观察者先读操作规则，保持剧情原文与带剧透的参考图隔离；准备凭证需包含 `test_id`、`observer`、`ready: true`、`canonical_unseen: true`。分段验证要求 60 FPS 上限和最多三个实例；按本次计划分配并记录实际并发负载。音频默认为开启，`--skip-audio` 仅用于用户明确豁免的任务，并记录缺测。
3. 调用游戏 MCP `on`，传入 `backend: godot`、`decision_maker: agent`、首场景 `scenario_path` 和 `assessment_plan`。用 `step` 操作、`observe` 观察，`review_visible_text` 标注屏幕文字，`event_script` 和 `character_script` 记录英文观察和对白。同段后续场景用 `step` 的 `next_case`，保持同一会话。手动检查点诊断可另用 `on(snapshot_path=...)`；再现既有检查点时保留其来源，切勿将其成绩并入另一会话。
4. 会话结束调用 `close`，再用 `metrics_status` 等待同一会话的分析完成。收集器提供流畅度、文字密度和响度证据。由同一位观察者提交全部评分：先完成并保留盲玩记录，再对照参考图与剧情原文；动作音效、美术相似度和节奏均使用同一会话的证据。
5. 按 [评审 MCP](../review/README.md) 一次提交七项结果，保留原因、证据和准确的失败阶段。需要重测时使用新的测试 ID。日常进度刷新轻量数据；分段闭环或交付时生成完整页面并验证本地链接。

## 量表要点

七项各 0–10 分，目标均为 8 分。流畅度将冷启动和跨房加载后的 1.5 秒单列，稳态帧时间超过 33.3 ms 按量表记失败；文字检查计可见的英文对白和交互提示，以 12 词、60 字符为上限，排除名牌和单键图标。部分项目探针另按 [文字预算配置](../../assets/data/test_scenarios/text_exemptions.json) 执行正式界面 25 字符、辅助界面 40 字符及指定页面豁免；报告须注明采用的阈值。动作音效关注物理动作、接触、穿模、遮挡、贴花和空间音效。音频目标为集成响度低于 -20 LUFS、环境峰值低于 -20 dBTP；数字削波判失败。盲玩叙事、美术和流程分别依据剧情对照、参考图和本次游戏过程评分。记录采样缺口、干扰和同屏文字的具体证据。
