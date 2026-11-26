# 主角与队友成衣管线

五名主线角色各输出一个 GLB，放在 `assets/characters/heroes/`：侦探、Hale、雀儿（quer）、卢西安、恶魔。构建回执（身高、头身比、穿模审计、三角面数）写在同目录的 `receipt.json`。

| 部分 | 来源 | 说明 |
|---|---|---|
| 人体 | MPFB2 2.0.18 | 统一写实 6.5 头身，同时求解身高滑杆与 `head-scale-vert-incr`，误差 < 3 mm |
| 骨架 | MPFB 内置 `mixamo` | 骨骼名为 `mixamorig:*`，以后可直接换用 Mixamo 动作 |
| 发型、眉、眼 | MakeHuman CC0 系统包（眼球用包内虹膜贴图，按原画选色：侦探、Hale 灰，雀儿棕，卢西安蓝绿） | `system_cc0.zip`，sha256 已在脚本中校验 |
| 底层衣物 | MakeHuman CC0 成衣（插件 `add_mhclo_asset`） | 按 UV 岛把贴图聚成 1–3 个区域，每个区域换成调色板中的纯色；袜子删除 |
| 外层衣物与道具 | `wardrobe.py` 程序建模 | 外套、马甲、斗篷、帽子、挎包带、鲁特琴等 |
| 动作 | Quaternius Universal Animation Library（CC0） | 重定向到 Mixamo 骨架，片段名按游戏协议命名：idle、walk、run、interact 等；站姿片段把颈和头拉回 85% 直立，避免 UAL 待机的低头 |

## 防穿模

1. 外层衣片从人体表面按层偏移切出，继承人体蒙皮权重。
2. 量出插件衣物沿每个法线方向的厚度，外层衣片从衣物表面再外推一层。
3. 闭合外层完全遮住的皮肤、插件衣物和内层衣片直接删除。
4. 仍然露出的边缘，用最近点检测推到外侧，每个点最多推 12 mm。
5. 切口边界沿自身做平滑，帽子按发型尺寸放大，并删掉帽内的头发。
6. 审计：在静止姿态下被外层包住的内层顶点，于每段动作的 8 帧里检查是否穿出外层，计数写入回执。

## 构建

每个角色单独起一个 Blender 进程，在同一进程里连续构建会崩溃：

```bash
W() { cygpath -w "$1"; }
.runtime/cast-pass/blender.sh --python tools/cast/build_heroes.py -- --system-pack "$(W .runtime/academy-cast/system_cc0.zip)" --motion "$(W "<AnimationLibrary_Godot_Standard.glb>")" --out "$(W assets/characters/heroes)" --only detective
```

`blender.sh` 用隔离配置启动 Blender 4.2，其中装有 MPFB2。动作库下载自 [OpenGameArt](https://opengameart.org/content/universal-animation-library) 或 [quaternius.com](https://quaternius.com)。

## 换用 Mixamo 动作

骨架已经是 Mixamo 命名。在 Mixamo 选「Without Skin」导出 FBX，导入后把动作重命名为游戏片段名（例如 `walk`），在 `export()` 前挂到 `rig` 上即可覆盖对应片段；不需要重定向。

## 按原画拟合人种、身材比例与脸型

侦探、Hale、雀儿和卢西安各有一张目标原画（`reference/`，裁切框和人种配比写在 `reference/manifest.json`）。`fit/` 下的脚本用 MediaPipe 的人体 33 点和人脸 478 点，让 MPFB 身体对齐原画：

| 步骤 | 脚本 | 说明 |
|---|---|---|
| 检测 | `fit/detect.py` | 在原画或渲染图上检测关键点；小脸先由人体点定位头部，再放大检测 |
| 标定 | `fit_heroes.py calibrate` | 渲染一个中性人体，记录人脸点落在哪些网格面上、人体点相对 MPFB 关节的偏差，写入 `fit/face_map.json` |
| 身材 | `fit_heroes.py fit` 第一阶段 | 用有界最小二乘拟合头身、颈、躯干、肩宽、胯宽、腿长、臂长等形变目标，使肩、胯、膝、踝、眼和下巴位置与原画一致 |
| 脸型 | `fit_heroes.py fit` 第二阶段 | 闭环：每轮渲染脸部，再用 MediaPipe 检测，按有限差分求雅可比后更新约 18 组成对的脸型参数；另有偏航、俯仰两个相机参数吸收原画的头部转向。只用合理范围内的参数，不用 `head-fat`、`cheek-volume` 一类会让脸变胖的目标 |
| 游戏内闭环 | `fit_heroes.py facerig` + `fit/godot_loop.py` | 导出带脸型 blend shape 的脸模（身体、眼、眉、睫毛、头发都带形变），`godot_fitloop.gd` 在游戏描色渲染（AcademyStage 加墨线、toon）里把四个人放进同一个世界，用四个视口一起渲染，每轮一帧基准加每个参数一帧探针；Python 检测后更新，结果叠加回 `fit/<hero>.json` |
| 原画投射 | `fit/face_paint.py`（生成时自动调用） | 468 个关键点在网格与原画之间建三角网，脸部每个顶点映射到原画像素，在 UV 里栅格化采样，把原画的眼线、睫毛、眉、鼻影、唇线、胡茬画进皮肤贴图；轮廓边缘和眉线以上逐渐淡出到原画肤色，避免把头发和帽檐阴影画上额头。脸部法线向正面压平 45%，让 toon 光像原画那样整块受光 |
| 成品验收 | `fit/review_built.py` + `fit/sheet.py --built`；游戏描色渲染用 `fit/godot_faces.gd` + `fit/sheet.py --godot` | 加载生成的 GLB，取 idle 首帧做正面全身渲染，再按原画头部朝向做脸部特写，重新检测关键点并与原画叠图 |

拟合结果写在 `fit/<hero>.json`（人种与年龄宏、目标权重、拟合前后误差），`build_heroes.py` 会自动读取。有拟合结果的角色不再强制 6.5 头身，只整体缩放到设定身高，头身比以原画为准，并记录在 `receipt.json`。

```bash
python -m venv --system-site-packages .runtime/facefit-venv   # 再装 mediapipe 1.2.3（无依赖安装）
.runtime/facefit-venv/Scripts/python.exe tools/cast/fit/detect.py --manifest tools/cast/reference/manifest.json --out-dir .runtime/facefit/ref
.runtime/cast-pass/blender.sh --python tools/cast/fit/fit_heroes.py -- --system-pack "$(W .runtime/academy-cast/system_cc0.zip)" calibrate
.runtime/cast-pass/blender.sh --python tools/cast/fit/fit_heroes.py -- --system-pack "$(W .runtime/academy-cast/system_cc0.zip)" fit --only quer
```

模型文件 `face_landmarker.task` 和 `pose_landmarker_heavy.task` 放在 `.runtime/facefit/models/`，从 MediaPipe 官方存储下载。

## Tripo 重拓扑

`reference/tripo/<hero>.glb` 是用原画在 Tripo 生成的四人高清模型（`.gdignore`，不进 Godot 导入）。只用它的形体，不用它的 UV 和贴图（Tripo 会把配色改掉）。`fit/retopo.py` 把零件合并、转成面向 -Y、按身高缩放，给单层布面加 1.2 cm 厚度，体素重建成封闭外壳，再用 QuadriFlow 生成约 2.5 万面的均匀四边面，最后沿法线吸附回 Tripo 外壳（限 2 cm）找回细节。QuadriFlow 拒绝时逐级加大体素（5 → 8 → 12 → 16 mm）；它偶尔直接崩溃，所以每个角色单独开一个 Blender 进程：

```bash
"/c/Program Files/Blender Foundation/Blender 4.2/blender.exe" -b --factory-startup --python tools/cast/fit/retopo.py -- --heroes quer
```

输出 `.runtime/facefit/retopo/<hero>.blend` 和线框图。`fit/retopo_all.sh` 逐个角色跑并按体素尺寸重试。

## Tripo 成品（绑定 + 原画投影）

`fit/rig_retopo.py` 把重拓扑网格接上 MPFB 骨架：用 MediaPipe 姿态点把网格配准到 MPFB 身体，把骨架摆到网格关节处，就近复制权重并平滑（每顶点最多 4 骨），复制完删除 MPFB 身体。贴图是原画正面投影（脸部按人脸关键点分片扭曲，人物遮罩由 `fit/figure_mask.py` 以网格轮廓做 GrabCut），看不到的顶点沿网格扩散填色。动作走 `build_heroes.retarget`。

```bash
.runtime/cast-pass/blender.sh --python tools/cast/fit/rig_retopo.py -- --system-pack <system_cc0.zip> --motion <UAL Godot Standard.glb> --hero quer --out .runtime/facefit/rigout
```

成品放在 `assets/characters/heroes-tripo/`（`.gdignore`，尚未替换 `heroes/`），游戏内对比图 `docs/design/hero-fit/tripo-rigged.jpg`，用 `fit/godot_faces.gd --gltf-dir=res://assets/characters/heroes-tripo` 在运行时加载渲染。已知问题：侧面和背面是扩散出来的颜色；lucian 披风继承手臂权重成团、脸部特写未检出、遮罩带入背景拱门；quer 遮罩在眼部有洞；同一进程第二次创建 MPFB 身体会崩溃（detective 为早一轮结果）。

## 已知待办

- 雀儿的报童帽已缩小，需在游戏内复看是否仍浮在头上。
- 侦探大衣在 signal 动作中穿模计数偏高（约 200 个顶点），主要在袖口和领口。
- 尚未接入游戏：玩家、开场和出征中的 Hale 仍在使用旧的 R-05 模型。
