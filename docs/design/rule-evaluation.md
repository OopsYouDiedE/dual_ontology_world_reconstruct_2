# 十关规则博弈评测 · v2

独立的第一人称 Godot Forward+ 场景。连接、碰撞、相位、压板、物理预警、规则及心理变化由 60 Hz 整数裁判持有；Godot 播放同一套状态和角色动作。第 3、7 关各加入一名同伴。跨过第 10 关的门槛即抵达 Main Camp Hall。飞轮和擒纵仪表沿用 Blue Prince 实验室的 CageDrive、Balance 装置网格；按台架包络安装，随裁判相位转动。营地陈列同一美术库的参考场景图版。

## 试玩、截图与录像

从仓库根目录运行。Godot 为项目的 4.7.2 .NET 版；评测只需 CPython 3.10+ 标准库。正式成绩需对照报告中的精确 CPython 版本与 Fuel ABI。

```powershell
$godot = '.runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64.exe'
$python = (Get-Command python).Source
$out = '.runtime/rule-evaluation'
& $godot --path . res://scenes/rule_evaluation/Evaluation.tscn -- --run-seed=107 --python=$python
& $godot --path . res://scenes/rule_evaluation/Evaluation.tscn -- --run-seed=107 --python=$python --eval-review
python -m unittest discover -s core/rule_evaluation -t . -p 'test*.py'
python -m core.rule_evaluation.batch --seeds 107 --roster target --out "$out/demo"
python -m core.rule_evaluation.participant --verify-replay "$out/demo/replays/107.target.json"
# The playthrough exporter requires FFmpeg on PATH.
python tools/rule_evaluation/playthrough.py --replay "$out/demo/replays/107.target.json" --out "$out/demo-film"
& .runtime/python/Scripts/python.exe tools/rule_evaluation/capture.py --seed 107 --crew-film "$out/demo-film" --out "$out/demo-captures"
```

`Tab` 开合 Field Notebook，`WASD` 移动，鼠标转向，`E` 操作，`Z` 切换器械动作，`C` 蹲下，`F` 投放探针。`0/1/2` 选择主控或同伴，`R` 同步同伴，`O` 切换观察证据，`P` 递交所选证据。擒纵室同步 Finch 并看清工作台和两只时钟后，`Y` 提交工作台文档论证。手册底部可输入结构化动作；`H` 开关可选提示。

- **截图**：游戏 MCP 的 `on(scene="rule_evaluation", eval_review=true, seed=107)` 启动真实 Forward+ 窗口。`PgUp/PgDn` 浏览入场、实体联动、场景危险与恢复等状态。`capture.py` 输出截图与 `manifest.json`，`--crew-film` 合入同伴与所操作器械同框的动作起点、机构响应两张画面，并在清单记录物理步、角色、电影帧和回放来源。`--crew-only` 可单独收集这些镜头。
- **全程录像**：`playthrough.py` 在真实 Forward+ 运行中把已验证的动作包逐个送回 Godot 场景，抓取连续帧并用 FFmpeg 生成 H.264 MP4。镜头在操作、说服和换房时暂停或切到同伴视角以便阅读，裁判的 60 Hz 轨迹保持原样。`receipt.json` 核对步数、状态哈希、渲染模式和营地终局。

## 十关的公开课程

| 关 | 工位 | 机制与危险分岔 |
|---:|---|---|
| 1 | The Synchronizer | 求两只凸轮的抬升重叠，再锁存闩。 |
| 2 | The Inspection Gallery | 对照 `MASTER` 的支架，拒收横臂上下倒装的一组。 |
| 3 | The Spring-Bolt Gallery | 用安全证据修订手册；让同伴踩踏板、抛栓、离板。 |
| 4 | The Indexed Flywheel | 接收位与飞轮相位耦合；双送载会升起红色活塞，接收位可卸压。 |
| 5 | Counterweight Transfer | 用测试配重先移车，再用远侧压板接力。带载丢弃测试配重会导致小车回滑，在离合工位接住配重。 |
| 6 | The Low-Sight Shutter | 泄压后蹲姿使用低位准星，交由同伴封阀并抬闸。闭闸排汽会困住蒸汽，可在准星台隔离。 |
| 7 | Counterweight Exchange | 两名同伴分别占住压板并接上载荷；带载解耦会落下配重，复位棘轮可恢复。 |
| 8 | Escapement Gantry | 计算双擒纵工作扇区。可通过试车，也可用公开手册和互斥联锁做限相签核；越相旁通会卡住龙门架。 |
| 9 | The Shadow Register | 依次交接两侧控制，抬遮板后对准定向投影并蹲姿读取；开启虹膜会造成眩光，在控制台盖回。 |
| 10 | Foundry Transfer | 抬升相位才能移载，撤位顺序由公开房规给出，低相位卸载。误顶止挡时从同一工位急停。 |

R5–R9 的房规以 `REQUIRE` 分配试车与带载操作人，个人手册仍可 `FORBID` 同一操作。准入在见证路径的实际联锁状态下执行两条反事实：领队操作被房规拒绝，指定同伴不持有效修订时被个人手册拒绝。证据经实际可见交互生成，实体反馈改变须可观察，满 40 tick 才成熟。R8 还可用两套公开操作联锁、领队时间条款、房规及同步的同伴条款排除越相分支；该修订只在双相位重叠时有效，全程无需空载操作。预警需刺探分支验证可见、同工位可解除、忽略后经过至少 40 个已观测物理步才致死。

## 确定性契约

- **时钟和动作**：物理 60 Hz，决策 3 Hz。动作包最多六项，`delay_ticks:0..19`，同偏移按输入顺序。`Move` 的 `[x,z]` 是世界坐标方向，`speed_ratio:0..100`，`duration_ticks:1..20`；默认朝 +z，90° 朝 +x。前进方向与朝向无关。单局 **10,800** 物理步，合 **180 秒 / 540 决策**。准入见证占 **30%–45%**，全局零慌乱，无心理随机性。
- **感知**：整数毫米、整数角度，27 条固定方向射线。暗处的首个命中与超出量程均返回 `UNOBSERVABLE`；暗处几何仍可遮挡。白盒操作与规律只在首次采样后可取。已同步的同伴显式共享规则与观测记录；心理篡改无广播，灰盒致死谓词始终留在裁判侧。
- **说服**：引用历史证据 ID 或已同步的签核前提，按规则节点限定修订。R5–R9 的合法未成熟证据可重试，不增加慌乱。无依据覆写会增加慌乱，进而引发拒绝、干扰、静默篡改或失能。裁判侧记录拒绝原因；参加政策只读黑盒结果。
- **开发接口**：`python -m core.rule_evaluation.participant --seed 101` 是非计量 JSONL 观察入口。`python -m core.rule_evaluation.training POLICY --seeds 101 --log .runtime/train-101.jsonl` 通过正式沙盒运行，日志仅含选手自身观测、动作和 Fuel。公开训练种子为 `101 113 127 139 149 163`；关于单位、证据和初始接口的补充见 [公开课程包](../../core/rule_evaluation/baselines/sol-public-packet.md)。

## 公平赛道与封卷顺序

Target、Sol、`reflex`、`no_persuasion`、`no_phase_memory` 都进入 `rule-policy/guarded-python-opcode-v2`，接收同一观察和动作。Target 的既有课程策略展开为同一种受限 Python 源码；Oracle 使用房间构造见证，只做准入。旧 `sol-v1.asm`、`sol-v1.json` 留作历史审计。参见 [政策子集和计量](rule-policy-lane.md)。

开发结束后先封卷，再由裁判抽取留出与泛化种子，两组互斥且排除公开训练/旧基准种子。已公布的测试组只用于复现历史，下一轮冻结版使用重新抽取的种子。

```powershell
$dir = 'core/rule_evaluation/baselines'
$sol = "$dir/sol-v2.policy.py"
python -m core.rule_evaluation.benchlock freeze $sol "$dir/sol-v2.author.json" "$out/freeze.json"
python -m core.rule_evaluation.benchlock draw "$out/freeze.json" "$out/cohorts.json" --holdout 12 --generalization 16
python -m core.rule_evaluation.batch --suite both --sol-policy $sol --freeze-lock "$out/freeze.json" --blind-manifest "$out/cohorts.json" --require-acceptance --out "$out/scored"
```

`--require-acceptance` 要求全部设计门禁、原动作回放逐步一致、重新运行政策的动作及 Fuel 链一致，并在**每一组**满足 Target ≥90% 通关；Sol ≥90% 通过前三关、≥80% 抵达 R5 或之后、≥80% 的整组局数有 R5–R10 的规则/相位失败证据，且全局通关率为 0%。门禁不满足时报表仍会写出，CLI 返回非零。对照试验先在 `--suite standard --seeds …` 上做，保持种子和政策哈希一致；`compare.py` 输出变化及处理建议。

## 自动归因

`report.json` 保存带证据的多标签归因，`triage.md` 按席位、关卡、原因分组，直接定位样例轨迹与 tick。录像只能展示人看到的画面；诊断回放另含裁判事件、归一动作包、计算候选数和两种哈希链。报告区分 `VM_FUEL_CAP_HIT`、`NO_PROGRESS_LOOP`、`WRONG_TARGET_SELECTED`、`EVIDENCE_IMMATURE`、`RULE_DEADLOCK_STALL`、`HAZARD_IGNORED` 等。有效单步等待、成功后恢复的冲突和未见预警各走独立判定。匹配操作失败的频率只提出排查方向；界面根因需结合现场截图与回放证实。

## 本轮实际结果

见 [v2 封卷盲测结果](rule-evaluation-v2-results.md)：两组共 28 个种子，Sol 与 Target 均全部通关。公平赛道已经可用；难度区分门禁仍未通过。
