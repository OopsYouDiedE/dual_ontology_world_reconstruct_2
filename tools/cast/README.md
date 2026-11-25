# 主角与队友成衣管线

五名主线角色各输出一个 GLB，放在 `assets/characters/heroes/`：侦探、Hale、雀儿（quer）、卢西安、恶魔。构建回执（身高、头身比、穿模审计、三角面数）写在同目录的 `receipt.json`。

| 部分 | 来源 | 说明 |
|---|---|---|
| 人体 | MPFB2 2.0.18 | 统一写实 6.5 头身，同时求解身高滑杆与 `head-scale-vert-incr`，误差 < 3 mm |
| 骨架 | MPFB 内置 `mixamo` | 骨骼名为 `mixamorig:*`，以后可直接换用 Mixamo 动作 |
| 发型、眉、眼 | MakeHuman CC0 系统包 | `system_cc0.zip`，sha256 已在脚本中校验 |
| 底层衣物 | MakeHuman CC0 成衣（插件 `add_mhclo_asset`） | 按 UV 岛把贴图聚成 1–3 个区域，每个区域换成调色板中的纯色；袜子删除 |
| 外层衣物与道具 | `wardrobe.py` 程序建模 | 外套、马甲、斗篷、帽子、挎包带、鲁特琴等 |
| 动作 | Quaternius Universal Animation Library（CC0） | 重定向到 Mixamo 骨架，片段名按游戏协议命名：idle、walk、run、interact 等 |

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

## 已知待办

- 雀儿的报童帽偏大，看起来浮在头上。
- 侦探大衣在 signal 动作中穿模计数偏高（约 200 个顶点），主要在袖口和领口。
- 尚未接入游戏：玩家、开场和出征中的 Hale 仍在使用旧的 R-05 模型。
