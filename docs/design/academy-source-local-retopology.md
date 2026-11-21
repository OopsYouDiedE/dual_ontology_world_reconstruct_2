# 学院人物｜原模表面重布线与纯色审阅

## 2026-11-21：七位首轮审阅

每位使用自己的 `academy-body-*-quad.zip`；首轮下载保持原样。旧面罩试件和通用人体拟合试件不进入这批模型。流程在原模上清理游离碎片、分区补洞、配对三角面、删减完整四边面带并匀顺身体边距。眼、嘴各做局部环带，额头和脸颊保留原网格的连续走向。模型含独立双眼和可打开的内翻唇缘；内衣为独立纯色审阅壳，底下保留完整人体。材质只使用纯色面，GLB 未包含图片或纹理。鼻翼到下巴的外圈走线仍需结合表情精修验收。

`H` 是该角色原模的赤脚全高。重心按同一坐标系、均匀密度和有向四面体体积计算。Tripo 原网格存在开边，先保留主体并补洞，再将其作为体积基准；有自交的角色读数是基于封壳的估算。另对原主体与输出计算面积加权表面中心，便于交叉检查。区域双向最近距离使用三角面重心坐标规则取样，属于表面偏差估计。侦探按颅顶至重投影颏点校准为 6.50 头身和 1.77 m；其他模型使用各自 1 m 的审阅归一尺度，保留自身比例，未核定游戏内绝对身高。

| 角色 | 皮肤四边面 / 余三角面 | 导出折三角（含双眼） | 估算体积重心偏差 | 表面中心偏差 | 原主体 → 审阅网格自交候选对 | 优先看 |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| 侦探 | 2,389 / 0 | 4,970 | 0.083% H | 0.078% H | 0 → 0 | 试姿时肩、肘和膝的压缩/伸长 |
| 卢西安 | 2,400 / 2 | 4,994 | 0.068% H | 0.011% H | 85 → 110 | 足底、手指 |
| 沃德 | 2,403 / 0 | 4,998 | 0.155% H | 0.052% H | 46 → 69 | 髋及大腿内侧 |
| 沈鼎 | 2,400 / 0 | 4,992 | 0.050% H | 0.065% H | 1 → 9 | 手指 |
| 霍铎 | 2,397 / 2 | 4,988 | 0.084% H | 0.052% H | 6 → 15 | 足底、手指 |
| 阮清月 | 2,401 / 2 | 4,996 | 0.027% H | 0.047% H | 11 → 11 | 手指 |
| 代管者 | 2,396 / 2 | 4,986 | 0.048% H | 0.024% H | 129 → 177 | 裆部、大腿内侧、足底 |

七件皮肤网格闭合且边的绕序一致。距原主体的双向表面偏差 P95 为 0.103%–0.206% H，最大值在 1.760%–2.086% H，包括新挖的眼窝和口袋。没有共用顶点的相交三角面对由 Blender BVH 报告，分类与对应顶点组供定位；多件补洞边缘仍有局部穿插。侦探的临时折弯探针测试了抬臂屈肘、屈髋屈膝。与中性姿相比，抬臂屈肘有 55 个三角面面积变为两倍以上，屈髋屈膝有 12 个三角面压至一半以下。探针使用临时关节权重，结果用于定位下一轮精修，正式蒙皮和角色表情仍待验收。本批为审阅资产，未替换游戏资产。

### 打开与复验

- `.runtime/academy-body-pilot/source-local-delivery/academy-seven-solid-review.zip` 含七个 `.blend`、七个 `.glb`、全身和脸部线框、侦探折弯试姿与 JSON 审计。`metrics.json` 同时给出 XYZ 重心偏移、各分区 P95/最大偏差与补洞位置；`blender-audit.json` 以导出 GLB 索引实测三角面。
- Blender 打开 `.blend`，选择 **Body**；`Tab` 看布线，`Z → Wireframe` 看透视线框。隐藏 **CLOTH** 可核对完整躯干和髋部；展开 **SOURCE** 打开原主体叠看。顶点组 **QA / Self-crossing candidates** 可选中剩余穿插候选区；脸部组记录各眼与唇环，`Preview - lower lip open` 是审阅用形态键。四边面以 `.blend` 为准，GLB 用三角面交给引擎。
- 复建：系统 Python 需 NumPy、SciPy、Pillow。启动参数 `ZIP_DIR` 是七份 ZIP 的目录；`ANCHORS` 放现有正面画面相机 `*-camera.npz` 与各人的 `*-landmarks.npy`；`OUT` 位于 `.runtime/`。使用 Blender 4.2.1 后台运行：

  ```powershell
  python tools/academy_cast/tripo_surface.py ZIP_DIR ANCHORS OUT
  python tools/academy_cast/tripo_surface_preview.py OUT
  blender -b --factory-startup --threads 2 --python-exit-code 1 -P tools/academy_cast/tripo_surface_blender.py -- OUT
  python tools/academy_cast/tripo_surface_pose_probe.py OUT
  ```

## 手工精修与验收

1. **先定边流和中性轮廓。** 原模锁为参考层。四边面从眼、嘴和下颌的既定边流开始，额头、颊面按逐级面积过渡。鼻梁至鼻翼和嘴角保留可供表情变形的连续区，极点移到较平坦的组织，避开眼角、唇角和弯折主线。眼睑闭环围独立眼球，检查擦过眼球切面的弧度；上下唇各有边与内翻壁，张嘴后能看到连续的口腔袋。
2. **身体按关节分布环带。** 以肩、腋下与胸背交界、肘腕、髋臀、膝踝和指根做局部起点。三道环是第一轮的画线方法；折弯外侧要能张开、内侧要能压缩，间距以实际活动量决定。镜像便于搭中性布线，角色原有的左右差异可在贴合后恢复。Shrinkwrap 建议分区、限制投影方向与距离，尤其要保护贴近的双腿、手指、唇内壁。组装后分别看正、斜、背、中性及弯曲姿。
3. **衣片独立。** 内衣边缘沿其轮廓走顺，身体在衣内保持连贯的大形体。基础母版保留完整；从服装版本复制后再按遮挡删除多余皮肤。最后在动作里检查皮肤与衣片互穿。
4. **雀儿的腹线以浅纵向过渡为主。** 在上腹留浅中线，两侧的腹直肌外缘向下淡出，下腹维持柔和弧面。横向边用于形状变形，不特意刻出腱划分块。纯色阶段用大形体和侧光复核；未来需要额外细节，可在高模轻刻后烘到新低模 UV 的切线法线，或用很浅的手绘过渡。阮清月保持平缓腰腹，不共用雀儿的腹线塑形。
5. **重心配合局部审计。** 对齐单位、地面、朝向后计算三轴重心差；全身差值作为形体回归指标，再检查各区剪影、折线、面长宽比和自交。加新 UV 后，重新对照高模用 Selected to Active 烘焙，检查射线穿透、笼体边界及接缝；本轮使用纯色，未烘焙贴图。

## 可核实的参考资料

- Blender Studio： [面部重布线规划](https://studio.blender.org/training/stylized-character-workflow/5e5407ec8faf011a381510d7/)、[边流与关节](https://studio.blender.org/training/stylized-character-workflow/5e5408388faf011a381510de/)、[极点与面片](https://studio.blender.org/training/stylized-character-workflow/5e5408688faf011a381510e2/)、[面部变形](https://studio.blender.org/training/stylized-character-workflow/5e6a5cc51921d7373e6205a9/)、[身体重布线](https://studio.blender.org/training/stylized-character-workflow/10-body-retopology/)、[服装重布线](https://studio.blender.org/training/stylized-character-workflow/11-outfit-retopology/)。这是课程章节目录，部分内容可能需要登录。
- Blender 4.2 手册：[Shrinkwrap 投影](https://docs.blender.org/manual/en/4.2/modeling/modifiers/deform/shrinkwrap.html)、[Mirror 和中缝](https://docs.blender.org/manual/en/4.2/modeling/modifiers/generate/mirror.html)、[Cycles 烘焙](https://docs.blender.org/manual/en/4.2/render/cycles/baking.html)。腹壁解剖看 [OpenStax：Axial Muscles of the Abdominal Wall and Thorax](https://openstax.org/books/anatomy-and-physiology-2e/pages/11-4-axial-muscles-of-the-abdominal-wall-and-thorax)。
- Gemini 清单中的 BV1Er4y137Cp 实际标题指向 3ds Max 头部建模，支持参考头部布线概念；两条 YouTube 和所列 Meshy 中文页的具体术语及内容本次未验证。AI 线框图用于构图和表面边流参考，实际关节决策以模型折弯为准。
