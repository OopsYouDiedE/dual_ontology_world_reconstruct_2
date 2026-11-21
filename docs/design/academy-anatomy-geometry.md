# 学院人物：正面贴图对照与阴影辅助雕刻

此轮使用用户给出的 `Bald base-body blockouts` 1248×1082 阵容图，处理已下载的七位独立素体：侦探、卢西安、沃德、沈鼎、霍铎、阮清月、代管者。雀儿是独立的第八位，本批输入中没有她的网格。原图以及模型和预览产物留在 `.runtime/academy-body-pilot/`，游戏资产保持原状。

## 参考教程与在本项目的用法

| 来源 | 应用 |
| --- | --- |
| Blender Studio：[Sculpting a complete Planar Head](https://studio.blender.org/training/stylized-character-workflow/5d3a1bd54bc3ff1bb9513d3e/)、[Planar Torso](https://studio.blender.org/training/stylized-character-workflow/5d7f7dcd9889b3993224bea2/)、[Planar Arms & Legs](https://studio.blender.org/training/stylized-character-workflow/5d7f7e61db37a94301d88fef/)、[Planar Hands & Feet](https://studio.blender.org/training/stylized-character-workflow/5d7f7f4c9bc439fdf7f65b31/) | 先用颏、肩、髋、膝和踝定大形，再雕出额—眶—颧—颌与胸—肩—肋弓、膝—胫—踝的面转折。前臂和掌背沿自身的 A 姿轴建形。 |
| Blender 手册：[Draw Sharp](https://docs.blender.org/manual/en/4.2/sculpt_paint/sculpting/tools/draw_sharp.html)、[Scrape](https://docs.blender.org/manual/en/4.2/sculpt_paint/sculpting/tools/scrape.html) | 用窄的结构沟配合宽面起伏表现转折。这里通过顶点坐标编辑实现，输出为实际可编辑网格。 |
| OpenStax：[肩带与上肢肌](https://openstax.org/books/anatomy-and-physiology-2e/pages/11-5-muscles-of-the-pectoral-girdle-and-upper-limbs)、[骨盆及下肢肌](https://openstax.org/books/anatomy-and-physiology-2e/pages/11-6-appendicular-muscles-of-the-pelvic-girdle-and-lower-limbs) | 胸肌向上臂汇入，三角肌下收，膝上股四头肌和髌骨分开，小腿前胫与后侧肌腹错开。 |
| Blender Studio：[Planning the Facial Retopology](https://studio.blender.org/training/stylized-character-workflow/5e5407ec8faf011a381510d7/) | 原有的眼睑和唇缘闭合边环独立编号；只压口缝而不焊唇，眼球为分件，眼枢轴居中。保留开下唇的检查形态键。 |

## 三层比较

1. **比例与剪影。** 按每人正面的冠、颏、颈窝、腋、腰、裆、膝、踝及足底标点重排比例；眼睛、鼻尖和口缝再用独立标点对齐。侦探采用 1.77 m、6.5 头身。其他人单独按 1 m 归一仅用于审阅。按行匹配正面图与实际模型的肢体轮廓区间，保留深度。剪影 IoU 为二值轮廓交集除以并集，统计采用统一的头顶—足底高度坐标。
2. **直投诊断。** 将参考原图按同一正投影 X/Z 坐标贴到实际模型的前表面，遮掉背景、侧背及无参考的区域。对照图并列正面、斜侧贴图与纯色。直投下相似度主要反映对位；判断三维体块以关贴图的同灯位视图为准。带 04 / Photo projection 集合的 `.blend` 中，关闭正在显示的 01/02，开启 04，再切到材质预览；参考 PNG 已打包。纯色 GLB 另行导出，无图像和贴图。
3. **明暗辅助实际雕刻。** Astra 编写的 `anatomy_relief.py` 在登记的人体面区采样较宽的双侧皮肤明暗反差，并据其调整法向形态的强度。下推胸肌下缘、肋弓转折和眉眶沟，抬起胸肩、颧面、髌骨与胫骨体块。坐标只沿 Y 前后移动，保持正面 X/Z 轮廓；冻结眼睑、唇缝、遮盖区与指定环线。逐三角检查局部翻面并对濒临折叠的顶点收力；Blender 随后查非邻接三角相交，对手足末端的小片折叠仅在得分变好时局部重布四边面。阮清月的身体保留更平顺的过渡；沃德保持倒三角，霍铎厚胸肩，沈鼎保留腹部体积和独立胡须，卢西安和代管者保留各自的窄身形及脸部差异。

## 验收与复现

`.blend` 保留低模四边面和高分辨率审阅几何；GLB 身体、双眼与眉片合计不超过 5,000 个三角面，内衣和胡须另计。`blender-audit.json` 记录导入几何和导出 GLB 的面数、开边、自交；`anatomy-metrics.json` 记录剪影、身高比例、面区位移、表面积中心和闭壳等密度重心偏差。本轮纯色低模的身体、眼球、眉片为 4,930–4,988 三角面；七个身体低模与高分辨率审阅网格的静态自交均为 0。侦探、沃德、沈鼎的身体低模全四边面，其余四位各保留两个三角面。参考是正面定稿的工作图；侧背形态和动作变形仍是独立验收项。纯色对照中需继续检查耳廓、指趾和眼鼻颌面。

```powershell
$d='.runtime/academy-body-pilot'
$ref="$d/anatomy-geometry-v7/reference-lineup.jpg" # 用户附件原图
$o="$d/anatomy-photo-relief-final"
$baseline="$d/anatomy-geometry-v7/fitted" # 上轮无明暗辅助的纯色校形
$blender='C:\Program Files\Blender Foundation\Blender 4.2\blender.exe'
python tools/academy_cast/anatomy_geometry.py "$d/source-local-delivery" $ref $o --relief 2.15 --geometry-only
& $blender -b --factory-startup --threads 2 --python-exit-code 1 --python tools/academy_cast/anatomy_geometry_blender.py -- $o "$d/source-local-delivery"
python tools/academy_cast/anatomy_geometry.py "$d/source-local-delivery" $ref $o --fitted-review --geometry-only
python tools/academy_cast/anatomy_photo_compare.py $ref $baseline "$o/fitted" "$o/photo-check"
& $blender -b --factory-startup --threads 2 --python-exit-code 1 --python tools/academy_cast/anatomy_photo_blender.py -- "$o/models" "$o/photo-check" "$o/photo-models"
```

Python 侧依赖：NumPy、SciPy、Pillow、OpenCV (`cv2`)。Blender 侧只需 Blender 自带的 `bpy`、`mathutils` 和 NumPy。
