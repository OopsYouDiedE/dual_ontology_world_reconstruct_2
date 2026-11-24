# Expedition 01 对话采样：21,312 个原网格案例

本工具只读加载 `tools/expedition/walk_campaign.py` 的 `CASES`、`PLAN`、`command(case, replay)` 和源码指纹函数，沿用原案例 ID、顺序、参数及完整场景命令。每局从实际 `route.json` 采集事件；不查询或写入既有监督器、队列、结果数据库。只以前台单进程串行执行，一次启动一个 Godot 子进程。默认最多新增四局，显式 `--all` 才会跑完剩余网格。

## 运行和续跑

在仓库根目录执行：

```powershell
$tool = 'docs/production/expedition-01/playtest/dialogue_campaign.py'
python $tool run --name dialogue-campaign-smoke --limit 3
python $tool run --name dialogue-campaign-smoke --limit 1
python $tool report --name dialogue-campaign-smoke
# 将来需要补齐时再显式运行；本次未执行：
python $tool run --name dialogue-campaign-smoke --all
```

同一个 `--name` 使用同一个 SQLite；每局回执和全部事件在同一事务提交。中断后，用同名重新执行，已提交案例默认跳过。`--retry-incomplete` 可追加缺失／无效 route 或基础设施类失败的尝试，旧回执与事件仍在；有效的死亡记录默认保留并跳过。四次连续采集/基础设施故障后停止。独立 Windows 文件锁阻止两次写入同一目录；运行前锁定原网格及原工具的源码指纹，每局提交前重新核对。指纹漂移时保留此前记录并停止；恢复原基线或使用新 `--name`。Godot 的用户目录、`route.json`、`archive.json`、临时日志都写入当前采样目录的单局 scratch，局后清理。SQLite 留存 route 元数据、原始事件对象和关键 stdout 回执；不留存两条逐帧轨迹或完整日志。

## SQLite 查询口径

- `attempts`：每次尝试，含原案例 ID、参数、命令、状态、退出码、实际 route 终止 tick、独立的 stdout 终止 tick、死亡原因和诊断。`route_state` 区分有效、缺失和无效；缺失时事件计数为 NULL，代表没有采到。
- `runs`：每个案例的最新回执。`events`：按 `attempt_id, ordinal` 保留实际事件数组顺序和完整单事件 JSON；同 tick 的多个事件都保留。
- `dialogue`：筛选 `event == 'dialogue'`，保留原文（含说话人）、玩家脚点 `(x,y,z)`、tick 和百分比。百分比为 `100 × 事件 tick / 本局 route.json 终止 tick`；死亡局以死亡前实际记录结束为 100% 基准。零时长为 NULL。该指标表示时间进度。
- 死亡局按 `WALK_DEATH` 或有效 route 的 `failed` + 失败原因识别。实际采到的整个死亡事件流与回执一起保存；若进程只留下死亡回执，仍保留死亡行并明确标记 route 缺失/无效。

```sql
SELECT d.case_id, d.tick, ROUND(d.percent, 2) AS pct, d.x, d.y, d.z, d.value
FROM dialogue d JOIN runs r USING (attempt_id)
ORDER BY d.case_id, d.ordinal;

SELECT case_id, attempt_id, failure_reason, route_state, dialogue_count
FROM attempts WHERE status = 'gameplay_death' ORDER BY case_id, attempt_id;
```

## 台词触发率：命中局数 / 全部有效局（含死亡）

触发率按**独立案例**计算。分母取 `runs` 中最新回执有有效 `route.json`、且该局已完成或已确认死亡的案例；无效、缺失和非死亡中断的采样不进入分母。有有效事件流的死亡局进入分母；若它在死亡前触发了目标台词，也进入分子。同一案例重复触发只计一次。以下用 `:line` 精确匹配一条台词的原始 `value`（含说话人）；分母为零时触发率返回 NULL。

```sql
WITH valid_runs AS (
    SELECT case_id, attempt_id
    FROM runs
    WHERE route_state = 'valid'
      AND (status = 'gameplay_death' OR json_extract(route_header, '$.outcome') = 'completed')
), hits AS (
    SELECT DISTINCT v.case_id
    FROM valid_runs v JOIN dialogue d USING (attempt_id)
    WHERE d.value = :line
)
SELECT COUNT(h.case_id) AS hit_runs,
       COUNT(*) AS valid_runs_including_deaths,
       ROUND(100.0 * COUNT(h.case_id) / NULLIF(COUNT(*), 0), 2) AS trigger_rate_pct
FROM valid_runs v LEFT JOIN hits h USING (case_id);
```

`dialogue.percent` 是**单局台词出现时的时间进度**；`trigger_rate_pct` 是**跨局触发率**，只使用命中局数和有效局数。

## 本次核验

真实 Godot 4.7.2 .NET：先运行 1–3，再同名续跑；第二次只追加第 4 局。四局均完成，实际 route 记录 **221 个事件、47 条台词**。各局台词数依序为 **15 / 10 / 8 / 14**；SQLite `integrity_check` 为 `ok`，外键检查无异常。第 1 局 Hale 的第二条台词采于 tick 551（7.744%）。四局均未自然死亡。输出为 `.runtime/dialogue-campaign-smoke/dialogue.sqlite3`。
