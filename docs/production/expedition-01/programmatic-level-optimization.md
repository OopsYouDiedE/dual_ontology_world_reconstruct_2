# 统一关卡结构与程序化迭代优化方案

本文档定义了《沉睡学院》（`Expedition-01` 与肉鸽主线 `core/rogue_topology`）共享的**声明式关卡图谱（Unified Level Graph）**与**闭环程序化迭代管线**，让关卡几何调整、规则叠加与手感调参能够在写 3D 白模之前就完成定量筛选，并在落地后自动回归。

## 1. 统一结构模型（RoomNode + RouteEdge）

所有关卡（包括序章三段式远征与肉鸽随机房牌）统一抽象为同一套数据契约：

- **节点 (`RoomNode`)**：`id`、`section` (`A | B | C | RETURN`)、`role` (`entry | hub | puzzle | resource | control | objective | exit | bypass`)、`rules`（生效契约列表）、`oil_delta`、`decision_points`、`is_checkpoint`。
- **边 (`RouteEdge`)**：`src`、`dst`、`length_m`、`bidirectional`、`stance_req` (`any | quiet | still | sprint`)、`oil_cost`、`noise_risk`、`rules_tested`（同时检验的规则集合）、`tags`（`main | shortcut | stealth_bypass | recovery | return_oneway`）。

该模型与项目现有的 [route_matrix.py](../../../tools/expedition/route_matrix.py)、[human_batch.py](../../../tools/expedition/human_batch.py) 及 [DuelView.RogueTopology](../../../core/rogue_topology/Topology.cs) 一一对应，确保“图谱层 → 几何层 → 胶囊物理层 → 类人盲测层”四层同源。

## 2. 程序化迭代闭环（5 步自动化工作流）

1. **图谱变异生成（Graph Mutation）**：在 [level_iterate.py](../../../tools/expedition/level_iterate.py) 中对基线拓扑施加结构算子（如 `M1: +B6 泵房`、`M2: +C2 桥下静步环道`、`M3: 联合结构 + C5 返程支路`），或参数微调算子（调整灯油补给、静步门槛、折返缓冲）。
2. **静态结构硬门禁与多目标打分（Fast Graph Eval，<0.1 s）**：
   - **硬门禁**：去程/返程最短路连通、坠落恢复区（`C1_floor`）必可徒步回桥头（零软锁）。
   - **目标函数 (`fitness_score`, 0–100)**：综合评估**总决策点密度**、**后半段（C/撤离）决策权重**、**多规则同时生效边占比（`>=2` 条规则叠加）**、**环路冗余度（圈复杂度）**与**去程/井段路线多样性**。
3. **几何实例化（Parametric Geometry）**：仅将排名前 1–2 的变异体接入 `ExpeditionKit.gd` / `ArchBuilder` 参数化房间配方。
4. **物理与规则回归门禁（Headless Godot 60 Hz）**：自动跑 `WalkTest.gd`、`FeelTest.gd`、`ContractTest.gd`、`HearingTest.gd`、`NicheTest.gd`、`ShaftRecoveryTest.gd` 与 `stair_support_sweep.gd`，强制零前兆致死为 0、零穿模与零软锁。
5. **类人盲测与真人 A/B 筛选**：调用 `human_batch.py` 统计停滞热区（如 B2→B3 转化率）并写入 `docs/production/expedition-01/playtest/preference/`，把卡点反馈回第 1 步作为下一轮变异目标。

## 3. 运行方式

```bash
python3 tools/expedition/level_iterate.py --json .runtime/level_opt_report.json
```
