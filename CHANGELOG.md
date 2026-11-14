# Changelog

## 未发布 · Terra 剧情评审修复（2026-11-14）

- 合入 hydrogen 修复包：调整三问与推演时序、词义分歧、候选案和第四夜选择分支，并修正知识解锁链、结局文字与搜证门槛。
- 修复高倍速跨节拍、读档后时间失控、测试存档隔离、退出自动保存，以及边界门权限、外院返程和自动搜证遗漏。
- 补入 fable51low 的争执中重推入口：前置推演判错时可返回对应推演，完成后接回原争执；保留待决抉择互斥，并修复证物复选框文字对比度。
- 回归验证覆盖自然搜证集齐 10 项知识、33 件证物和破晓结局，以及永久争执中的误判补救、按钮交互和证物勾选保护。

## 未发布 · 复盘整改（对应复盘报告 F1–F10）

### 规则与玩法
- **F2** `DualEngine.resolve_conflict()` / `choose()` 增加幂等保护：该争执不在 `pending_conflict` / `conflict_queue`、或该抉择不是当前 `pending_choice` 时直接返回；UI 按钮按下即 disabled 并同步移除弹窗（`_dismiss_modal()`）。回归用例在 `dual_verify.gd` 第 9 节。
- **F1** `d3_deduce_vote`（第三天 08:30）时风窗走廊尚未开放，证物只能凑到 1/2，被设计校验抓出；节拍移到 09:00（`d3_case` 顺延到 09:05）。`ded_cuffs` / `ded_window` 的证物就在节拍所在房间（A-P / C-P），由「搜证门槛」挂起时间并传送侦探到现场后可取，不再依赖区门开放时间。新增设计校验（`dual_verify.gd` 第 8 节）：每个推演在节拍时刻按真实门锁可达证物数 ≥ `minEvidence`。
- **F3** 新局默认暂停并弹一次性引导；推演弹窗显示「已取得 X / 至少需要 N」，证物不足时禁用假设按钮并提供「先去取证」（`postpone_deduction()`，时间冻结到证物齐了再弹回）；案卷抽屉新增「推演」页，判错的推演可「重新推演」（`retry_deduction()` 现在只允许对 wrong 的推演重试，并在对应争执尚未拆解时接回争执）。
- **F6** 字幕改为累加 `delta` 计时（随 `Engine.time_scale`）；空格 / 回车（`ui_accept`）推进字幕；菜单新增「自动跳过字幕」。

### 性能
- **F4** `Main.gd`：删除 `Step` 之后多余的 `Observe()`（Step 返回值已含 snapshot）；事件文本只在 mechanics / receipts 数量变化时重建。*未做*：C# 侧快照窗口化（只带最近 N 条 mechanics / receipts、完整历史走分页接口）与 CLI 五日性能回归阈值，需要 .NET 工具链，见 TODO。

### 工程与文档
- **F7** 根目录 `index.html` 与两个 zip 移入 `docs/archive/`；`probe2.gd`、`dual_world_integration.patch`、`FIX_README.md` 删除（内容并入本文件）；README 补 Linux 快速开始与 `.runtime/` 说明；`docs/33` 标注「已被取代」。
- **F10** 标题页节点 `DualWorldButton` → `StartButton`、`NewButton` → `LifeTestButton`，副标题改为「双本体 · 案卷推演与主观认知」。

### 此前的修正包（原 FIX_README.md）
- `NuGet.Config` 删除指向被忽略的 `.runtime/godot/4.7.2/...` 的本地源（NU1301），只保留 nuget.org。
- `project.godot`：窗口标题；音频键 `buses/default_bus_layout`；补回 12 个缺失输入动作；入口改为 `Boot.tscn`。
- `scenes/main/Boot.gd/.tscn`：启动自检，非 .NET 版或程序集未编译时显示原因，不再空白。
- `TitleUI.gd`：「打开建筑设计工具」按钮补上悬停音效。
- `tools/build/build.sh`、`run.sh`：跨平台构建 / 运行脚本。

## TODO（未完成）
- F4：快照窗口化 + CLI 五日性能阈值（C#）。
- F5：机器人玩家（被动 / 勤奋）纳入 CI，需注入式时钟；目前只有 `dual_autoplay.gd`。
- F8：有显示环境下的画面 / 声音 / 文字溢出验收（1280×720、1440×900，620 px 弹窗长文本）。
- F9：ObjectDB 退出泄漏，需 `--verbose` 定位对象类型。
