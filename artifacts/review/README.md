# 测试评分

打开 `index.html` 查看每个片段最近一次测试的七项评分、依据和版本。`scoring_overview.md` 提供 Markdown 总览，`score_records.json` 提供结构化数据。

所有测试统一记录。七项结果属于同一测试 ID；缺测项目显示原因。旧测试页面和重复历史报告已删除。

通过 MCP `add_scores` 一次提交七个类别的 `scores` 和 `reasons`，附 `trajectory_id`、`test_id`、`evidence`。页面自动刷新；测试结束调用 MCP `render` 导出静态页面并校验链接。
