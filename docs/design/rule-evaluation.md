# 十关规则博弈评测基底

评测入口是独立的 Godot Forward+ 场景。常规出征入口仍保留。两者共用仓库的白模材质、既有角色模型和动作库。评测角色的坐标、门禁、压板、相位、规则、证据和心理状态都由整数仿真裁判持有，Godot 负责第一人称呈现和操作。

## 试玩、截图、评测

从仓库根目录运行。Godot 使用项目配备的 4.7.2 .NET 版；评测器仅依赖 Python 3.10+ 标准库。

```powershell
$godot = '.runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64.exe'
$python = (Get-Command python).Source
& $godot --path . res://scenes/rule_evaluation/Evaluation.tscn -- --run-seed=1 --python=$python
& $godot --path . res://scenes/rule_evaluation/Evaluation.tscn -- --run-seed=1 --python=$python --eval-review

python -m unittest core.rule_evaluation.test_evaluation -v
$sol = 'core/rule_evaluation/baselines/sol-v1.json'
$out = '.runtime/rule-evaluation'
python -m core.rule_evaluation.batch --suite both --roster target reflex no_persuasion no_phase_memory sol --sol-policy $sol --require-acceptance --out "$out/accepted"
python -m core.rule_evaluation.participant --verify-replay "$out/accepted/replays/107.target.json"
& .runtime/python/Scripts/python.exe tools/rule_evaluation/capture.py --seed 107 --out "$out/release-captures"
& .runtime/python/Scripts/python.exe tools/rule_evaluation/live_smoke.py
```

- **试玩**：开局发放 Field Notebook。`Tab` 开合手册（打开时暂停），手册末页列出已观察器材的白盒条件和状态转移，`H` 在手册中开关可选调试提示；`WASD` 移动，鼠标转向，`E` 操作（对着打开的门可辅助走过门槛），`Z` 切换同一机关的动作，`C` 蹲下，`F` 投放安全探针。`0/1/2` 选择主控或同伴；`R` 同步所选同伴，`O` 切换已有证据，`P` 将证据送给所选同伴。手册底部可发送类型化命令，适用于精确延迟、遥控转向、和同一决策内的复合动作。`Space` 暂停。
- **现场审查**：游戏 MCP 的 `on(scene="rule_evaluation", eval_review=true, seed=1)` 打开真实 Forward+ 窗口。`eval_next_review` / `eval_prev_review`（键盘 `PgUp/PgDn`）浏览真实仿真快照。截图库输出 `manifest.json`：房间、物理步、门状态、窗口截图及所属 MCP 会话。特殊分支成对显示预警出现、就地恢复；它们从安全回放的同一节点分岔。
- **参赛协议**：`python -m core.rule_evaluation.participant --seed 1`。每行输入一个动作、动作数组或 `{"actions":[...]}`；每行输出新的黑盒观测。用于政策调试与记录交互，实时 Fuel 认证走 `batch` 的隔离 VM。Godot 专用的视觉桥另有协议；参赛 VM 无权访问该桥或回放接口。

## 十关的公开课程

| 关 | 工位 | 通用能力与关键物理读数 |
|---:|---|---|
| 1 | The Synchronizer | 看两只凸轮的抬升区间，求重叠后锁存闩。 |
| 2 | The Inspection Gallery | 对照标为 `MASTER` 的支架，找出三组中横臂上下倒装的一组。 |
| 3 | The Spring-Bolt Gallery | 安全试车形成反例；现场让同伴踩踏板、抛栓、离板，再走门。 |
| 4 | The Indexed Flywheel | 由安全空载反例解开双手册僵持；一人在接收站，另一人按飞轮相位送载。过压活塞与卸压是独立的可逆风险分支。 |
| 5 | Counterweight Transfer | 先借测试配重把实体小车移出走道；换成远侧接力后重新移车。 |
| 6 | The Low-Sight Shutter | 打开泄压才能启用低位准星；同伴随后封阀并拉开实体闸门，玩家走过门洞。 |
| 7 | Counterweight Exchange | 示范空行程；两名同伴占各自压板，同时接上两边载荷。 |
| 8 | Escapement Gantry | 给两边离合器上载，并计算两套偏移擒纵的共同传动窗口。 |
| 9 | The Shadow Register | 安全暗态试车换取规则修订；抬起实体遮板后对准定向投影，蹲姿读取。 |
| 10 | Foundry Transfer | 抬升相位才能移载；房间规则指明种子决定的撤位顺序。止挡落定后在低相位卸载。误顶止挡时从同一工位急停。 |

第 3、7 关入队。十道门沿课程顺序通往 Main Camp Hall；步数预算贯穿全程。种子控制房间的镜像、器械间距与行程、支架故障和母样、相位参数及末关角色职责。课程顺序与房间入口类型保持可比较。开门后，主控角色可用 WASD 跨过门槛；辅助通行沿同一条物理碰撞和门槛检测路径运行。独立的构造路径只在准入、回放和审查模式中调用。

## 分层契约

- **时钟和状态**：60 Hz，每 20 个物理步提交一次决策。动作可带 `delay_ticks: 0..19`，同一包最多 6 项，按偏移与输入顺序执行。`Move` 的 `[x,z]` 为世界方向，`speed_ratio` 为 0–100，`duration_ticks` 为 1–20。`Wait` 维持已开始的有限时长动作。达到第 36,000 步时结算。世界使用毫米、整数角度和整数几何；每步滚动 SHA-256，每次决策另存完整逻辑检查点哈希。播种采用有名字的 SplitMix64 派生流，关卡生成和心理风险各有独立随机流。
- **观测和白盒文档**：每次是三层共 27 条射线；横向 −60°…+60°、步距 15°，默认仰角 −15°/0°/+15°，最大 10 米。站姿眼高 1.56 米，蹲姿为 0.94 米，眼高在各姿态内固定。暗处首命中和射程不足都返回同一 `UNOBSERVABLE`，并保持首遮挡。已发现标牌的作用、依赖和周期进入 `equipment`；第二关的故障位置由可见几何给出。同伴只在可见或主动同步时给出各自观测。灰盒危险条件、暗处坐标、未同步的规则变更留在裁判内。
- **类型规则**：`FORBID` 为匹配动作的否决条件；`REQUIRE` 为匹配动作的前置条件；`PERMIT` 为显式许可，不移除其他否决。房间范围由当前房间限定。主控可承担探索风险；同伴的个人 AST 与公开房间 AST 联立，违规命令报告僵持节点。物理门禁独立校验。证据必须引用相同操作的真实记录、有可见或本人直接观测的来源、经过至少 40 tick 无警报成熟期、并在执行时反驳被修订的条款。修订限于精确的操作模式；房间的物理门禁与其余条款保持有效。
- **公平风险**：有致死分支的房间另带准入测试。它检查实体灯或活塞是否真被射线见到、同一操作站能否解除、以及原地等待时死亡距首次可观测警报是否至少 40 tick。其最低联动人数为两人或三人，单人裁判不会触发这些危险。探针安全触发受测表读数，不改写活系统危险状态。无依据强迫累积慌乱；高慌乱进入带种子的指令拒绝和理智侵蚀路径。变更后的 AST 可经主动同步重新获得，或提交具体证据修复。玩家和参赛者都可以绕开强迫，采用零慌乱路线。
- **Fuel**：常规决策 60,000 fuel，首次进房 300,000。每次接受最近一个通过动作语法验证的候选；用尽时沿用其候选，从未提交则 `Wait`。指令数是固定的算力度量档位，不把 60,000 个指令声明成实测 100 ms；同种程序在宿主繁忙时仍有相同截断点。仓库内参考程序用受信 CPython opcode 计数，报告记录运行时版本；复评应使用同一版本。外来政策用隔离 VM 的固定燃料表。两个计量域的原始指令数分别解释。实跑模型的推理服务若需作为选手，必须提供其可冻结、可计量的政策产物或等价运行器。

## 报告和迭代

标准集 16 个种子、留出集 8 个种子。`--seeds` 可指定测试集，`--random-seeds N --seed-key K` 以独立 PRNG 产生可复现的新种子。`--config` 读取 JSON，例如 `{"phase_window_bias":-20,"coerce":3600}`：以物理步缩短开放窗口（裁判仍执行最小 60 步检查），调整每次强迫的慌乱增量（单位为百分之一）。

准入检查零慌乱见证（≤16,200 步）、逐 tick / 决策回放、单相与组合时窗的采样下界、关键器械及静态几何线索的采样发现、预警与恢复分支、以及公开操作和真实实现的一致。第 3–10 关还须记录至少一个原生规则会拒绝、用安全反例说服后成功执行的协作动作。当前门禁以规则形状、危险联动人数下界及联立动作的见证来验证本课程；任意新增 DSL 的全状态空间性质需要另行证明。

`report.json` 分别给出门禁、各参赛者、平均通关深度、区分度、证据准确率、理智保留率及多角色时序耦合率。思考/执行比用已消耗 fuel 除以实际执行的交互次数；步数效率以构造见证为参考。失败有带原始事件的可回放轨迹。相位标签要求当前非时序条件保持不变时，推进时钟可解开被拒操作；失败上下文同时记录房间、未采到的目标、卡住的规则节点及事件计数。分类可同时命中；证据不足的失败归为 `UNRESOLVED_PLANNING_FAILURE`。回放含归一动作包、哈希和事件，不给选手提供旁路信息。

- `target` 是课程感知的参考程序：由观测导航、量测几何、推算相位、检索证据和执行多角色计划。它使用公开的课程设备和工序知识，作为关卡回归标尺；其成绩按这份能力画像理解。
- `reflex` 是固定的反射对照；`no_persuasion` 和 `no_phase_memory` 是参考程序的消融。四者共用观测和动作协议。
- `sol` 是单独席位。仓库附带的 [冻结政策](../../core/rule_evaluation/baselines/sol-v1.json) 由独立 `gpt-6.2-sol` 按[公开课程与 VM 接口](../../core/rule_evaluation/baselines/sol-public-packet.md) 编写，在未获种子、裁判源码或评分反馈前提交。汇编器只解析指令和标签并验证 ABI。`--sol-policy FILE` 要求 JSON `{model:"gpt-6.2-sol", revision, provenance, ability_profile, program}`，冻结 SHA-256，走 VM 实时计量。`--sol-traces FILE` 接收 `{model, revision, runs}`，`runs` 按种子提供动作流，只用于诊断回放。缺席时记录 `UNENROLLED`。`--require-acceptance` 要求全部门禁、Target ≥90% 且冻结 Sol 全集 0%；追踪回放和其他基线的成绩不填补这一席位。

VM 目前有 `load / const / copy / get / length / lt / eq / add / sub / mul / mod / and / or / not / jump / if / object / array / emit / stop`。带操作数示例：`["const",0,{"type":"Wait"}], ["emit",0], ["stop"]`。寄存器跨决策保存。无文件、网络、计时器或调用系统命令的指令。

### 配对迭代示例

同一批种子、同一冻结政策，分别评测默认值和相位窗口偏置 `-20`。报告按关核对是否因时序变化产生新的未采样线索或不可避免的短窗口；配对工具输出通关、深度、效率与诊断差异。

```powershell
'{"phase_window_bias":-20}' | Set-Content -Encoding ascii "$out/narrow-window.json"
python -m core.rule_evaluation.batch --suite both --roster target sol --sol-policy $sol --config "$out/narrow-window.json" --require-acceptance --out "$out/candidate-narrow"
python -m core.rule_evaluation.compare "$out/accepted/report.json" "$out/candidate-narrow/report.json" --out "$out/comparison.json"
```

### 本次发布基线

| 测试集 | Target 全十关 | 冻结 Sol 全十关 | Sol 平均通过关数 |
| --- | ---: | ---: | ---: |
| 标准 + 留出（24） | 24/24 | 0/24 | 1.71 |
| 泛化（33，含 32 个新种子） | 33/33 | 0/33 | 1.61 |

两组都通过所有零慌乱、复现、射线与时序采样门禁，记录到的脏失败数为 0。默认 24 个种子的构造路线为 3,840–4,460 物理步；第 4、10 关的警报分支均由实际射线发现，忽略警报时至少保留 40 物理步，就地处置可在一个决策周期内消警。禁用说服的对照组均停在第 3 关，禁用相位记忆的对照组均停在第 4 关。冻结 Sol 在标准 + 留出集有 7 局停在第 2 关、17 局停在第 3 关，详见各局的操作互锁与回放事件；现有事件支持定位阻塞步骤，精确的规划根因保留为未归因。

偏置 `-20` 的配对结果保持同样的通关和深度分布，Target 平均多用 5 个物理步。保留默认时窗，给实机执行留出余量。正式截图及动态帧清单由 `capture.py` 生成；分关审查和集成审查使用实际 Forward+ 画面，修改后再拍。另在干净暂存树复验 .NET 构建、Godot 资源导入、正式出征回归与评测场景输入；种子 107 的完整构造路线在 Windows 与 WSL Ubuntu 上得到一致的终局和逐步链哈希。

```powershell
python -m core.rule_evaluation.batch --seeds 41 --random-seeds 32 --seed-key 609842 --roster target sol --sol-policy $sol --require-acceptance --out "$out/generalization-blind"
```
