# 测试评分总览

报告版本：5571db5e0b6af1a87bb605c743fb05e0ec2a9fe3

| 片段 | 测试 ID | 游玩流畅度 | 界面字数 | 动作与音效 | 音频响度 | 视听剧情替代 | 参考图相似度 | 剧情流畅性 |
|---|---|---|---|---|---|---|---|---|
| 起床与卧室探索 | terra-batch-20261117-wake | 8/10 | 8/10 | 未测 | 未测 | 未测 | 未测 | 8/10 |
| 出门与走廊会合 | terra-batch-20261117-corridor | 6/10 | 8/10 | 未测 | 未测 | 未测 | 未测 | 8/10 |
| 厨房七证物与原房间镜头 | terra-batch-20261117-kitchen_evidence | 6/10 | 8/10 | 6/10 | 未测 | 未测 | 未测 | 8/10 |
| 厨房三段脑内推演 | event-bd00522941736580e272f27c1453f273 | 未测 | 未测 | 6/10 | 未测 | 未测 | 未测 | 未测 |
| 手铐、检修与暗井路线 | 尚未测试 | 未测 | 未测 | 未测 | 未测 | 未测 | 未测 | 未测 |
| 跨区调查与中央对账 | 尚未测试 | 未测 | 未测 | 未测 | 未测 | 未测 | 未测 | 未测 |
| 传声管与四锚调查 | 尚未测试 | 未测 | 未测 | 未测 | 未测 | 未测 | 未测 | 未测 |
| 黑板诗与三分支 | 尚未测试 | 未测 | 未测 | 未测 | 未测 | 未测 | 未测 | 未测 |
| 四院知识与复核 | 尚未测试 | 未测 | 未测 | 未测 | 未测 | 未测 | 未测 | 未测 |
| 包饺子、借物与晚间分工 | 尚未测试 | 未测 | 未测 | 未测 | 未测 | 未测 | 未测 | 未测 |
| 夜间返回、休息与章节存档 | 尚未测试 | 未测 | 未测 | 未测 | 未测 | 未测 | 未测 | 未测 |

## 起床与卧室探索

terra-batch-20261117-wake · 2026-11-17T16:17:32.425634+08:00 · 5571db5e0b6af1a87bb605c743fb05e0ec2a9fe3 · 待补测

- 游玩流畅度：8/10 — Steady wake telemetry recorded P95 9.507 ms, P99 13.319 ms, and zero steady spikes over 33.3 ms.
- 界面字数：8/10 — Visible English dialogue and prompts met the observed concise-text rule.
- 动作与音效：未测 — A stand-up phase and bed camera move were observed, without a complete skeletal-and-SFX measurement.
- 音频响度：未测 — Final FFmpeg audio postprocess timed out; retained live telemetry is not a final audio measurement.
- 视听剧情替代：未测 — No canonical-plot comparison was supplied to the blind tester.
- 参考图相似度：未测 — No Astra target image was supplied for visual comparison.
- 剧情流畅性：8/10 — Wake-up, bed inspection, and door transition formed a clear short progression.

## 出门与走廊会合

terra-batch-20261117-corridor · 2026-11-17T16:17:36.899698+08:00 · 5571db5e0b6af1a87bb605c743fb05e0ec2a9fe3 · 不合格

- 游玩流畅度：6/10 — Corridor telemetry recorded two steady-state spikes over 33.3 ms after live interaction.
- 界面字数：8/10 — Visible English lines and interaction labels were concise; no untranslated text was observed.
- 动作与音效：未测 — The run covered character selection and dialogue, without a complete skeletal-and-SFX measurement.
- 音频响度：未测 — Final FFmpeg audio postprocess timed out; retained live telemetry is not a final audio measurement.
- 视听剧情替代：未测 — No canonical-plot comparison was supplied to the blind tester.
- 参考图相似度：未测 — No Astra target image was supplied for visual comparison.
- 剧情流畅性：8/10 — Selectable group dialogue communicated clues and directed the player to the Kitchen.

## 厨房七证物与原房间镜头

terra-batch-20261117-kitchen_evidence · 2026-11-17T16:17:41.153996+08:00 · 5571db5e0b6af1a87bb605c743fb05e0ec2a9fe3 · 不合格

- 游玩流畅度：6/10 — Kitchen telemetry recorded three steady-state spikes over 33.3 ms during the live evidence segment.
- 界面字数：8/10 — Only concise English prompts and a 0/7 then 2/7 clue counter were visible.
- 动作与音效：6/10 — The heel-mark macro frame visibly placed part of the detective mesh in the lower-left evidence view.
- 音频响度：未测 — Final FFmpeg audio postprocess timed out; retained live telemetry is not a final audio measurement.
- 视听剧情替代：未测 — No canonical-plot comparison was supplied to the blind tester.
- 参考图相似度：未测 — No Astra target image was supplied for visual comparison.
- 剧情流畅性：8/10 — Two direct in-room sampling interactions completed and advanced the counter from 0/7 to 2/7.

## 厨房三段脑内推演

event-bd00522941736580e272f27c1453f273 · 2026-11-17T13:43:34.922735+08:00 · 34a6d483d6946da6c4e3639570917f109942bd77 · 不合格

- 游玩流畅度：未测 — This test did not collect this dimension.
- 界面字数：未测 — This test did not collect this dimension.
- 动作与音效：6/10 — Restored-checkpoint development observation: close reconstruction camera is obstructed by overlapping character silhouettes, obscuring the action; visual occlusion triggers the rubric fail threshold. Other action and audio components remain unassessed.
- 音频响度：未测 — This test did not collect this dimension.
- 视听剧情替代：未测 — This test did not collect this dimension.
- 参考图相似度：未测 — This test did not collect this dimension.
- 剧情流畅性：未测 — This test did not collect this dimension.
