# 剧情流程与验证

主线按 [`dual_world.json`](../assets/data/dual_world/dual_world.json) 的时间线推进。`DualEngine` 逐拍处理房间限制、取证门槛、选择和分支；界面负责把这些状态呈现为对话、现场交互、复演和转场。第一天的结算在 **22:00** 后、晚间分工已落实且待办清空时出现。玩家点 `Chapter 2` 后，第二天从 R05 接续。

## 按交接点检查

| 起点 | 重点核对 |
| --- | --- |
| 标题到厨房 | `New Game` → R05 起身 → 走廊 → B-P。采样时检查进入近景、手势、返回、入账和后续提示。 |
| `kitchen-reconstruction` | 看复演、试错、调整顺序并确认。回到房间后检查时钟继续和下一拍出现。 |
| `service-maintenance`、`cross-c-window`、`cross-d-pressure`、`shaft-question` | 记录实际开放的门、线索和角色；能换序时对照两种可达顺序，检查主线交接与回访。 |
| `poem-stakeout` / `poem-expose` / `poem-indulge` | 复现各预选结果；测试选择本身需从 `d1_poem_hint` 之前的玩家保存点开始。 |
| `dinner-plan` | 从分工前开始，等到 22:00，点 `Chapter 2` 并观察 R05。`chapter-night` 用于定位已结算界面。 |
| `day2-wind`、`day3-case`、`day4-control`、`day5-morning` | 逐日定位风窗、案件、风险处置和最终选择，实际推进一个交接；结局以页面和规则状态共同核对。 |

分段入口在 [`segments/`](../assets/data/test_scenarios/segments/) 中，以 `before_beat` 标记起点。批量巡检按 [`mainline_survey.json`](../assets/data/test_scenarios/mainline_survey.json) 选择场景。改一个节拍或镜头时，先从最近检查点复现；验证相邻段交接优先沿用上一段玩家操作形成的真实存档。

## 结果按测试方法记录

- **规则回归**：`tools/test/story_contract.gd` 验证五天节拍、章节边界、存档与取证规则；记录供给证物和选择的测试条件。
- **定点与巡检**：游戏 MCP `focus_open` / `focus_step` 或评估 MCP `scene_survey`，分别记录起点、操作、到达状态和截图。诊断夹具保留在测试证据中。
- **连续实玩**：从正式标题用普通操作通关，同一会话保留时间、房间、动作和待办；参照[第一天连续路线](../mcp/evaluation/day-one-route.md)。验 `Continue` 时另启独立回读记录，引用原存档来源。
- **正式分段**：冻结提交后按[评估手册](../mcp/evaluation/README.md)准备独立观察者、参考图和七项同步采集。分段状态、缺测和原始失败由[评审流程](../mcp/review/README.md)发布。
