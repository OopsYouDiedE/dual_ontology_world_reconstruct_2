# 项目约束与实时进展

本项目唯一根目录为 `C:\Users\iii\Desktop\dual_ontology_world_reconstruct_2`。保留用户给出的 Affirmative-First Writing 要求；織羽Oriha 使用自然、具体、直接的表述。

## 主线与协作纪律

- 以正式主线顺序采集、评分、根据本段反馈修复；当前优先第一章。开发快照用于五秒内排错，独立 Terra 从标题开始的慢环只在目标房间快检通过后开展。
- 所有启动、截图和监控入口核对本项目标识与真实 PID。快照恢复属于开发测试，验收保持待评。全部工作和证据保存于本项目。
- 主线每段先展示实机轨迹，再展示结论、七项评分原因、实际修改次数和反馈修正。辅助／隔离资料在 archive.html。每次修改与检测立即追加，工作完成后追加独立确认。
- 家具和证物使用原房间原相机交互；表面细节优先采用受光贴花。站位、家具和镜头修改先检查占位、路径与物理遮挡射线，逐次只修角色或物体一个变量。
- 调度工程 Sol 时实际模型使用 `gpt-6.1-sol`。Terra 负责独立采集盲测，Astra 负责参考图。子代理仅在开始、结束交流，测试针对已验证提交；角色名和实际模型分别核对。

## 所有智能体共用的评分与进展接口

项目级 MCP 配置：`.codex/config.toml`，服务 `dual-ontology-review`。新会话加载后可直接调用 `progress_append`、`review_append`、`flush`、`render`。

- 图片评审优先展示“独立测试者看到的动作／猜测的意图 → 剧情实际动作／意图 → 误读、漏读与分项得分”。使用 `semantic_append` 接口，每段填写结构化比较。Terra 只接收匿名图片，不接触剧本和答案。正式轨迹和连续录制保留按原时机完整播放的台词；原字幕图使用 `original_subtitled_stills`，分别记录 `visual_only`、`dialogue_understanding` 和每项 `evidence_basis`。另行遮字的开发轮使用 `text_masked_stills`，历史保留。原始观察不可改写，来源与评分均保留版本。图片评审与完整实机七项验收分别标识。设定来源保存不可变副本，后续修复不得覆盖旧评审；每段／每批闭环调用 render 批量导出。接口说明见 `mcp/review/README.md`。
- 完整录制通过 `progress_append(kind=check)` 的 `evidence` 附加本项目 `*.capture.json`。导出器按段自动展示首行完整关键帧、连续视频及对白时间轴；来源PID、视频SHA和覆盖报告均校验。使用 `tools/testing/publish_opening_recording.py --output <录制目录>` 自动校验第一二段生产阶段、六项调查、自然房门交棒及逐字对白覆盖后写入MCP。单次抽帧与完整录制分别标记。

- 每一次文件修改、每一次检测结束后，立即调用 `progress_append`，`kind` 分别为 `change`、`check`。填写稳定 `work_id`、计划中的 `segment_id`、具体 `summary`、真实 `result`、当前 Git `revision`、项目内已存在的 `evidence` 文件路径数组。共享基础设施使用 `segment_id: project`。
- `event_id` 可指定唯一 ID；省略时按输入自动生成。相同输入重试返回原事件；相同 ID 改写会被拒绝。事件记录实际服务 PID、项目根与证据 SHA256。
- 工作完成后另行调用 `progress_append(kind=complete)`，相同 `work_id` / `segment_id`，`related_event_ids` 列出该工作全部 change/check 事件 ID。确认是新的不可变事件。后续修改使用新的 `work_id`。
- 独立 Terra 评分用 `review_append(work_id,summary,record)`。`record` 复用 `tools/testing/mainline_reviews.py` 格式与验证，保留真实标题新游戏入口、同主机 PID/会话、七项评分原因和图片 sidecar/hash 门槛。生产评分成功自动完成一次全量 HTML 渲染；已完成渲染的相同评分重试复用回执。导出失败时同请求重试会继续导出；测试沙盒始终跳过正式页面。普通检查保留在 progress。
- 每次事件自动原子刷新 `artifacts/acceptance/mainline_progress.yaml` 和 `artifacts/review/live-progress.js`；已打开 HTML 底部定时读取脚本。日常事件只刷新此快照。每段闭环调用 `render` 或 `flush(full_render=true)` 全量导出 HTML。
- 当前会话若没有热加载新工具，立即使用相同 MCP 协议的项目客户端：`.runtime/python/Scripts/python.exe mcp/review/client.py progress_append --arguments @项目内请求.json`。客户端真实执行 initialize / tools/list / tools/call。`review_append`、`flush`、`render` 同样可用。新增智能体与后续会话均遵循本规则。
- 完整格式、恢复机制与验证入口见 `mcp/review/README.md`。保留其他智能体的修改，按本次任务已有授权提交已验证的项目改动。
