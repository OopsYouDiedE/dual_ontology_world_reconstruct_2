# 现场案卷与角色材质

## 调研与设计决定

| 样本 | 界面结构 | 本作采用 |
| --- | --- | --- |
| [Return of the Obra Dinn](https://obradinn.com/) | 现场调查和调查簿各有界面；从簿册索引进入具体记录，回到现场核对。 | 从房间左下角打开 `Case File`，现场继续可见。案卷左栏固定为索引，右栏展示当前记录。 |
| [The Case of the Golden Idol](https://store.steampowered.com/app/1677770/The_Case_of_the_Golden_Idol/) | 观察现场和组织推论分开，线索材料与案件判断在各自的界面中呈现。 | `Evidence`、`Deductions`、`Log` 依次供玩家查证、复核推演、回读经过。证物条目保留来源房间与知识解读状态。 |
| [Pentiment](https://news.xbox.com/en-us/2022/11/15/pentiment-available-now/) | 手抄本和木刻形成统一的视觉语言。 | 用现有书桌的深棕、铜金和衬线标题建立案卷风格；较长的阅读内容用无衬线字形。 |

`Knowledge`、`Terms`、`Relations`、`Contract` 在分隔线下方。切换页签保留当前证物；当知识变化时，重新读取既有推理引擎给出的证物解释。书桌标题、书本笔记、地图路线、推演触发和存档结构沿用现有流程。

## 材质实现

用走廊同一机位对比暖灯下的头发、浅布和深色衣物。导入角色的不透明常规表面采用哑光彩绘：保留原贴图、配色、顶点色、UV 变换和单双面设置，减弱镜面反光，让衣色和轮廓由场景光形成。透明、发光、法线贴图和多通道等特殊表面沿用导入材质。模型、骨骼及摆位保持原样。

## 开发检查

- 游戏 MCP 的 `interaction / corridor-characters` 用于走廊的 Forward+ 前后对照。
- 既有 `2F-cross-M` 项目检查点可用来检查已收集证物和已完成推演。视觉实测入口为左下 `Case File`。
- `tools/test/exploration_ui_contract.gd` 另覆盖空态、条目切换、选择保留和调试页隐藏，运行时传入 `.runtime/checkpoints/fixtures/opening-free.json` 或同等自由探索检查点。
