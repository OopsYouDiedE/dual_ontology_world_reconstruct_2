# 2026-11-24 · 从首次出征到天文台：478 局路线与剧情测试

[首征交互图：按走法、台词原文或零命中筛选](index.html) · [首征路线和台词概率图](first-expedition.png) · [返营后路线图](campaign-routes.png)

| 实验 | 独立案例 | 实际结果 |
|---|---:|---|
| 首征自主探索：Human Sol，三种感知策略 × 种子 1–72 | 216 | 全部到达 7,200 tick 上限（每局 120 秒），4/52 种字幕有送达，342 次 |
| 首征定向对照：见证／跳过／途经档案窗 × 北线／南线 | 6 | 5 局撤离；途经档案窗走南线的一局取芯后遭听觉猎手扑击。20/52 种字幕有送达，67 次 |
| 返营后独行：地图种子 1–256 | 256 | 223 局敲钟，33 局途中失败；27 种实际房间序列，80 种机关回执 |

**下一轮先测铁闸到档案翼的转向。** 216 局中，205 局踏入铁闸空间范围；95 局听到 Hale 试闸后提及绿门的台词，28 局看到档案翼区域牌并听到塌拱台词。再向内，16 局曾进入档案门边空间范围，两种门边台词均为 0 局；定向对照在此分别触发 4 次未见证分支、2 次见证分支。建议先在门边记录玩家与 Hale 的相对距离、剧情状态和字幕占用，以区分到达、满足条件和送达。上述数字是各自事件的边际计数，不假定所有局都按同一顺序经过。

**返营后最值得复核的是折返闸。** 256 局全部抵达，19 局在这里耗尽生命；西翼第三间失败 8 局、东翼第三间失败 6 局。74 局乘车回营；抵达天文台的 223 局全部敲响晨钟。折返与否由此处可用目的地等概率抽取。

## 样本与读法

- 两个首征组均在 Godot 4.7.2 .NET 中以 60 Hz、真实玩家胶囊和触发器运行，使用原有 `strategy-light` 无头夹具。自主策略只用延迟感知与玩家输入；种子影响反应、动作保持时长、初始偏向，多个种子可产生同一策略参数。定向组统一种子 73、双补给、到点半径 0.12 m、额外等待 116 ticks。另用游戏 MCP 对首征入口做了 Forward+ 画面抽查。
- 触发率取**本组至少送达一次该句的局数 / 本组的全部有效局数**，包含限时与死亡。同一文本重复播出只算一个命中局；HUD 镜像和操作反馈不算台词。空间曝光另按区域采样计数。三组独立抽样，尤其返营后直接初始化为首征已返回，不与首征拼成连续存档，也不推算真人通关率。
- 首征脚点每 12 个物理 tick 记录一次，交互图每五个样本取一点连线。图中固定路线用于检验后段分支是否可触发。目录覆盖静态可识别的中文台词及实际观察到的文本；本批次使用游戏默认中文。
- 返营后用独行队长运行真实 `new_run/travel/_inspect/_act`，跳过房间绘制与步行；只在界面启用的选项中优先尝试本房最少用过的选项，同次数由种子打破平局。回执是英文机关叙事，与首征角色台词分表。相同种子重跑 256 局，房间、步骤、回执和结局逐项一致；重跑不计入样本量。

## 数据与复现

[台词命中率](rates.csv) · [每次送达的坐标和 tick](hits.csv) · [门边分支顺序](order.csv) · [战役逐局路线](campaign-runs.csv) · [有向边经过率](campaign-edges.csv) · [机关回执率](campaign-lines.csv) · [每次操作与回执（压缩 CSV）](campaign-actions.csv.gz)

在仓库根执行（Python 需 matplotlib；字体默认 Microsoft YaHei）：

```powershell
$env:DOTNET_ROOT='C:/Program Files/dotnet'
$s=1..72
python tools/expedition/human_batch.py run --seeds $s --ticks 7200 --jobs 6 --timeout 180
python tools/expedition/route_matrix.py --seed 73 --jobs 2 --loadouts both --crossings north south
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . --log-file .runtime/campaign-story.log -s res://tools/expedition/campaign_story_batch.gd > $null
# 使用对应批次的输出目录；下列为本次已验收的输入。
$h='.runtime/human_batch/20261124T131950Z-7457dd8f'; $m='.runtime/route-matrix/seed73-840s6vw2'
$p='docs/production/expedition-01/playtest'; $o='.runtime/story-batch-report'
python -B "$p/test_dialogue_atlas.py"
python -B "$p/story_batch_figures.py" --matrix $m --human $h --campaign-log .runtime/campaign-story.log --out $o
python -B "$p/dialogue_atlas.py" --matrix $m --human $h --out $o
```

固定路线工具会为游戏内死亡返回非零；检查单局 `outcome`、原因与引擎日志。本批将上述一局死亡保留在 6 局分母中。预检中发现的 .NET hostfxr 配置错误批次已弃用；216 局来自更正运行时后的同一个完整批次，所有单局均通过报告及日志验证。
