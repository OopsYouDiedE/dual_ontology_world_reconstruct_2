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

## 生图调用与资产来源（2026-11-18）

同一组案卷与走廊实机截图分别交给 `gpt-image-2.5` 和 `gpt-image-2.6-sunburst` 编辑，两组都成功返回。2.6 使用 `quality=high`，结果各为 1586 × 992。案卷采纳了皮革棕索引、铜金选中标记、浅色纸面和右上角关闭按钮；从 2.6 案卷输出裁出一块无字纸面，作为正式资源 `assets/textures/case_file/vellum.webp`。证物下拉框、阅读区和关闭入口均由 Godot 控件渲染。角色图用于对照暖光下的明暗过渡；实装在 `FigurinePaint.gdshaderinc` 中扩展漫反射过渡，并给受光表面加极轻的掠射光泽，沿用原角色贴图。

本机配置的供应商在 `codex exec --model gpt-image-2.5` 走 `/v1/responses` 时返回 HTTP 503，并提示该图像模型支持 `/v1/images/generations` 和 `/v1/images/edits`。基于截图复现时，使用 imagegen 技能自带的脚本直接调用编辑端点：

```text
python image_gen.py edit --model gpt-image-2.6-sunburst --image <游戏截图> --quality high --size 1536x1024 --no-augment --out <输出PNG>
```

运行进程从本机配置映射 `OPENAI_BASE_URL` 与 `OPENAI_API_KEY`。2.5 复测沿用同一命令，仅替换 `--model`。本地比较图保存在 `artifacts/review/ui-material-development/`：`case-file-art-direction.png`、`character-art-direction.png` 为 2.5，`case-file-sunburst.png`、`character-sunburst.png` 为 2.6。

## 开发检查
- 2.6 实装在 Godot 4.7.2 .NET 中复查：走廊四名角色的 Forward+ 定点图为 `artifacts/review/focused/runs/04e476a066010177/frames/step-0001-00.png`；在二楼交叉口检查了 Evidence 正文、已完成的 Deductions、右上角 × 和取消操作。案卷实机图为 `case-file-sunburst-runtime.png`、`deductions-sunburst-runtime.png`，与上述比较图同目录。 游戏 MCP 的 `interaction / corridor-characters` 用于走廊的 Forward+ 前后对照。
- 既有 `2F-cross-M` 项目检查点可用来检查已收集证物和已完成推演。视觉实测入口为左下 `Case File`。
- `tools/test/exploration_ui_contract.gd` 另覆盖空态、条目切换、选择保留和调试页隐藏，运行时传入 `.runtime/checkpoints/fixtures/opening-free.json` 或同等自由探索检查点。
- 2.6 实装在 Godot 4.7.2 .NET 中复查：走廊四名角色的 Forward+ 定点图为 `artifacts/review/focused/runs/04e476a066010177/frames/step-0001-00.png`；在二楼交叉口检查了 Evidence 正文、已完成的 Deductions、右上角 × 和取消操作。案卷实机图为 `case-file-sunburst-runtime.png`、`deductions-sunburst-runtime.png`，与上述比较图同目录。 2.6 实装在 Godot 4.7.2 .NET 中复查：走廊四名角色的 Forward+ 定点图为 rtifacts/review/focused/runs/04e476a066010177/frames/step-0001-00.png；在二楼交叉口检查了 Evidence 正文、已完成的 Deductions、右上角 × 和取消操作。案卷实机图为 case-file-sunburst-runtime.png、deductions-sunburst-runtime.png，与上述比较图同目录。
- 探索 UI 契约 62 项通过；剧情契约的 31 个夹具、45 个节拍无失败。以上为开发检查。
