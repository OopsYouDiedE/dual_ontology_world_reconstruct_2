# 项目评分与进展 MCP

`semantic_append(work_id, summary, record)` 保存图片盲读对照。它与真实标题新游戏的 `review_append` 分开，独立图片评审可立即呈现结论。record 参见 `tools/testing/visual_semantic_reviews.py`：填写 schema_version=1、唯一 id、segment_id、revision、带时区 evaluated_at、modality=text_masked_stills、group_id、observations（独立 Terra 原始 JSON）、source_map、input_manifest、comparisons、conclusion、next_fix。每个 comparison 包含 frame_ids、expected_action、expected_intent、implementation、difference、action_score、intent_score、truth_sources（path、locator）。单项目标相符10、部分相符5、误读或漏读0；动作和意图分别平均，全部达到8分为图片盲读合格。

原始猜测与对照评分分别保存；调用者保持 Terra 报告原文。剧情来源先存入本轮不可变 truth-sources，保证以后代码修复仍能复核当时设定。服务检查匿名帧／原图哈希、主线对应关系、未知帧、来源文件和同 ID 内容冲突；每条记录追加 check 进展。段落／整批闭环后调用 render，刷新两份 HTML、带图 Markdown 并检查链接。常规追加保持轻量。新会话通过现有项目 MCP 注册自动获得此入口，旧会话可用 `client.py semantic_append --arguments @请求.json`。

服务只接受当前项目。根目录来自服务文件位置，并与授权根目录及可选 expected_project_root 双重核对；调用者不能提供来源 PID。服务来源由实际进程生成，评审来源由原 on/start 收据和图像 sidecar 交叉校验。

`progress_append` 必填：work_id、segment_id、kind（change/check/complete）、summary、result、revision（本项目存在的 Git commit）、evidence（项目内已有文件的路径数组）。可选 event_id、related_event_ids、expected_project_root。complete 必须引用相同工作所有先前事件 ID，完成后该 work_id 封闭。project 是基础设施专用段；其余段使用 gameplay_review_plan.json 的场景 ID。

`review_append` 必填 work_id、summary、record。record 原样经过 mainline_reviews.validate，保持独立 Terra 与真实主线全部校验，并生成对应 check 事件。supersedes 审计限定同版本同段。review 和进展跨两个文件采用可恢复提交：评分文件先完整发布，事件后发布；相同请求重试补齐投影。生产评分随后自动全量渲染 HTML，渲染成功回执位于 `.runtime/review-export/review-<id>.rendered.json`；成功重试复用回执，失败重试补做导出。返回成功时评分、进展与对应 HTML 均已发布。独立渲染锁串行全量导出，普通进展写入持续可用。测试沙盒评分只返回 skipped_test_sandbox，始终跳过正式页面。

已有独立实机评分的页面提供“修订这条评分”：填写新记录 ID、说明、分数及依据后下载 JSON 草稿。将草稿保存到项目内，例如 `.runtime/review-correction.json`，执行 `& ./.runtime/python/Scripts/python.exe mcp/review/client.py review_append --arguments '@.runtime/review-correction.json'`。提交经过与原评审相同的来源与证据验证，成功后自动重渲染；旧评分保留在历史中。没有独立实机记录的段落显示待评，需先完成独立评审。

持久化：跨线程与跨进程写锁；同目录临时文件 flush/fsync 后原子替换；独立评分通过硬链接 create-only 发布；进展由 YAML 作为持久源，JS 为轻量派生快照。YAML/JS 各自原子更新；进程在两次写入间终止时，重试原请求或调用 flush 重建 JS。所有事件只追加，旧 ID 内容不能覆盖。未关联该写锁的旧脚本应停止直接写进展；评分的旧 append 仍有独占创建保护。

页面通过 script 标签重载 live-progress.js，支持直接 file:// 打开。事件追加不扫描报告链接；render 才调用现有完整导出器。服务本身不声称已完成浏览器视觉验收。

项目配置位于 `.codex/config.toml`。正在运行的会话通常已固定工具集合；若工具列表没有 dual_ontology_review，可立即运行：

```powershell
& ./.runtime/python/Scripts/python.exe mcp/review/client.py
& ./.runtime/python/Scripts/python.exe mcp/review/client.py progress_append --arguments '@.runtime/review-request.json'
& ./.runtime/python/Scripts/python.exe mcp/review/client.py flush
& ./.runtime/python/Scripts/python.exe mcp/review/client.py render
```

请求示例（revision 替换为本项目当前 Git commit）：

```json
{"work_id":"review-interface-v1","segment_id":"project","kind":"change","summary":"建立项目进展接口","result":"已完成文件修改","revision":"995d0254891b150b2ad8ffae93651d0def653d2f","evidence":["mcp/review/server.py"]}
```

测试入口：`python mcp/review/test_integration.py`，必须使用本项目 `.runtime/python/Scripts/python.exe`。测试通过真实 stdio MCP 执行 initialize / tools/list / tools/call，临时数据限 `.runtime/review-tests/`；测试评分不会进入正式轨迹。`--test-sandbox` 只能指向该目录下的子目录，测试服务禁止全量渲染。

完整原字幕录制：`tools/testing/record_opening_complete.py --output <新的项目内目录>` 原速运行起床、六件家具、房门自然交棒、完整走廊会合，生成连续视频、关键帧、对白与阶段时间轴、恢复快照。`tools/testing/publish_opening_recording.py --output <录制目录>` 核验生产流程、逐字对白、后台帧写入和来源后，通过 `progress_append(kind=check)` 附加 `*.capture.json`。每段闭环调用 `render`，页面自动以本段完整关键帧作为首行，显示可播放视频和对白时间轴，保留旧评审。`complete` 仍须独立调用确认。覆盖完整与正式七项验收分别记录；无信号的音轨如实标识。

`semantic_append` 支持 `original_subtitled_stills`：input_manifest 的 `text_mode` 为 `original_subtitles`，原始 Terra 观察的 modality 同名，每组填写 `visual_only` 和 `dialogue_understanding`，每条 claim 填写 `evidence_basis: visual/dialogue/both`。兼容字段 `masked` 此时指向与原图逐字节相同的匿名图，`masks` 为空；服务验证哈希一致。正式台词按原时机完整显示。独立开发遮字轮继续使用 `text_masked_stills`，历史评分保持其原输入口径。
