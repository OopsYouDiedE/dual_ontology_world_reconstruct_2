# 首征 AI 自主批测：试板修复

[HTML 报告](index.html) · [修复前报告](../playtest-reading-8e0c31c/index.html)。被测 AI `a94f7e5`，游戏规则未改。原始批次留在 `.runtime/human_batch/`，标识列于 HTML 和 JSON。十分钟批次另保留逐局区域、停止原因、采样路线和首次确认节点的 tick。

原版 AI 在观察到稳视提示后仍按原探索节奏转向。修改后，读现场提示的 AI 用实际字幕和可见的琥珀表面采样决定接近、稳视和越过远端；同时补齐铁闸字幕的中英文措辞。修复中间版两个样本已开始稳定过板，却在板末抬头或提前恢复巡墙。最终版按到远端的距离调整俯视角，并为过板保留独立动作预算。无预设世界坐标、传送或强置关卡标志。

## 配对复测

- 主实验：谨慎、好奇、直行三策略 × 种子 1–18 × 四种阅读条件，216 局，各 7,800 tick，全部耗尽步数预算，0 局通关。手册实际翻五页；跳过现场提示时屏蔽字幕、路牌与交互文字。
- 十分钟实验：好奇策略，种子 8、12，各跑四组。8 局均超时。相同条件下修复前/后，独自越过试板从 0/8 增至 2/8，合上总闸从 0/8 增至 1/8，成功撤离仍为 0/8。各组及逐局结果见报告。核验看游戏确认事件和可见结算卡。
- 展示的路线为角色实走位置采样折线。近场 6 项按键与文字检查、开发中的试跑均单列或排除，不计入主实验和延时复测。

## 从仓库根目录复现

```powershell
$env:DOTNET_ROOT='C:/Program Files/dotnet'
$seeds=1..18
foreach($arm in 'closed-skip','closed-hints','book-skip','book-hints') {
  python tools/expedition/human_batch.py run --seeds $seeds --ticks 7800 --timeout 180 --reading $arm
  python tools/expedition/human_batch.py run --profiles curious --seeds 8 12 --ticks 36000 --timeout 600 --reading $arm
}
```

用 `ending_audit.py` 收集四个十分钟批次为本目录的 `ending-audit.json`，然后用 `reading_report.py` 读取四个 130 秒批次，传 `--sites-log`、`--prior-audit`（本目录 `prior-audit.json`）和 `--out`（本目录 `index.html`）。两脚本在 `docs/production/expedition-01/playtest/`。通关率只取 `outcome=completed`；`status=ok` 表示运行与日志通过校验。

## 并发实测（2026-11-24）

同机依次启动独立批次，使用好奇策略、合上手册并读取提示。表中是整批墙钟时间，含 Godot 启停。

| 工作量 | 1 并发 | 4 并发 | 8 并发 | 12 并发 |
|---|---:|---:|---:|---:|
| 种子 1–8，各 1,800 tick | 29.41 秒 | 10.61 秒 | 5.75 秒 | — |
| 种子 1–24，各 3,600 tick | — | — | 34.62 秒 | 36.20 秒 |

每个配置各测一次。同一工作量内，逐种子的结局、步数、行走距离、区域记录和决策次数一致。72 局性能样本单列。轻量策略批测默认最多 8 并发，按可用逻辑 CPU 和实际局数缩减；可显式指定 `--jobs 1` 到 `--jobs 12`。
