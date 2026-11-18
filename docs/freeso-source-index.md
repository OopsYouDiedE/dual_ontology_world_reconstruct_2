# FreeSO 固定版本源码索引

版本：`4c6b3e8f5835b228723caea3c9f683c62f244f73`。索引来源是该提交的递归 Git tree（共 **6145** 条，`truncated=false`，其中 blob **5466** 个）。这是全仓路径盘点：下方的源码入口用于阅读、复现和记录差异。逐项行为的迁移进度、验收版本与证据见 [机制迁移清单](freeso-mechanism-migration.md)。

## 从源码入口到项目验收

| 工作组 | 固定版本中的入口（除注明外，以 `TSOClient/` 为根） | 项目后续验收 |
| --- | --- | --- |
| 建造界面与命令 | `tso.client/UI/Panels/UIBuildMode.cs`、`UIBuyMode.cs`；`tso.simantics/Model/VMArchitectureCommand.cs`；`NetPlay/Model/Commands/VMNetArchitectureCmd.cs` | 建造器保留预览、拒绝、提交、撤销和保存；逐项覆盖移动、复制、旋转、删除和批处理。 |
| 地块、墙地与房间 | `tso.simantics/VMArchitecture.cs`、`Model/VMRoomMap.cs`、`Model/VMArchitectureTerrain.cs`、`Utils/VMArchitectureTools.cs`；`VMNetChangeLotSizeCmd.cs`、`VMNetSetRoofCmd.cs` | 验证承载、室内外、地形、屋顶、跨层开口、地块扩张与边界，记录与本项目非正交几何的差异。 |
| 路由和动态占用 | `tso.simantics/Engine/VMRoutingFrame.cs`、`VMRouteFinder.cs`、`Engine/Routing/`、`Model/Routing/` | 真实房间跨门、楼梯绕行、动态家具、相向会车、占位回收与路径恢复。 |
| 放置、手持和容器 | `tso.simantics/Entities/VMEntity.cs`、`Engine/VMSlotParser.cs`、`Primitives/VMFindLocationFor.cs`、`VMDropOnto.cs`、`VMGrab.cs`、`VMSnap.cs` | 将空间承载、站位槽和容器持有关系分开验证，检查表面物件随父物件移动、回滚和旧档。 |
| 动机与自主 | `tso.simantics/Primitives/VMFindBestAction.cs`、`VMFindBestObjectForFunction.cs`、`VMSetMotiveChange.cs`；`Model/VMMotive.cs`、`Model/VMMotiveChange.cs` | 按对象和角色产生候选，校验可达成本、需求变化、技能／环境影响和固定种子重放。 |
| 行为、动画、对话及音频 | `tso.simantics/Engine/VMThread.cs`、`VMScheduler.cs`、`VMQueuedAction.cs`、`VMStackFrame.cs`；`Primitives/VMAnimateSim.cs`、`VMPlaySound.cs`、`VMDialog*`；`tso.sound/`、`tso.vitaboy.engine/` | 按开始、接触、效果、结束记录时序；验证队列、打断、错误处理、皮肤／衣装、声音与字幕，保留原剧情动作。 |
| 关系、人物与可见状态 | `tso.simantics/Primitives/VMRelationship.cs`、`VMTestSimInteractingWith.cs`；`Model/VMPersonDataVariable.cs`、`Model/TSOPlatform/VMTSOAvatarState.cs` | 双向关系、拒绝、邀请、信任、长期趋势、技能锁、感知和存档往返。 |
| 经济、库存及权限 | `tso.simantics/Primitives/VMTransferFunds.cs`、`VMInventoryOperations.cs`；`NetPlay/Model/Commands/` 的买卖、转移、锁与权限命令；`FSO.Server/Servers/Lot/Domain/LotServerGlobalLink.cs` | 物品与资金守恒、权限拒绝、地块共享、原子提交、重复投递和回滚。 |
| 城市、地块服务器和会话 | `FSO.Server/Servers/City/`、`FSO.Server/Servers/Lot/`、`FSO.Server.Database/`；`tso.simantics/NetPlay/Drivers/`、`NetPlay/Model/` | 授权加入、主机权威帧、重同步、暂停/断线重连、地块存档、社交消息和状态恢复。 |
| 物件插件和工作 | `tso.simantics/NetPlay/EODs/Handlers/`；`Primitives/VMInvokePlugin.cs`、`VMOnlineJobsCall.cs` | 逐插件独立记录进入条件、双方事件、进行中状态、奖励与退出；禁止把插件分组视作验收通过。 |
| 资源格式、渲染、工具链 | `tso.files/`、`tso.content/`、`tso.world/`、`tso.vitaboy.model/`、`FSO.IDE/`、`FSO.SimAntics.JIT*/` | 分开登记格式兼容、可见效果和开发工作流；核对替换所需的资源权属和本地发布依赖。 |

## 可执行行为入口（路径清单）

以下清单由固定提交的目录结构生成。名称只用于逐项搜索，机制语义、可达性和边界仍须查看实现与调用点。

### SimAntics primitives（54）

`VMAnimateSim`, `VMBreakPoint`, `VMBurn`, `VMChangeSuitOrAccessory`, `VMCreateObjectInstance`, `VMDialogGlobalStrings`, `VMDialogPrivateStrings`, `VMDialogSemiGlobalStrings`, `VMDrop`, `VMDropOnto`, `VMExpression`, `VMFindBestAction`, `VMFindBestObjectForFunction`, `VMFindLocationFor`, `VMGenericTS1Call`, `VMGenericTSOCall`, `VMGetDirectionTo`, `VMGetDistanceTo`, `VMGetTerrainInfo`, `VMGosubFoundAction`, `VMGotoRelativePosition`, `VMGotoRoutingSlot`, `VMGrab`, `VMIdleForInput`, `VMInventoryOperations`, `VMInvokePlugin`, `VMLookTowards`, `VMNotifyOutOfIdle`, `VMOnlineJobsCall`, `VMPlaySound`, `VMPushInteraction`, `VMRandomNumber`, `VMReach`, `VMRefresh`, `VMRelationship`, `VMRemoveObjectInstance`, `VMRunFunctionalTree`, `VMRunTreeByName`, `VMSetBalloonHeadline`, `VMSetMotiveChange`, `VMSetToNext`, `VMShowString`, `VMSleep`, `VMSnap`, `VMSpecialEffect`, `VMStopAllSounds`, `VMSubRoutine`, `VMSysLog`, `VMTS1Budget`, `VMTS1InventoryOperations`, `VMTS1MakeNewCharacter`, `VMTestObjectType`, `VMTestSimInteractingWith`, `VMTransferFunds`.

### 地块与会话命令（49）

`VMBlueprintRestoreCmd`, `VMChangePermissionsCmd`, `VMGenericDialogCommand`, `VMNetAdjHollowSyncCmd`, `VMNetArchitectureCmd`, `VMNetAsyncPriceCmd`, `VMNetAsyncResponseCmd`, `VMNetAsyncSaleCmd`, `VMNetBatchGraphicCmd`, `VMNetBuyObjectCmd`, `VMNetChangeControlCmd`, `VMNetChangeEnvironmentCmd`, `VMNetChangeLotSizeCmd`, `VMNetChatCmd`, `VMNetChatEditChanCmd`, `VMNetChatParamCmd`, `VMNetCheatCmd`, `VMNetDeleteObjectCmd`, `VMNetDialogResponseCmd`, `VMNetDirectControlCommand`, `VMNetDirectControlToggleCmd`, `VMNetEODEventCmd`, `VMNetEODMessageCmd`, `VMNetGotoCmd`, `VMNetInteractionCancelCmd`, `VMNetInteractionCmd`, `VMNetInteractionResultCmd`, `VMNetLockCmd`, `VMNetMoveObjectCmd`, `VMNetPingCmd`, `VMNetPlaceInventoryCmd`, `VMNetSM64AnimDataCmd`, `VMNetSM64EventCmd`, `VMNetSM64PositionCmd`, `VMNetSendToInventoryCmd`, `VMNetSetIgnoreCmd`, `VMNetSetOutfitCmd`, `VMNetSetRoofCmd`, `VMNetSetTimeCmd`, `VMNetSimJoinCmd`, `VMNetSimLeaveCmd`, `VMNetSkillLockCmd`, `VMNetTimeoutNotifyCmd`, `VMNetTuningCmd`, `VMNetUpdateInventoryCmd`, `VMNetUpdatePersistStateCmd`, `VMNetUpgradeCmd`, `VMRequestResyncCmd`, `VMStateSyncCmd`.

### 物件插件处理器（33）

`VMAbstractEODRackPlugin`, `VMEODAbstractGameshowBuzzerPlugin`, `VMEODBandPlugin`, `VMEODBlackjackPlugin`, `VMEODBulletinPlugin`, `VMEODCooldownEventPlugin`, `VMEODDJStationPlugin`, `VMEODDanceFloorPlugin`, `VMEODDancePlatformPlugin`, `VMEODDresserPlugin`, `VMEODFNewspaperPlugin`, `VMEODGameCompDrawACardPlugin`, `VMEODGameshowBuzzerHostPlugin`, `VMEODGameshowBuzzerPlayerPlugin`, `VMEODHoldEmCasinoPlugin`, `VMEODNCDanceFloorPlugin`, `VMEODNightclubControllerPlugin`, `VMEODPaperChasePlugin`, `VMEODPermissionDoorPlugin`, `VMEODPizzaMakerPlugin`, `VMEODPropertySelectPlugin`, `VMEODRackOwnerPlugin`, `VMEODRackPlugin`, `VMEODRoulettePlugin`, `VMEODScoreboardPlugin`, `VMEODSecureTradePlugin`, `VMEODSignsPlugin`, `VMEODSlotsPlugin`, `VMEODStubPlugin`, `VMEODTimerPlugin`, `VMEODTrunkPlugin`, `VMEODTwoPersonJobObjectMazePlugin`, `VMEODWarGamePlugin`.

## 全仓目录与文件组

计数包含相应目录下的源码、项目文件、数据和第三方内容；用来确认索引范围。

| 目录或文件组 | Blob 数 |
| --- | ---: |
| `(root)` | 6 |
| `Charvatia` | 10 |
| `Documentation` | 33 |
| `FSOInstaller` | 33 |
| `Other` | 1078 |
| `TSOClient` | 4 |
| `TSOClient/FSO.Common.DatabaseService` | 17 |
| `TSOClient/FSO.Common.Domain` | 15 |
| `TSOClient/FSO.Content.TSO` | 1388 |
| `TSOClient/FSO.IDE` | 295 |
| `TSOClient/FSO.Patcher` | 17 |
| `TSOClient/FSO.Server` | 204 |
| `TSOClient/FSO.Server.Api.Core` | 50 |
| `TSOClient/FSO.Server.Clients` | 11 |
| `TSOClient/FSO.Server.Common` | 22 |
| `TSOClient/FSO.Server.Core` | 7 |
| `TSOClient/FSO.Server.DataService` | 44 |
| `TSOClient/FSO.Server.Database` | 171 |
| `TSOClient/FSO.Server.Debug` | 38 |
| `TSOClient/FSO.Server.Domain` | 6 |
| `TSOClient/FSO.Server.Framework` | 3 |
| `TSOClient/FSO.Server.Protocol` | 129 |
| `TSOClient/FSO.Server.Updater` | 8 |
| `TSOClient/FSO.SimAntics.JIT` | 29 |
| `TSOClient/FSO.SimAntics.JIT.Roslyn` | 6 |
| `TSOClient/FSO.UI` | 109 |
| `TSOClient/FSO.Windows` | 13 |
| `TSOClient/FSO.iOS` | 131 |
| `TSOClient/FSODroid` | 52 |
| `TSOClient/FSOFacadeWorker` | 8 |
| `TSOClient/MigrationBackup` | 3 |
| `TSOClient/System.Drawing` | 3 |
| `TSOClient/tso.client` | 386 |
| `TSOClient/tso.common` | 125 |
| `TSOClient/tso.content` | 417 |
| `TSOClient/tso.debug` | 45 |
| `TSOClient/tso.files` | 100 |
| `TSOClient/tso.simantics` | 306 |
| `TSOClient/tso.sound` | 11 |
| `TSOClient/tso.vitaboy.engine` | 8 |
| `TSOClient/tso.vitaboy.model` | 22 |
| `TSOClient/tso.world` | 103 |
