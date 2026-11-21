# MPFB 2.0.18 功能审阅

测试环境：2026-11-21，本机 Windows、Blender 4.2.1 LTS、MPFB 2.0.18、Rigify 0.6.12、Godot 4.7.2 .NET Forward+（RTX 3070）。沿用[侦探底模试验](mpfb2-character-test.md)，另建独立样体与审阅项目；现有游戏人物保持原样。

## 怎么用 MPFB

从 Blender 3D 视口按 `N`。先在 `MPFB` 的 `Start here` 确认资产包，再在 `New human` 建人。体型滑块和局部目标在同一套 HM08 拓扑上移动顶点，所以衣服、拓扑代理和骨架可以按对应关系重新贴合。身体比例定好后再绑定、试衣；若随后改体型，使用 `Refit`。保存角色配方方便复用，`.blend` 则保存整个当前编辑场景。发布时从 `Operations → Export copy` 创建独立导出副本，处理遮挡和辅助几何，再用 Blender 的 GLB 或 FBX 导出器。

| 功能 | 实测及使用判断 |
| --- | --- |
| **捏人、非对称细节、随机** | 已测整体身高、头高与 MPFB 2.0.18 新开放的单侧脸颊变形。用固定种子连续批量生成两组，每组 4 人，个体种子、宏观体型和位置一致。配合身高与年龄参数适合做群像起稿，命名角色仍需单人雕形。 |
| **角色与资产库** | MakeHuman `.mhm` 样例转成带形态键的 HM08；MPFB JSON 保存并恢复了体型、`game_engine` 骨架及衣、短发、眼睛、眉毛四件资产。预设记录资产引用，换机需带上同一资产包。提高手中样体的身高后，`Refit` 同步移动头骨和衣件顶点；官方测试亦覆盖代理卸下与皮肤遮挡恢复。 |
| **皮肤与材质** | 同一皮肤切换 Layered 和 Game Engine 模式。前者用于 Blender 内的分层处理；后者简化节点后随 GLB 进入 Godot。实景可见皮肤、眼、眉、衣料和网格短发，也可见短发局部露底，发布前应修发际线与材质。 |
| **骨架、试姿、动作工具** | `default` 163 骨，`game_engine` 53，`mixamo` 52，`mixamo_unity` 64，`cmu_mb` 31，`openpose` 24。另生成了 Rigify 成品控制骨架；将系统 `sit01.bvh` 作为姿势导入 `default`，162 根骨的姿态矩阵发生变化。上游另覆盖关键帧、姿势工具和 OpenPose JSON；本轮未提交 Mixamo 网站动画或接项目动作库。 |
| **脸部** | 测了 ARKit 表情加叠、清零及预设载入；加载 Meta 15 个口型和 ARKit 52 个面部通道，连同蒙皮导出到 GLB。Godot 实测 67 个形态键并在 Forward+ 驱动 `jawOpen`、`viseme_aa`。自动音频口型另需 Lip Sync；扩展站所列 Windows 版本最低要求 Blender 4.4，本机 4.2.1 只验了形态键。 |
| **头发与体毛** | 资产库网格短发可随 GLB 导入。Hair Editor 的曲线短发和前臂体毛分别成功附着，原始引导曲线 418、678 条。2.0.18 面板没有开放转发片/烘焙；直接调用实验转发片操作时，官方短发模板报 `Object does not have geometry data`。游戏头发优先用可控面数的网格或自行做发片。 |
| **自制资产** | 上游共有 203 项资产制作相关测试，覆盖 MakeClothes（贴合与权重/遮挡）、MakeTarget（形变）、MakeSkin/Makeup（皮肤和叠层）、MakeExpression、MakePose、MakeRig 与 MakeWeight。验证的是工具和文件读写；这轮未制作一套成品大衣或逐件校验社区资产。 |
| **导出** | 用 MPFB 的复制、烘焙与清理：样体主网格由 19,158 顶点变为 10,086，并保留独立衣、眼、眉、发、骨架与表情。GLB 在 Godot 里读入并显示；FBX 在干净 Blender 场景回读 5 个网格、53 骨和 67 个形态键；材质以 GLB 的 Godot 画面为验收口径。MakeHuman 实时 Socket 另需运行独立应用及其插件，本轮验证了 `.mhm` 文件路线。 |

**用于本项目：** MPFB 负责比例、不同体型试制、换装试配、初始权重和表情源数据；近景侦探继续从编辑母版做局部重拓扑、身份雕形和游戏版头发。正式接入还需将 MPFB 骨骼与项目动画/挂点契约对齐，并收敛到 5,000 三角面的身体预算。项目当前的角色资源未改动。

## 测试记录

- 源码标签 `v2.0.18` 上游全套：**1,134 项，初跑 1,133 通过、1 失败、0 跳过**。失败是 `makeexpression::test_load_operator_via_user_data` 的 Windows 枚举路径比较：测试 profile 根路径混入了单个 `/`，而列表值被规范成 `\`。统一用原生路径后定向重跑 MakeExpression 文件夹 **17/17 通过**。这是全套首跑加定向复验的记录。
- 发布扩展实测脚本：`tools/mpfb2_test/audit.py`，生成角色预设、编辑 `.blend`、GLB、FBX 和 `workflow-all.json`。Hair Cards 结果独立记录，不计入曲线头发/体毛通过条件。
- `tools/mpfb2_test/FaceReview.gd` 对 Godot 4.7.2 的导入和 Forward+ 出图验收。原始结果位于 `.runtime/mpfb2-audit/`：`upstream-equipped.xml`、`upstream-expression-rerun.xml`、`workflow/workflow-all.json`、`face-review/mpfb-face-preview.png`。

### 复现指引

- [MPFB 官方手册](https://static.makehumancommunity.org/MPFB/Docs/)及[扩展发行页](https://extensions.blender.org/add-ons/mpfb/)。资产包取官方 MakeHuman System Assets、System Poses、Hair Editor、Faceunits 01、Visemes 01/02；通过 Asset Library 的包导入器装到隔离环境。Rigify 取 Blender Extensions 0.6.12。按照[底模试验的环境配置](mpfb2-character-test.md#复现)设置 `BLENDER_USER_RESOURCES`、`BLENDER_USER_CONFIG`、`BLENDER_USER_SCRIPTS`；用 `Join-Path` 构造原生 Windows 路径。
- 上游套件：在另一个隔离 profile 内启用 MPFB 的源码标签 `v2.0.18`，令 `extensions/user_default/mpfb` junction 指向源码 `src/mpfb`，安装 System Assets 和 Rigify。用 Blender 绑定的 Python 将 `pytest==8.4.2` 安装到 `.runtime/` 私有依赖目录，打开源码 `test/testdata/test_scene.blend` 后执行 `tools/mpfb2_test/upstream.py -- --pydeps <私有目录> --xml <输出文件>`。同命令可加 `--test tests/eee_ui/create_assets/makeexpression` 做定向复验。
- 发布包流程：`blender -b --python-exit-code 1 --python tools/mpfb2_test/audit.py -- --out <工作目录> --mhm <源码/test/testdata/testchar.mhm>`。将 `character_face.glb`、`FaceReview.gd` 与重命名为 `project.godot` 的 `preview.godot.txt` 放到独立预览目录。Godot 先 `--headless --path <预览目录> --import`，再 `--path <预览目录> --rendering-method forward_plus --script res://FaceReview.gd`。通过时打印 `MPFB_FACE_GODOT_PASS` 并写图。
