# 游戏定点测试 MCP

`dual-ontology-input` 提供快速实机定点测试。一次会话绑定一个目标、一位测试者和一个新测试 ID。Godot 4.7.2 .NET 使用项目 Forward+ 渲染，按目标直达入口并使用隔离存档和独立用户设置。正式盲玩、全段采集、自动冒烟仍走原有入口；定点结果在独立页面显示。

## 范围

| `scope` | `target` 示例 | 入口与验收项 |
|---|---|---|
| `room` | `R05`、`B-P`、`2F-cross-M` | 直接进入指定房间；检查布置、局部动线、证物和提示的视线。离开该房间后，本次测试只允许观察或提交结论，跨房步骤不能给房内检查作证。 |
| `interaction` | `kitchen-props`、`corridor-characters`、`wardrobe` | 前两项运行游戏内的厨房道具、走廊人物，`wardrobe` 是组件近景。检查命中、可观察状态、取消／重试与动作反馈。 |
| `ui` | `title` | 正式书桌标题界面；沿玩家实际点击路径检查标题、菜单、返回、英文标识、控件边界与排版。独立存档可用于继续检查新游戏界面。 |
| `design` | `building`、`lighting`、`expressions`、`mocap` | 直接启动工作台，检查控制、预览和诊断。`diagnostic` 支持 `monitor`、`reload`，建筑矩阵还支持 `previous_case`、`next_case`。动作捕捉工作台使用项目内指定的参考动作；`focus_catalog` 会标明它是否就绪。工作台内部诊断文字沿用工具自身语言。 |
| `story` | `wake-bedroom`、`kitchen-reconstruction`、`shaft-question` | 直接加载指定分段夹具与其快照；核对起点，再用普通输入推进到预期节点。每个节点单独启动、单独结算。 |

## 四个调用

1. `focus_catalog {}`：列出有效目标、前置条件、精确判项键和实时报告位置。
2. `focus_open {"scope":"room","target":"B-P","tester":"Your Name"}`：启动并返回 `session_id`、当前房间、界面控件和判项。默认无截图、无录音。需要听取直达游戏入口的音效时，启动时加 `"audio":true`。
3. `focus_step`：传 `session_id`，可选择 `operation`（`observe`、`start`、`click`、`drag`、`input_action`、`diagnostic`）、`note`、`wait_ms`。观测和输入默认只返回状态，截图用于核对实际画面。音效检查按需加 `capture_audio:true`（最多最近三秒，页面保留可回放 WAV；音频准备中会返回原因）。
4. `focus_finish`：关闭同一实机并一次提交该测试者的全部 `verdicts`。例如 `"layout":{"outcome":"pass","reason":"道具与侦探间有足够通行距离，桌角未发生穿模。","steps":["step-0001"]}`。填齐 `focus_open.checks` 的所有键。相同提交可以重试；改分需创建新测试。

静态布局、选项边界或某个状态用 `still:true` 和一句具体的取证目的；走位、触碰、操作物品或表情过渡用同一次输入的 `motion_frames:[8,22,45]`。它会采集动作前及指定的 2–3 个实际渲染帧，按帧序与实测毫秒分别保存。例如：

```json
{"session_id":"<id>","operation":{"type":"input_action","action":"move_right","frames":24},"motion_frames":[8,20,40],"note":"对比向右走之前、起步、行走和停止时的脚底接触及碰撞。"}
```

对照当前画面选控件或坐标，避开无变化的轮询截图。`inline:true` 可让 MCP 附回已留存的原图；序列默认只返回路径和时间，HTML 里逐张可查看。首图、过程图、结束图共用一个步骤 ID。

## 结论和发布

- 判项用 `pass`、`fail`、`blocked`、`not_applicable`。通过和失败都引用本次有效步骤；受阻和不适用写明具体原因，不折算成零分。任一判项失败则整体失败；其余情况如有受阻或退出异常则未完成；全部不适用单独显示。不存在跨范围加权总分。
- 唯一评分者在 `focus_open` 绑定。指标、引擎日志、画面与 WAV 只提供证据。批量结论只能从持有会话的同一 MCP 连接提交；连接正常中断时保留过程，并标示会话中断。
- 打开 [定点测试实时验收](../../artifacts/review/focused.html)。启动、每一步、异常及最终判定都会立即写入本地独立记录，HTML 每两秒刷新。每次测试保留版本、工作区状态、帧顺序、截图哈希和结论。HTML 的“主线评分”返回正式主线页面。

## 工具发现与复现

服务启动命令（从仓库根目录）：`.runtime/python/Scripts/python.exe mcp/game/server.py --service input`。更新已有 MCP 的工具表时重启连接；`focus_open`、`focus_step` 和 `focus_finish` 应由同一连接调用。`test_focused.py` 覆盖范围、动图采样要求、归属和结论规则。使用本服务做画面复测时选择实际要验收的目标和动作。
