# 测试评分总览

报告版本：08c529ced9ba1936d5b0fee444de7b3a820cd76a

| 片段 | 测试 ID | 游玩流畅度 | 界面字数 | 动作完整性 | 音频响度 | 视听剧情替代 | 参考图相似度 | 剧情流畅性 |
|---|---|---|---|---|---|---|---|---|
| 起床与卧室探索 | wake-blind-20261118-fec773f | 6/10 | 8/10 | 6/10 | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 6/10 | 7/10 |
| 出门与走廊会合 | eval-20261117t174600-514af9d1-reviewed-corridor | 8/10 | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) |
| 厨房七证物与原房间镜头 | eval-20261117t174600-514af9d1-reviewed-kitchen_evidence | 6/10 | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) |
| 厨房三段脑内推演 | eval-20261117t174600-514af9d1-reviewed-kitchen_reconstruction | 6/10 | 0/10 (暂定·缺证据) | 6/10 | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) |
| 手铐、检修与暗井路线 | eval-20261117t174600-514af9d1-reviewed-service_route | 6/10 | 6/10 | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) |
| 跨区调查与中央对账 | eval-20261117t174600-514af9d1-reviewed-cross_zone | 6/10 | 6/10 | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) |
| 传声管与四锚调查 | eval-20261117t174600-514af9d1-reviewed-shaft | 6/10 | 6/10 | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) |
| 黑板诗与三分支 | eval-20261117t174600-514af9d1-reviewed-poem | 6/10 | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) |
| 四院知识与复核 | eval-20261117t174600-514af9d1-reviewed-institutes | 6/10 | 6/10 | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) |
| 包饺子、借物与晚间分工 | eval-20261117t174600-514af9d1-reviewed-dinner | 6/10 | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) |
| 夜间返回、休息与章节存档 | eval-20261117t174600-514af9d1-reviewed-chapter_end | 6/10 | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) | 0/10 (暂定·缺证据) |

## 起床与卧室探索

wake-blind-20261118-fec773f · 2026-11-18T00:49:07.020409+08:00 · fec773fd5858b884e94050208757c8725cb764c6 · 已测 · 测试未完成

- 游玩流畅度：6/10 — 53227 steady frames; 50 above 33.3 ms after the 1.5-second warmup exclusions. P95 16.799 ms, P99 25.098 ms, average 59.98 FPS. Peak observed load: three Godot processes, including two pre-existing instances; this test owns one. Runtime includes observer and tool waiting.
- 界面字数：8/10 — 61 visible-text changes; maximum 12 words and 60 characters in one frame. Seven unclassified strings counted conservatively; recognized nameplates and single-key icons excluded. Script checks found no non-Latin violations; Latin script alone does not verify English.
- 动作完整性：6/10 — Independent observer: 6/10. The detective moves to the wardrobe and its door opens; the bed cover changes position. The wardrobe edge obscures the arm, and the bed action lacks visible hand-to-cover contact. Visible motion only. Close-time isolation failure is retained beside this assessment.
- 音频响度：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Same-session raw Master and Music audio contain signal, but both segment analyses timed out after 180 seconds. FFmpeg inherited MCP stdin and stalled. Retain original failed analysis; the next revision disables interactive input and requires a full retest.
- 视听剧情替代：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. The observer reached the hallway and recorded waking, unexplained scratches and departure; memory loss was absent. The close receipt then exposed current_scene, violating the required server-side isolation guarantee. A valid fully isolated test is unavailable; repeat with a fresh observer after repair.
- 参考图相似度：6/10 — Independent observer: 6/10, after completing the blind account. Same-session bedroom framing and furniture placement match the assigned reference, while pure-white cutaway surroundings, harsher floor lighting, flatter surfaces and window lighting diverge.
- 剧情流畅性：7/10 — Independent observer: 7/10. Markers and the bedroom door guided the transition. The opening question and wardrobe dialogue establish a mystery; the bed inspection reveals little and the exit transition is abrupt. No gameplay phase blocked. Test incomplete due to close-time isolation and audio analysis failures.

## 出门与走廊会合

eval-20261117t174600-514af9d1-reviewed-corridor · 2026-11-17T18:05:08.034603+08:00 · d341ce8d36422a5c63f409df20ee69a087e8ff32 · 已测 · 测试未完成

- 游玩流畅度：8/10 — Lowest case score from this run: corridor-meeting=8
- 界面字数：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: corridor-meeting
- 动作完整性：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: corridor-meeting
- 音频响度：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: corridor-meeting
- 视听剧情替代：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: corridor-meeting
- 参考图相似度：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: corridor-meeting
- 剧情流畅性：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: corridor-meeting

## 厨房七证物与原房间镜头

eval-20261117t174600-514af9d1-reviewed-kitchen_evidence · 2026-11-17T18:05:11.181317+08:00 · d341ce8d36422a5c63f409df20ee69a087e8ff32 · 已测 · 测试未完成

- 游玩流畅度：6/10 — Observed failing score in kitchen-evidence=6
- 界面字数：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: kitchen-evidence
- 动作完整性：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: kitchen-evidence
- 音频响度：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: kitchen-evidence
- 视听剧情替代：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: kitchen-evidence
- 参考图相似度：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: kitchen-evidence
- 剧情流畅性：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: kitchen-evidence

## 厨房三段脑内推演

eval-20261117t174600-514af9d1-reviewed-kitchen_reconstruction · 2026-11-17T18:05:14.442091+08:00 · d341ce8d36422a5c63f409df20ee69a087e8ff32 · 已测 · 测试未完成

- 游玩流畅度：6/10 — Observed failing score in kitchen-reconstruction=6
- 界面字数：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: kitchen-reconstruction
- 动作完整性：6/10 — Observed failing score in kitchen-reconstruction=6
- 音频响度：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: kitchen-reconstruction
- 视听剧情替代：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: kitchen-reconstruction
- 参考图相似度：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: kitchen-reconstruction
- 剧情流畅性：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: kitchen-reconstruction

## 手铐、检修与暗井路线

eval-20261117t174600-514af9d1-reviewed-service_route · 2026-11-17T18:05:17.685774+08:00 · d341ce8d36422a5c63f409df20ee69a087e8ff32 · 已测 · 测试未完成

- 游玩流畅度：6/10 — Observed failing score in service-stair=6, service-maintenance=6
- 界面字数：6/10 — Observed failing score in service-maintenance=6; missing measurements: service-stair, service-hall
- 动作完整性：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: service-stair, service-maintenance, service-hall
- 音频响度：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: service-stair, service-maintenance, service-hall
- 视听剧情替代：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: service-stair, service-maintenance, service-hall
- 参考图相似度：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: service-stair, service-maintenance, service-hall
- 剧情流畅性：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: service-stair, service-maintenance, service-hall

## 跨区调查与中央对账

eval-20261117t174600-514af9d1-reviewed-cross_zone · 2026-11-17T18:05:20.880676+08:00 · d341ce8d36422a5c63f409df20ee69a087e8ff32 · 已测 · 测试未完成

- 游玩流畅度：6/10 — Observed failing score in cross-c-window=6, cross-d-pressure=6, cross-central=6
- 界面字数：6/10 — Observed failing score in cross-c-window=6, cross-d-pressure=6; missing measurements: cross-central
- 动作完整性：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: cross-c-window, cross-d-pressure, cross-central
- 音频响度：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: cross-c-window, cross-d-pressure, cross-central
- 视听剧情替代：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: cross-c-window, cross-d-pressure, cross-central
- 参考图相似度：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: cross-c-window, cross-d-pressure, cross-central
- 剧情流畅性：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: cross-c-window, cross-d-pressure, cross-central

## 传声管与四锚调查

eval-20261117t174600-514af9d1-reviewed-shaft · 2026-11-17T18:05:24.009608+08:00 · d341ce8d36422a5c63f409df20ee69a087e8ff32 · 已测 · 测试未完成

- 游玩流畅度：6/10 — Observed failing score in shaft-north-stair=6, shaft-four-anchors=6, shaft-question=6
- 界面字数：6/10 — Observed failing score in shaft-four-anchors=6; missing measurements: shaft-north-stair, shaft-question
- 动作完整性：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: shaft-north-stair, shaft-four-anchors, shaft-question
- 音频响度：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: shaft-north-stair, shaft-four-anchors, shaft-question
- 视听剧情替代：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: shaft-north-stair, shaft-four-anchors, shaft-question
- 参考图相似度：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: shaft-north-stair, shaft-four-anchors, shaft-question
- 剧情流畅性：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: shaft-north-stair, shaft-four-anchors, shaft-question

## 黑板诗与三分支

eval-20261117t174600-514af9d1-reviewed-poem · 2026-11-17T18:05:27.221090+08:00 · d341ce8d36422a5c63f409df20ee69a087e8ff32 · 已测 · 测试未完成

- 游玩流畅度：6/10 — Observed failing score in poem-stakeout=6, poem-expose=6, poem-indulge=6
- 界面字数：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: poem-stakeout, poem-expose, poem-indulge
- 动作完整性：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: poem-stakeout, poem-expose, poem-indulge
- 音频响度：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: poem-stakeout, poem-expose, poem-indulge
- 视听剧情替代：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: poem-stakeout, poem-expose, poem-indulge
- 参考图相似度：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: poem-stakeout, poem-expose, poem-indulge
- 剧情流畅性：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: poem-stakeout, poem-expose, poem-indulge

## 四院知识与复核

eval-20261117t174600-514af9d1-reviewed-institutes · 2026-11-17T18:05:30.758141+08:00 · d341ce8d36422a5c63f409df20ee69a087e8ff32 · 已测 · 测试未完成

- 游玩流畅度：6/10 — Observed failing score in institutes-corridor=6, institute-w-102=6, institute-s-102=6, institute-b-102=6, institute-f-104=6
- 界面字数：6/10 — Observed failing score in institute-w-102=6, institute-s-102=6, institute-b-102=6, institute-f-104=6; missing measurements: institutes-corridor
- 动作完整性：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: institutes-corridor, institute-w-102, institute-s-102, institute-b-102, institute-f-104
- 音频响度：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: institutes-corridor, institute-w-102, institute-s-102, institute-b-102, institute-f-104
- 视听剧情替代：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: institutes-corridor, institute-w-102, institute-s-102, institute-b-102, institute-f-104
- 参考图相似度：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: institutes-corridor, institute-w-102, institute-s-102, institute-b-102, institute-f-104
- 剧情流畅性：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: institutes-corridor, institute-w-102, institute-s-102, institute-b-102, institute-f-104

## 包饺子、借物与晚间分工

eval-20261117t174600-514af9d1-reviewed-dinner · 2026-11-17T18:05:35.213454+08:00 · d341ce8d36422a5c63f409df20ee69a087e8ff32 · 已测 · 测试未完成

- 游玩流畅度：6/10 — Observed failing score in dinner-dumpling=6, dinner-medical=6, dinner-plan=6
- 界面字数：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: dinner-dumpling, dinner-medical, dinner-plan
- 动作完整性：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: dinner-dumpling, dinner-medical, dinner-plan
- 音频响度：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: dinner-dumpling, dinner-medical, dinner-plan
- 视听剧情替代：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: dinner-dumpling, dinner-medical, dinner-plan
- 参考图相似度：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: dinner-dumpling, dinner-medical, dinner-plan
- 剧情流畅性：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: dinner-dumpling, dinner-medical, dinner-plan

## 夜间返回、休息与章节存档

eval-20261117t174600-514af9d1-reviewed-chapter_end · 2026-11-17T18:05:38.721939+08:00 · d341ce8d36422a5c63f409df20ee69a087e8ff32 · 已测 · 测试未完成

- 游玩流畅度：6/10 — Observed failing score in chapter-night=6
- 界面字数：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: chapter-night
- 动作完整性：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: chapter-night
- 音频响度：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: chapter-night
- 视听剧情替代：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: chapter-night
- 参考图相似度：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: chapter-night
- 剧情流畅性：0/10 (暂定·缺证据) — Provisional 0: evidence unavailable; test incomplete. Missing measurements: chapter-night
