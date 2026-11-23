# FreeSO 全仓源码分析

**分析基线：** `riperiperi/FreeSO`，提交 `4c6b3e8f5835b228723caea3c9f683c62f244f73`（2025-08-22），与本项目 `vendor/FreeSO` 的 gitlink 一致。该树有 5,466 个跟踪文件、2 个依赖 gitlink、2,378 个 C# 文件（含生成代码与旧工具）。本文先按全树梳理模块，再深读关键链路；结论来自静态源码，未启动客户端或部署服务器。源码定位默认以该提交的 `TSOClient/` 为基准，最后有复核命令。

## 1. 运行时总图

FreeSO 以 MonoGame 重做《The Sims Online》的运行环境。它用 C# 实现引擎、编辑器和服务端；原版对象行为、动画、服装和界面等仍依赖游戏数据。地块运行时的核心是 **SimAntics VM + 可挂接的网络驱动 + 可选的地块视觉表现**。本地沙盒用本进程的服务器驱动，线上地块服务器运行无视觉端的同一 VM，联机客户端执行服务器发来的 tick。游戏逻辑因此能跨这三种宿主共用。

```text
原版数据 / FreeSO 补丁 → Files 解码 → Content 索引与资源装配
                                         ↓
客户端界面 → 地块命令 → VM 驱动 → SimAntics（实体、建筑、时钟、行为栈）
                           ↕       ├─→ VMMarshal → 地块存档 / 状态同步
                    地块网络 tick  └─→ LotView Blueprint → 2D / 3D 绘制
                           ↑
                     LotServer（无图形 VM）← CityServer（进场、分配）
```

### 全仓模块地图

| 位置 | 职责及阅读入口 |
|---|---|
| `FSO.Windows`、`FSODroid`、`FSO.iOS` | 平台启动及宿主适配。Windows 从 `Program.Main` 进入 `FSOProgram.InitWithArguments`，再由 `GameStartProxy.Start` 创建并运行 `TSOGame`。移动目录是固定提交中的平台工程，构建情况未验证。 |
| `tso.client`、`FSO.UI`、`tso.common` | 游戏与界面层；前者含登录、城市界面、地块操作及沙盒，`FSO.UI` 提供可共享控件与绘制基础，`tso.common` 含位流、渲染框架、环境与共享类型。`TSOGame` 初始化内容服务、HIT、场景及 UI 层。 |
| `tso.files`、`tso.content`、`FSO.Content.TSO` | 二进制格式读取、内容 Provider 与资源索引、TSO 侧内容包。对象包常用 IFF/FAR，`WorldObjectProvider` 对 `objiff.far` 实际使用 `FAR1Provider<IffFile>`，并组合精灵、调参和补丁。 |
| `tso.simantics` | 303 个 C# 文件。`Engine` 调度与行为解释，`Entities` 管对象和人物，`Primitives` 实现原语，`Marshals` 做状态编码，`NetPlay` 定义地块命令和驱动；建筑与整局状态在 `VMArchitecture`、`VMContext`、`VM`。EOD 插件也走模拟及客户端消息层。 |
| `FSO.SimAntics.JIT`、`FSO.SimAntics.JIT.Roslyn` | BHAV 翻译和编译路径；Roslyn 工程含 `VMRoslynTranslator`、`VMRoslynRoutine`。阅读行为语义先从解释器走，编译路径单独核对构建和启用方式。 |
| `tso.world`（`FSO.LotView`）、`tso.vitaboy.model`、`tso.vitaboy.engine`、`tso.sound` | 地块、相机、光照、物件绘制；人物骨骼、服装及动画数据和运行层；声音侧由 `HITVM`、`HITInterpreter`、`HITThread` 及环境声组件工作。 |
| `FSO.Server`、`FSO.Server.Protocol`、`FSO.Server.Clients` | City/Lot/API/Tasks 宿主、会话处理与消息包。协议工程分 Voltron、Gluon 等包族；地块 SimAntics 命令另在 `tso.simantics/NetPlay` 定义。 |
| `FSO.Server.{Database,DataService,Common,Domain,Core,Framework}`、`FSO.Common.{DatabaseService,Domain}` | SQL 访问和模型、数据服务的同步与类型、共用领域与基础设施；读数据结构从 `FSO.Server.Database/DA` 开始，运行时接线看 `FSO.Server/Servers`。 |
| `FSO.Server.Api.Core`、`FSO.Server.Debug`、`FSO.Server.Updater` | 独立 ASP.NET Core API 工程、服务器调试工具及更新监护；`FSO.Server` 内也有 API/UserApi 路径，按宿主区分入口。 |
| `FSO.IDE`、`tso.debug`、`FSOFacadeWorker` | Volcanic 对象/资源/BHAV 编辑及运行时检查；旧调试界面；另有地块外观生成 worker，相关渲染入口是 `tso.world/Facade/LotFacadeGenerator.cs`。 |
| 根级 `Charvatia/`、`FSOInstaller/`、`Other/`、`Documentation/` | 独立沙盒宿主工程、安装器，第三方库与历史工具（FAR/IFF 提取、城市渲染、网格预览及音频转换），以及上游构建、数据库和运维说明。客户端补丁器另在 `FSO.Patcher`。 |

## 2. 行为：资源驱动、实体队列与离散时钟

1. **对象内容**：`tso.content/WorldObjectProvider.cs` 的 `GameObjectResource` 组合对象 IFF、精灵与调参；`tso.files/Formats/IFF/Chunks` 的 `OBJD` 是对象定义，`BHAV` 是行为指令图，`TTAB` 提供交互表及动机广告，`SLOT` 提供坐标与路由槽。`DGRP` 和 `SPR2` 管图层组合及带深度的精灵数据。实际的互动行为要联合阅读 C# 原语和对象 BHAV。
2. **交互进入 VM**：手动菜单入口 `tso.client/UI/Panels/UIPieMenu.cs` 发送 `VMNetInteractionCmd`；命令通过后从目标取得互动并入调用人物的队列。`VMThread` 的 *thread* 是实体逻辑执行状态；`VMScheduler` 统一驱动它。队列中的一次互动由 `VMQueuedAction` 描述，正在执行的脚本由 `VMStackFrame` 描述，二者可同时存在并有独立的存档数据。`Engine/Translator/VMRoutine.cs` 执行当前指令，`VMThread` 处理跳转、返回和子例程调用；子例程按编号区间解析到对象私有、共享或全局资源。
3. **时钟和调度**：`VM.Update` 将客户端更新步转换为以 30Hz 为基准的 VM tick 预算；`VM.Tick` 调用驱动，驱动处理逻辑 tick 后进入 `VM.InternalTick`。后者更新 VM 时间、建筑派生数据与对象调度。显示层有单独的插值与绘制步，所以按真实 VM tick 读数据比按渲染帧读更有意义。
4. **自主行为**：`Primitives/VMFindBestAction.cs:92` 从自治对象索引取候选，检查交互能否运行，按需求、个性和距离等因素评分，从高分候选中使用 VM 随机数按分数加权抽取，最后加入人物行动队列。决定何时进入这一逻辑的是原版脚本。脚本调用入队和自主挑选最终汇入同一个执行入口，因此记录自主选择应在 `VMFindBestAction` 成功入队处收集证据。
5. **路由**：`Engine/VMRoutingFrame.cs` 字面上就是行为栈里的路由帧。多房间路径先在门户图上做 A*，沿途执行门户行为；同房间再寻找目标槽位、绕开障碍并完成朝向。门户失败能触发替代路线。这里的“移动”是与对象和脚本交互的一段过程，可借鉴成 Godot 的“房间拓扑 → 门槛行为 → 室内导航 → 槽位对齐”。

## 3. 建造和显示：一份逻辑建筑，多种表示

`UIWallPlacer`、`UIFloorPainter` 等生成建筑命令。`VMArchitecture.SimulateCommands(commands, true)` 走可视预览路径；命令提交后通过 `VMNetArchitectureCmd` 和 `IVMTSOGlobalLink` 的建筑处理，再应用到正式墙、地面和地形。`VMArchitecture.Tick` 消费脏状态，`RegenRoomMap` 按楼层墙与地面重建 room map；`VMContext` 把房间同实体、窗/门 portal、静态与动态障碍和照明关联。线上 `LotServerGlobalLink.Tick` 先模拟价格，再执行交易，把通过的命令送回 VM；`VMNetBuyObjectCmd` 同样把付费、地块摆放和持久 ID 分开。窗户是建筑对象：`Entities/VMGameObject.cs` 根据对象标记、朝向和墙样式更新相邻墙段。

`LotView.Model.Blueprint` 是显示侧共享数据结构。`World` 按模式挂载 `WorldPlatform2D` 或 `WorldPlatform3D`，处理墙缓存、屏幕拾取、缩略图等：

- **等角模式**：`Components/WallComponent.cs` 绘制墙片，`Utils/DGRPRenderer.cs` 组合对象 sprite，`_2DWorldBatch` 处理批绘。层、旋转、墙切面和深度共同决定屏幕可见结果。
- **3D 模式**：`RC/WallComponentRC.cs` 等生成建筑几何，`tso.content/RCMeshProvider.cs` 与 `tso.files/RC/DGRP3DMesh.cs` 负责对象重建和缓存路径；一般对象可利用原精灵深度重建，也支持替换网格。人物另走 Vitaboy 骨骼与动画。
- **三种同名“蓝图”要按类型区分**：`XmlHouse` 是加载／交换用的建筑与初始对象数据；`LotView.Model.Blueprint` 是运行中渲染状态；`.fsov` 是可以用于恢复 VM 的快照。给 Godot 导入建筑布局优先用第一种，导入运行中人物的位置与行动用第三种或 live bridge。

## 4. 联机、权威 tick 和存档

- **本地**：`SandboxGameScreen.InitializeLot` 建立 `World`、`VMContext` 和 `VM`。普通本地沙盒用 `VMServerDriver` 加 `VMTSOGlobalLinkStub`；另有远端连接和录制回放分支。因此沙盒也能走地块命令路径。
- **联机**：`CoreGameScreen.InitializeLot` 挂 `VMClientDriver`。`CityServer` 管城市会话，`LotAllocations.TryFindOrOpen` 负责查找或分配地块，`LotHost` 管理地块宿主和会话路由；`LotContainer` 在地块线程建 `VMContext(null)` 并驱动权威 VM。客户端提交命令，`VMServerDriver.Tick` 校验后给一批命令分配 tick 和 VM 随机种子、在服务端执行并广播；`VMClientDriver` 缓冲并执行权威 tick，`VMNetDriver.InternalTick` 发现随机种子错位时可请求 resync。协议是“命令流 + 状态同步”，相比逐帧实体坐标广播，需要双方维持相同的执行语义、内容和随机数使用顺序；随机种子检查只覆盖一种可观察的分歧信号。
- **社会与经济**：`LotServerGlobalLink` 承接交易、室友、库存、服装和插件持久化等服务；物件发起的交互式面板可由 `VMEODHost` 连到一个 EOD 会话，再以 `VMNetEODMessageCmd` 等消息协调客户端界面及 VM 端逻辑。`ToolRunServer` 接线运维宿主，`TaskEngine` 执行配置中的后台任务。
- **持久化**：`VM.Save` 生成 `VMMarshal`，固定提交的写入版本为 `38`，格式以 `FSOv` 开头，支持 GZip 负载；主体是 context、人物/对象、行为线程、多格分组、全局状态、TS1/TSO 平台状态与调参。`VM.Load` 重新建立运行对象、关系和派生状态。`VMHollowMarshal` 为地块外观等提供精简状态，服务端 `LotContainer` 保存完整及 hollow 文件，用数据库中的 ring 索引追踪保存代际；帐号、关系、库存等持久数据另有数据库模型。客户端记录流（如 `.fsor`）另走 `VMFSORDriver` 和 tick 流。
- **可维护性**：地块模拟、城市分配、外部服务通过驱动/GlobalLink 分开，后台服务的结果可以回到 VM 命令流。主要移植成本来自 VM 工程对内容格式、图形数学类型和 LotView 的编译引用，以及旧版依赖与内容版本。无图服务器路径可证明运行时分层；要在现代 .NET 进程中嵌入，仍需逐项解开这些编译依赖。该提交的经典服务器工程目标是 .NET Framework 4.5；`FSO.Server.Api.Core` 则是 `netcoreapp2.2`。

## 5. 与本项目桥接的关系

- [`tools/freeso/freeso.ps1`](../../tools/freeso/freeso.ps1) 从固定树构建隔离副本，启动原版客户端。它可传入学院 XML 蓝图路径；这是布局输入。实时出口由 [`install-hook.ps1`](../../tools/freeso_bridge/install-hook.ps1) 在沙盒更新前后观察 tick，[`LiveTickHook.cs`](../../tools/freeso_bridge/LiveTickHook.cs) 在推进后的原生 VM 线程上采样，按房间绑定输出并限频。[`SnapshotBridge.cs`](../../tools/freeso_bridge/SnapshotBridge.cs) 同时服务离线 `.fsov` 和实时投影。
- [`LotSnapshot.gd`](../../tools/freeso_bridge/LotSnapshot.gd) 定义 JSON 契约和坐标变换；[`FreeSoSnapshot.gd`](../../scenes/rogue_view/FreeSoSnapshot.gd) 将每层的墙位掩码、地板、摆件和人物位置适配成 Rogue 房间视图。当前消费端按可见/摆放/包含关系过滤并合并多格物件，用少量 GUID 推断窗口；这些是显示适配语义。门的原生通行行为、角色骨骼、导航和完整建筑视觉仍由各宿主自己的系统提供。
- 推荐沿三层逐步深化：**地块几何**继续用 FreeSO 数据验证门窗、斜墙、半砖和多层转换；**行为观察**保留 `tick`、VM-local `object_id`、持久角色 ID、active action 与槽位/目的对象在诊断视图中做关联；**本作行为**保留营地自研决策和队长出征指挥，复用 FreeSO 的“候选生成 → 资格检查 → 行为队列 → 门户与槽位执行”结构。若要由 Godot 控制 FreeSO 动作，单独设计由原生驱动执行的命令通道，与快照读端分开。
- 验证优先级：稳定样例覆盖斜墙、窗门、楼层、容器和多格组；真实互动覆盖手动指令与原生自主入队，并以 tick/房间/PID 排除旧快照。计划涉及分发原版资产或修改后的上游源码时，先分清上游 MPL-2.0 文件、其依赖以及 EA 游戏数据的来源。

## 6. 源码复核

从本仓库根目录执行。子模块的固定 Git 对象用于追踪上游路径，即使当前检出只保留一部分工作树；首次读取尚缺的 blob 可能需要网络。

```powershell
$rev = '4c6b3e8f5835b228723caea3c9f683c62f244f73'
git -C vendor/FreeSO ls-tree -r --name-only $rev
git -C vendor/FreeSO show "${rev}:TSOClient/tso.simantics/VM.cs"
git -C vendor/FreeSO show "${rev}:TSOClient/tso.simantics/Primitives/VMFindBestAction.cs"
git -C vendor/FreeSO show "${rev}:TSOClient/FSO.Server/Servers/Lot/Domain/LotContainer.cs"
python third_party_sources/FreeSO/verify.py
```

固定树的 gitlink 是 `Other/libs/FSOMonoGame` 和 `Other/libs/FSOMina.NET`；分析把它们当作图形与网络依赖。`.gitmodules` 另有 assimp-net 段，在该修订树中没有对应 gitlink。原版游戏数据、两个依赖的内部代码、运行时行为兼容性与生产部署分别需要独立验证。
