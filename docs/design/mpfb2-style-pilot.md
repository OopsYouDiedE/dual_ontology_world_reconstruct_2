# MPFB2 学院角色风格试验 · R-05

**建议：角色开独立反壳细线，建筑保留项目现有低多边形材质表现。** R-05 已跑通比例、脸、附件、烘焙与 Godot 材质。建议保留侦探的 **177 cm / 6.5 头身** 设计母版，另留本轮 **5.98 头身** 满强度试片供比较；下轮把纵向比例和表面简化拆成两个权重。

环境：Blender 4.2.1 LTS、MPFB 2.0.18 / HM08、Godot 4.7.2 .NET / Vulkan Forward+、RTX 3070。沿用[四人体型 LOCAL FIT](mpfb2-reference-fit.md)；使用独立预览项目和墙板、地面搭建的测试台。现有游戏角色、主场景与后处理保持原样。

## 逐层结果

| 层 | 实测 | 采用建议 |
| --- | --- | --- |
| **MakeTarget / 比例** | 关闭 Phenotype，从原始 HM08 出发，以 MakeTarget 操作器写出男女各一份 `.target`。男版头部／掌部名义强度 +12%／+15%，女版 +14%／+12%；同时增强前臂末端、小腿体面，对身体网格选区做邻域平滑。叠加到 R-05 的局部体型和身份目标后重新按 177 cm 归一、从变形后的辅助几何重建骨架。按颅顶到颏、颅顶到足底量测，R-05 从 **6.50 → 5.98**，头高 **27.23 → 29.59 cm**。雀儿加载女版后 **6.99 → 6.18**，仅做几何验证。 | 两套目标文件可复用；比例推满适合作风格上限，命名角色各自定头身。R-06、R-03、R-10 的脸部与完整流程留待单角色试制。 |
| **身份脸 / 表情** | R-05 以正面光头设计稿为方向：强化颧骨、加宽收短下巴、窄化鼻部、略收嘴宽，重做内端较厚、外端收尖的不透明眉条。眉条沿底模三角面插值，迁移 5 个眉部形态键。GLB/Godot 实测 **53 骨、67 个身体面部通道**；`jawOpen` 和 `viseme_aa` 同时驱动牙齿和舌头，双眨眼及提眉生效；抬手镜头验证右肘姿态实际转动。 | 眼睑轮廓、鼻尖和唇缘还可按正侧稿继续雕形。预览验证了通道与附件联动；全套表情的穿插、说话动捕和游戏动画挂点单独验收。 |
| **发服几何** | 头发由加厚发帽和 7 条封端的倒角曲线发束组成，全部绑定头骨。试衣从身体网格提取，约 7 mm 离体、4 mm 加厚、1.6 mm 倒角；领口裁平，抬手后可读。 | 保留不透明发块和物理折边作为方法。样片发束偏高且重复、袖边仍有折点，衣身跟随人体体面产生过多暗斑。正式版重做发型外轮廓和袖笼／衣领拓扑，再做可控的衣褶。 |
| **肤色烘焙** | 去掉写实皮肤贴图与高频凹凸。Cycles 把皮肤纯色 × 局部 AO × 网格凹部曲率近似值烘进 **512×512** UV 底色，AO 距离 34 mm，曲率调制上限 15%。图 03/04 的变化集中在眼周、鼻底与口耳暗部。 | 保留这种轻量底色；衣料的细褶和内结构线单独烘。纸纹与衣服 AO/曲率本轮未跑。 |
| **面部法线** | 椭球到脸颊的 Data Transfer 最近面插值，混合 0.36，保护眼鼻唇。738 个加权顶点；2,838 个角法线偏移超过 0.1°，平均 **2.77°**、最大 **12.56°**。同光位 04/05 肉眼差别很小。 | 保留为侧光问题的定点修整工具，默认先不上。增加旋转灯位与表情过程后，再决定哪些角色需要。 |
| **Toon / 反壳 / 全屏** | 以 `light()` 的两处柔阈值加少量连续漫反射，脸 `band_width=0.10`、衣发 `0.08`。反壳 `next_pass` 厚度约 1.35–2.15 mm，鼻口、手指借 `COLOR_0.a` 降至约 32% 基础线宽；实际导入范围 0.3216–1.0。全屏版追加 Forward+ 深度／法线边缘，墙板框、地面交界和角色边缘同时变深。 | 先用 **柔色阶 + 角色反壳 + 少量贴图内线**。全屏版本保留作对照；需在正式房间跨镜头验内部线条、远处闪烁和性能之后，再考虑做成独立视觉模式。 |

截图为 1232×756 实时视口。排除顶部 62 px 的编号，按“任意 RGB 通道绝对差 >4/255”计，全视口受影响像素：纯色→AO/曲率约 **0.7%**，加面颊法线 **<0.1%**，全身镜头从角色线切到角色＋全屏线约 **4.65%**。这个量测用于定位本组画面的改变量；细线选择以实图中角色和背景的视觉层级为准。06/07 与 08/09 成对，只切换全屏层；01/02 同时更换头身和身份形态，沿用同一套眉形与灯位。

## 插件审查与接入决定

- **本轮沿用 MPFB，项目侧封装脚本。** 原生 `HumanService`、`TargetService` 和 MakeTarget 已支持生成、保存、载入项目形变。`human.r05-styled.json` 以第二资产根的 `custom/` 寻址，独立实例回读后逐顶点与写出前一致（最大误差 **0.0 m**）。预设保存的是体型和目标引用；重建同款发服、脸键及最终 177 cm 归一需要运行脚本。
- `TargetService.bake_targets` 会移除当前形态键。先烘体型／身份，再装入口型和 ARKit。`FaceService.interpolate_targets` 使用 MHCLO 对应关系，务必在 `ExportService.bake_modifiers_remove_helpers` 删除助手顶点之前执行。对已存在的附件形态键，插值会跳过同名键；改脸后从干净编辑配方重建导出副本。
- **实测一个上游边界问题：** 只有 Phenotype、尚无口型或 ARKit 键时，`FaceService.interpolate_targets` 会在临时关闭 viewport modifiers 后提前返回。2.0.18 本机最小复现为 `create_human` → 新建启用中的 `SUBSURF` → 调用插值 → `show_viewport: True → False`。当前顺序先装口型／表情，绕开该分支；适合向上游提交单独修复，项目样板暂无 fork 需求。
- **发布前减面和重定向。** 当前样片 **52,226 三角面、约 10.8 MB GLB**，其中身体 26,756 三角面，牙齿另占 7,120；编辑保真试片用于验流程。生产约 5,000 三角面的身体需要重拓扑并回传权重／表情，游戏骨架挂点还要从 MPFB 的 `hand_l` / `hand_r` 映射到现有 `LeftHand` / `RightHand` 契约。第三方资产入库前逐件核对许可。

技术参考：[MPFB 官方手册](https://static.makehumancommunity.org/MPFB/Docs/)、[Blender Data Transfer](https://docs.blender.org/manual/en/4.2/modeling/modifiers/modify/data_transfer.html)、[Blender Cycles Baking](https://docs.blender.org/manual/en/4.2/render/cycles/baking.html)、[Godot Spatial Shader](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html)、[Godot Screen-reading Shader](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html)。

## 复现

按[底模试验的隔离配置](mpfb2-character-test.md#复现)准备 Blender / MPFB，安装官方 System Assets、Faceunits 01 与 Visemes 01/02，先生成[四人体型 LOCAL FIT](mpfb2-reference-fit.md#验证与复现)中的 JSON。从仓库根目录运行（`blender` 和 `godot` 可替换为本机的固定版本执行文件）：

```powershell
$out = '.runtime/mpfb2-face-fit'
$preview = "$out/godot"
blender -b --python-exit-code 1 --python tools/mpfb2_test/style_pilot.py -- --out $out --presets .runtime/mpfb2-fit/presets
if ($LASTEXITCODE) { throw 'Blender pilot failed' }
New-Item -ItemType Directory -Force $preview | Out-Null
Copy-Item tools/mpfb2_test/style.godot.txt "$preview/project.godot"
Copy-Item "$out/r05-*.glb",tools/mpfb2_test/StyleReview.gd,tools/mpfb2_test/academy_*.gdshader $preview
godot --headless --path $preview --import
if ($LASTEXITCODE) { throw 'Godot import failed' }
godot --path $preview --rendering-method forward_plus --script res://StyleReview.gd
if ($LASTEXITCODE) { throw 'Forward+ test failed' }
```

完成标志：Blender `ACADEMY_STYLE_PASS` 并写 `blender-receipt.json`；Godot `ACADEMY_STYLE_GODOT_PASS` 并出 13 张图。可编辑烘焙工作台 `r05-baked-workbench.blend` 打包贴图；`custom/` 保存两份风格目标；`r05-styled.glb` 是带骨骼、形态键、肤色贴图和线宽遮罩的导出模型，Toon 与描边由 Godot 侧施加。中间产物和视口截图都留在 `.runtime/`。
