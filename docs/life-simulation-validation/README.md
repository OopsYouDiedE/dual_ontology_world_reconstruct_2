# 生活融合验收资料

本目录是正式宿主的原始 MCP 回执与派生分析，不包含状态注入、回放测试或附件网页截图。

- `cli-seed7.receipt.json`、`cli-seed13.receipt.json`：正式 CliMCP 完整五日新局调用结果。相应 report、acceptance 原样复制。
- `summary.json`：从两局真实 actions.yaml 后处理的库存守恒、八种回应、承诺、同坐、关系范围、五人完成次数与因果样本；含原始逐动作日志的绝对位置与 SHA256。
- `godot-auto.receipt.json`、`godot-auto.report.json`：180 秒正式 GodotMCP，实际首日 07:00～07:50，达到墙钟截止；没有完成五日。
- `godot-release.receipt.json`：最后界面修正后的 75 秒正式 GodotMCP 新局，实际至首日 07:13，无宿主错误；达到墙钟截止。
- `campaign-regression.receipt.json`：原 17 人 campaign，1000 秒预算到第五日 15:00 截止，未完成五日，不作为完整回归通过。
- `input-000014.json`～`input-000019.json`：建筑删除一件家具、从当前未保存建筑开启生活新局、返回与撤销。前后建筑、选择、平移缩放完全一致，撤销恢复被删除家具。
- `input-000022.json`～`input-000026.json`：暂停下相同内容重载、保存、继续、读取；完整会话投影保持，存档恢复包含回执历史。
- `input-000030.json`、`input-000031.json`：真实 240× 运行至首日 13:40 后正常关闭，无宿主错误。原始回执中的本地截图路径是采集位置，不是新的远端资源。
- `godot-build.txt`、`environment.json`：正式宿主构建与项目内 Godot .NET 环境记录。

`Five-person-life-live.png`、`Five-person-life-noon-live.png`、`Builder-return-live.png` 均为正式 Godot 实机图片。人物保留原 GLB 姿态；座位逻辑完成不代表坐卧骨骼动画已经完成。中午截图保留采集时的恢复提示，后续已修正继续操作清除该提示。

构建与规则验收通过不能推导完整剧情动机质量。跨层、骨骼动作、动态人物避让、20 日压力运行、让位与主动分享自然分支没有在本轮完成验收。完整原 campaign 回归同样尚未通过终点。
