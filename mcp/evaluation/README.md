# 第一章评估 MCP 与测试工作流

本目录提供测试与报告基础设施；用户已于 2026-11-16 撤销此前「不优化游戏」的限制，正式游戏修复另在生产场景中记录并单独回归。开发诊断、Mock、固定步长、软件渲染截图均**不是正式验收**。已有 `mcp/review/` 的不可变评分、七项验收与独立 Terra 来源校验仍是唯一的正式评审入口，本服务复用其进展账本和导出器，不伪造评分。

## 组成与边界

- `server.py`：标准 MCP stdio 服务；提供 `evaluation_start/status/cancel/gate`、`progress_append`、`render_report`。
- `worker.py`、`common.py`：真实 Godot 子进程、来源/PID 校验、独立存档和证据目录、超时回收、资源限流。
- `client.py`：实际经过 MCP 初始化、工具发现和工具调用的命令行客户端。
- `examples/`：已完成的一次开发测试汇报快照；它只示范报告格式，不代表独立盲测或通关。
- `tools/testing/TestWorkbench.gd` 和现有 `ScenarioLoader.gd`：读取支持测试契约的项目内场景及经校验的 YAML Mock 状态。按用户原有决定，测试工作台监控栏**默认隐藏但继续采集**；F2 或 `--monitor-visible=true` 可显式打开，`scenario` MCP 参数 `monitor_visible:true` 同理。正式游戏不变。

进入、读写和快照路径绑定服务文件所在的**唯一命名检出** `dual_ontology_world_reconstruct_2`；提供的 `expected_project_root` 仅作为附加断言，不能改变授权根。每个运行单独记录 Git 版本、源码指纹、Godot 路径与哈希、实际 PID、进程创建时间、命令行及工作目录。截图核对同一工程、同一 Godot PID 和 SHA-256；不要把其他工程的截图或快照移作当前验收。

## Linux 准备

在指定工程根目录执行：

```bash
python3 -m venv .runtime/python
.runtime/python/bin/pip install -r mcp/evaluation/requirements.txt
.runtime/python/bin/python mcp/evaluation/install_godot.py --import
```

安装器从 Godot 官方 4.7.2 版本下载**标准版** Linux x86-64，按官方 SHA-512 校验并安装在 `.runtime/godot/4.7.2/`；`--import` 以已校验的工程根运行资源导入。正式主线为 GDScript，可使用标准版；C# 生活测试及 CLI 仍需项目原有的 Godot .NET 和 .NET SDK 8。无图形桌面时，渲染采集需要 Xvfb 与 Mesa；响度分析需要 FFmpeg。Debian 系统可由有权限的管理员安装 `xvfb xauth ffmpeg libgl1-mesa-dri`。不要把测试所得软件渲染 FPS 当作真实硬件性能结果。

MCP 客户端的 stdio 配置示例：`command` 使用本检出 `.runtime/python/bin/python` 的绝对路径，`args` 包含本检出 `mcp/evaluation/server.py` 的绝对路径及 `--expected-project-root`、本检出根目录；`cwd` 指向该根目录。不要把服务注册到另一个检出。也可以直接用以下客户端，无需编辑 MCP 配置。

## 主线优先、特殊 UI 并行

Windows 项目已在 `.codex/config.toml` 注册本服务。常驻 MCP 的 `evaluation_start` 立即返回 `run_id`；Windows 命令行客户端会保持会话至批次结束，避免虚拟环境启动器退出时回收后台进程，并在输出中附带最终状态。后台 worker 使用实际 Python 解释器及项目依赖路径，收据记录实际执行 PID。Linux 客户端保持异步启动行为。

```bash
.runtime/python/bin/python mcp/evaluation/client.py evaluation_start \
  --arguments '{"profile":"chapter1_ui","rendered":true,"max_seconds":600}'
# 从返回结果复制真实 run_id，再查询；以下只表示参数结构
.runtime/python/bin/python mcp/evaluation/client.py evaluation_status \
  --arguments '{"run_id":"<实际返回的run_id>"}'
.runtime/python/bin/python mcp/evaluation/client.py evaluation_gate \
  --arguments '{"run_id":"<实际返回的run_id>"}'
```

批次首先执行第一章诊断与测试快照，再安排起床/走廊/厨房快检、标题/探索/书本 UI 契约以及可选实机截图。仅排查主线时可使用 `evaluation_start` 的 `{"profile":"chapter1_flow","rendered":false}`；该单项批次缺少房间快检，不能放行慢环。可选参数 `motion_time_scale:1.0` 仅在开发探针的行走／过门期间降低时间缩放，避免 120 倍加速产生超大步长；其他阶段仍加速，结果不是自然游玩或性能采样。`chapter1_flow.gd` 的后段**主动补证并输入已知答案**，仅检查逻辑连通，不是自然游玩，也不是从标题开始的盲测；30 秒状态无进展会记录路径、NPC 距离与切换状态并结束探针，不能单凭停滞认定游戏失败。针对已定位的 `2F-cross-M` 开发过门诊断，默认目标为 `1F-Shaft-Monitor`；可设 `pretransit_to:"T01"` 追查下一处讲堂过门。探针会在下一帧前主动调用生产换房 watcher，再验证侦探、原相机和规则状态未变，保存出门阶段的首步前快照；此调用是人为介入，不是自然流程记录。worker 核对日志标记、路径、所选房间、宿主 PID、开发标志与快照载荷哈希后才将其写入证据账本；后续仍须在 Godot 内恢复并核实快照内容。UI 测试恢复快照，同样不具备验收资格。书本动画测试分别记录各步墙钟耗时及旧 3 秒阈值，软件渲染下最多等待 15 秒检查功能；超时后不执行依赖步骤，避免连锁误报，亦不能据此认定目标硬件性能合格。`rendered=false` 使用无头固定步长，不产生视觉证据。

`status.json` / `report.yaml` 的 `jobs` 在开始时列出本 profile 计划的检查；依赖失败、取消或启动前中断导致的未执行项保留为 `blocked`，不会遗漏可选视觉检查。`observed_concurrency.peak_live_hosts` 在成功校验新宿主时记录同时存活的本批次 Godot 进程数，`witness` 给出对应 job 和 PID；这是一组观测下界，而非系统范围进程总数、FPS 或验收评分。各 job 的原有路径、射线、耗时、场景采样等客观结果仍位于对应 `detail` 和原始证据文件中。该批次覆盖第一章诊断与 UI/房间快检，生活模拟、CLI 和独立盲测各有其他入口，不能由此批次推定覆盖。

For rendered evaluations, MCP uses the native Windows display or a reachable Linux Wayland/X11 display. On Linux without a usable native display, the worker starts and owns an isolated Xvfb server and records its display and PID; it cleans up that server after the batch. Xvfb must be installed or provisioned on the host. Native rendering and software-rendered fallback are recorded separately, so benchmark results retain their execution context.

两条测试工作流最多同时运行两个 Godot 进程；可用内存低于 3500 MiB 时自动限制为一个，避免渲染进程争抢内存而污染帧率、快检时间甚至触发 OOM。`workers:1` 可主动收紧；结果中记录实际资源策略。需要精确帧时间时应停止其他重负载任务，在目标硬件上单独采集。

卧室与厨房快检读取固定快照，执行入口占位、角色间距、可达路径、`NavigationAgent3D` 与原相机到证物的物理射线；**整个目标房间快检实际耗时必须小于 5 秒**，失败即阻塞，而不是按内部某一子函数耗时掩盖超时。卧室 7 个目标和厨房 7 个证物必须完整、唯一；除卧室出口门之外必须有实际适用的证物射线。缺少目标、重复目标、缺少原物或射线、活动过门快照，以及尚未适配的普通房间均不会因空列表或 `not_applicable` 而放行。导航服务器异步发布时，检查实际空闲格投影及区域所有权，不能只看地图旧迭代计数；有界等待仍未就绪则记为 blocked，等待时间计入 5 秒。厨房按生产 `InteractionApproach` 的实际路径和 `ok/reason` 记录；计划拒绝后返回的起点只是 fallback，导航到该点不能标为到达证物，强制视觉射线也不是已完成的互动。

如需隔离厨房互动入口，可运行下列单项：暂停快照中的时间、核查活动守卫，再对现有目标处理器直接调用一次并记录其立即决策。它**不模拟屏幕鼠标点击、不推进完整动画、不采集正式轨迹**；入口、计划或处理器拒绝时返回 `blocked`，不会放行慢环。

```bash
.runtime/python/bin/python mcp/evaluation/client.py evaluation_start \
  --arguments '{"profile":"kitchen_click","snapshot_path":"<项目内厨房快照>","interaction_id":"e_b_seal"}'
```

走廊使用独立 `CorridorStage` 和自己的移动控制器，底层仍保留但隐藏的 R05 卧室网格不适用。走廊专属探针按生产控制器固定步长模拟各目标的移动、角色间距与边界，另以当前可见静态网格的**保守 AABB 代理**及真实 NPC 站位构造独立测试导航网格，分别记录 `NavigationAgent3D` 和服务器的路径与净距。AABB 代理可能高估阻碍，不是原生物理碰撞体，独立导航也不代表生产控制器采用了该路径。

走廊射线探针使用原跟随 Camera3D、当前场景中可唯一识别的原物件和按原网格/蒙皮生成的测试专用不可见三角碰撞代理；原 stage 本身没有这些碰撞体。它不是微距拍摄、画面可辨性或生产物理证明，盆栽只以盆体代表，不足以证明叶子与土面细节。无法唯一识别西端门或厨房开口的原物件时记为未覆盖，快照起点射线也未覆盖。即使部分射线通过，房间仍返回 `blocked`；总耗时仍须小于 5 秒。较早用 R05 网格测走廊的失败仅是测试适配错误，不能推断游戏走廊有问题。

合成几何回归入口分别为 `godot --headless --path . --fixed-fps 60 --script res://tools/test/corridor_navigation_unit.gd` 与 `res://tools/test/corridor_ray_unit.gd`：它们验证导航、遮挡与拒绝歧义，不是原走廊结果或验收。单独复测真实走廊快照：

```bash
.runtime/python/bin/python mcp/evaluation/client.py evaluation_start \
  --arguments '{"profile":"room_fast","snapshot_path":"<项目内快照路径>"}'
```

任意时刻的开发场景可由项目内 YAML/JSON 描述 `scene`、`room`、`time` 与 `mock`，例如 `assets/data/test_scenarios/kitchen.yaml`；验证失败直接中止，不回退到其他工程：

```bash
.runtime/python/bin/python mcp/evaluation/client.py evaluation_start \
  --arguments '{"profile":"scenario","scenario_path":"assets/data/test_scenarios/kitchen.yaml","rendered":true}'
```

快照、Mock、人工加速及设备信息均进入 YAML。`evaluation_gate` 仅判断快环结果、源码未变和当前版本已干净提交等**慢环前置条件**；它不会替代独立评审或自动宣称验收通过。现有项目的 `mcp/review/README.md` 说明如何由独立 Terra 从标题新局采集并提交含七项原因的正式评分。

## 实时汇报与节流

1. 测试开始、结束时原子追加进度 YAML，同时刷新 `artifacts/review/live-progress.js`；已打开报告每 5 秒读取一次。普通事件不重扫所有文件。
2. `progress_append` 可记录其他工作，参数与 `mcp/review/README.md` 一致。每项工作的完成确认须引用同一工作全部 change/check 事件 ID。
3. 房间/章节闭环或停机时调用 `render_report`，批量生成 `artifacts/review/index.html`、`评分总览.md`，并检查 HTML 和 Markdown 的本地链接。导出时按不可变进度账本的 SHA-256 审计历史证据；丢失、内容变化或缺少哈希的证据会保留原路径与记录哈希、显示警告，不生成失效链接，也不进入开发图片轨迹。清单写入 `artifacts/review/evidence-audit.json`；只要历史证据不完整，总体验收保持未通过。跨主机的既有历史开发图会保留并标注「原 PID 不可复核」，不会进入正式验收。
4. 实时增量事件中的证据先显示为「待批量核验」的纯文本；下次导出确认存在且哈希一致后才显示链接，避免为了实时刷新扫描所有历史文件。可启动项目内报告服务查看自动更新；如果只是离线查看，请打开 `examples/` 内的自包含 HTML。浏览器/系统隔离可能限制 `file://` 脚本刷新，此时使用本地报告服务。

`evaluation_cancel` 先核验实际 worker PID、启动时间、命令及工程目录，再发送取消请求；worker 只关闭自己启动的进程。每批从 `goal.md` 解析**既有、含时区的起止时间**，与 `.runtime/evaluation/active-goal.json` 中已记录的更早截止取最严格值，缺失或非法则拒绝启动；不会从服务首次启动时重新计算八小时。上一 Goal 于 **2026-11-16 10:51:07 UTC** 结束；用户明确授权的新 Goal 截止 **2026-11-16 19:14:33 UTC（2026-11-17 03:14:33 +08:00）**，过渡凭证保存在 `artifacts/evaluation/renewal-20261116/`。截止后拒绝新批次并停止当前测试；最终导出与版本提交须由操作者核对。不得通过删除预算记录、重启进程或修改本轮时间绕过截止；未来新任务须由用户明确建立新 Goal。

## 验收与音频限制

房间快检不证明动作、音效、美学、剧情替代或全章顺畅。独立 Terra 全程录制、原始盲测观察、七项评分原因及参考图对照均未提供时，结果必须显示“待评”。采集使用现有监控的 15 秒音频环形缓冲与后台 PCM/FFmpeg 处理；只有音频完整、无丢帧且真实有信号时才能评价 LUFS/真峰值。数字信号没有校准声压参考时 dBA 记为不可用。冷启动/换房 1.5 秒单独记录，不豁免稳态 33.3 ms 红线。

## 全天分场景并发测试

通过本项目 MCP 的 `evaluation_start` 调用 `{"profile":"scene_survey","rendered":true,"workers":3,"max_seconds":1800}`。此配置从 `assets/data/test_scenarios/mainline_survey.json` 为每个场景创建独立任务，最多同时运行三个 Godot 进程，每个进程使用 `--max-fps 60`，并分别保存画面、回执、输出、并发观测及失败详情。单场景最长运行 150 秒；超时或其他错误记入该场景结果，其他场景继续执行。状态文件和 `report.yaml` 按场景列出房间、阶段、具体动作与未完成项，七维暂缺数据保留空值。

由并行负载采得的帧时间携带并发上下文，供该次场景测试解释；单实例基准可另行采集。场景通过快照或预设状态切入，连续玩家通关进度由实际游玩记录呈现。
