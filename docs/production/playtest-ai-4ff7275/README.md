# 首征 AI 自主探索复测 · 2026-11-24

[交互路线图：按策略、台词或零命中筛选](index.html) · [三策略轨迹及激活率总览](autonomous.png) · [上版基准](../playtest-20261124/README.md)

测试代码 `4ff7275553ff230be8b2fac2857dc62fe6c13ca1`；对照 `74c0dc1` 中相同的 Human Sol 自主组。谨慎、好奇、直行各用种子 1–72；共 216 局。AI 用延迟感知、可读提示和自身移动记录在真实首征场景中操作。每局 7,200 个物理 tick（120 秒游戏时间）；216 份报告和日志全部通过批处理校验，216 局均在限时结束。统计仅含自主测试，按每句至少送达一次的局数计。

| 台词 | 上版局数 | 本版局数 / 216 | 本版触发率 |
|---|---:|---:|---:|
| Hale 交代试闸 | 216 | 216 | 100% |
| Hale 查明插销 | 95 | 95 | 43.98% |
| 塌拱与档案翼 | 28 | 28 | 12.96% |
| 壁龛备用油壶 | 3 | 3 | 1.39% |
| 档案门边警告 · 未见证 | 0 | 3 | 1.39% |
| 档案门边警告 · 已见证 | 0 | 0 | 0% |

按「策略＋种子＋台词」逐项配对，只新增 3 个命中，原有命中全部保留。台词送达 342 → 345 次，命中目录 4 → 5 种（共 52 种）。新增均是好奇型的种子 8、44、70，在 tick 5178（86.3 秒）听到未见证警告。三者抽到相同策略参数：反应延迟 16 tick、动作保持 45 tick、初始侧向 −1。

**下一步优先复测玩家到门时 Hale 的位置。** 本版 16 局在采样时进入距门 3.25 米内（好奇 7、直行 9）；其中仅 3 局同时采到 Hale 距门 1.25 米内，也正是听到警告的 3 局。其余 13 局可作为同一区域的未触发对照。坐标每 12 tick 采样一次；这些计数描述同帧位置，剧情状态和字幕占用仍由游戏逐帧判定。交互图和 `order.csv` 保留上版 2.60 米的固定审计范围用于跨版比较；本版该范围也有 16 局到访。窗前双人注视、已见证门边警告和铁闸死锁提示均为零命中。

[全部台词与策略概率](rates.csv) · [送达位置与 tick](hits.csv) · [门边顺序](order.csv) · [逐局门边距离采样计数](door-samples.csv)

## 复现

仓库根目录 PowerShell：

```powershell
$env:DOTNET_ROOT='C:/Program Files/dotnet'
$s=1..72
python tools/expedition/human_batch.py run --seeds $s --ticks 7200 --jobs 6 --timeout 180
# 替换为刚输出的批次路径；下列为本报告使用的批次。
$h='.runtime/human_batch/20261124T140129Z-f72b47e1'
$p='docs/production/expedition-01/playtest'; $o='.runtime/ai-rerun-atlas'
python -B "$p/test_dialogue_atlas.py"
python -B "$p/dialogue_atlas.py" --human $h --out $o
python -B "$p/autonomous_figure.py" --human $h --out $o
```
