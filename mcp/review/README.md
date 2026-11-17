# Review MCP

本服务绑定当前项目，通过 stdio MCP 提供评分、进度记录和报告导出。

## 一次测试，七项结果

使用 `add_scores`，参数为：

- `trajectory_id`：测试计划中的片段 ID。
- `test_id`：唯一测试 ID，相同请求可安全重试。
- `scores`：七个类别对应 0–10 分或 null。
- `reasons`：同样七个类别，每项填写评分依据；null 项填写具体缺测原因。
- `evidence`：项目内真实证据文件路径。

类别为 `fluidity`、`text_density`、`action_sfx_integrity`、`audio_loudness`、`blind_narrative_match`、`aesthetic_similarity`、`narrative_flow`。

服务先验证全部字段，再原子写入一条含 `test_result` 的记录和文件哈希。相同 ID 的内容冲突会被拒绝。`see_score.latest_test` 返回完整批次。兼容入口 `add_score` 保留单项提交，其他维度标明缺测；完整测试应使用 `add_scores`。

页面通过本地脚本自动刷新，每次替换整批七项结果。测试结束调用 `render` 生成 `artifacts/review/index.html` 和 `scoring_overview.md` 并核验本地链接。首页保留每个片段的最新测试，旧报告页已删除。

`review_append` 接受带真实来源的七项评测；`semantic_append` 记录图片盲读；`progress_append` 记录修改、检查和完成事件。完成事件引用同一 work 的已有事件。`flush` 修复实时投影，`render` 生成报告。来源、PID、截图哈希和版本校验持续生效。

## 调用与验证

已启动会话加载旧工具表时，可使用 `.runtime/python/Scripts/python.exe mcp/review/client.py add_scores --arguments @<项目内JSON文件>`，该客户端使用相同 stdio MCP 协议。`--test-sandbox` 将测试记录限制在 `.runtime/review-tests/`，隔离测试数据。

回归入口：`mcp/review/test_batch_scores.py`、`mcp/review/test_integration.py`、`tools/testing/test_result_batches.py`。

The `action_sfx_integrity` identifier is retained for compatibility. Current assessments score visible physical action; historical scores retain their original rubric and reasons.
