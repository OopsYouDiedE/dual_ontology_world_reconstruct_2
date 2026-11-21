# MPFB2 肌肉滑块：四人三档试样

2026-11-21 · Blender 4.2.1 LTS / MPFB 2.0.18 · Godot 4.7.2 .NET Forward+ / RTX 3070。

**角色预设起点：霍铎和雀儿用 `0.75`，侦探和阮清月保留 `0.50`。** 肌肉滑块会一起改变几处轮廓；它对霍铎主要增加上臂体量，对两位女性样体还会明显收腰。雀儿如需更强的攀爬体态，下一步优先局部修肩背、前臂和大腿，并保持腹面平顺。`1.00` 留作高档对照。

| 试样 | 性别滑块 | 人物卡年龄 → Age | Weight | 赤脚展示身高 | 结果与建议 |
| --- | ---: | ---: | ---: | ---: | --- |
| 侦探 R-05 | `1.00` | 27 → `0.5154` | `0.42` | 177 cm，6.5 头身 | `0.75` 胸背起伏稍明显，前臂反而少约 0.9 cm；`0.50` 更贴合匀称偏瘦的设定。 |
| 霍铎 R-06 | `1.00` | 29 → `0.5308` | `0.60` | 182 cm* | `0.75` 上臂和肩背已有可见的结实感；`1.00` 上臂增加到约 3.6 cm、轮廓更突出。 |
| 雀儿 R-03 | `0.00` | 19 → `0.3750` | `0.49` | 156 cm* | `0.75` 增加少量四肢体量，腹面过渡较平顺；腰线比基线收约 2.6 cm。 |
| 阮清月 R-10 | `0.00` | 19 → `0.3750` | `0.45` | 164 cm* | `0.50` 的肩臂、躯干过渡更柔和；`1.00` 腰线收约 5.2 cm，背面体面起伏更清楚。 |

`*` 三个身高是本轮展示尺寸。人物年龄取[角色规格](academy-featured-character-export.md)，按 [MakeHuman `setAgeYears`](https://github.com/makehumancommunity/makehuman/blob/master/makehuman/apps/human.py) 的约定算出试填滑块；`Age`、`Weight`、`Muscle` 是形态输入。性别、年龄、体重、高度滑块及其他输入在同一人三档内固定。侦探的头部纵向目标在 `0.50` 拟合一次并冻结。各人的三档原始赤脚高度在 0.01 cm 精度上相同，分别约 174.10、172.73、146.24、146.24 cm；导出前整身等比缩放到展示高度，并将足底对齐至 0。预设 JSON 保留 MPFB 原始尺寸和可编辑滑块。

后续预设见[按示意图调整局部肌肉分布](mpfb2-reference-fit.md)。

## 截面量测

以下为相对同一人 `0.50` 的变化，单位 cm；每格依次为 **`0.75` / `1.00`**。在未摆姿的烘焙身体上计算闭合截面周长：右上臂、右前臂、右大腿从各自关节头沿骨轴到 48%、32%、38% 作横截面，腰线取展示高度 59% 的水平截面。这里量的是底模外形。

| 试样 | 上臂 | 前臂 | 大腿 | 腰线 |
| --- | ---: | ---: | ---: | ---: |
| 侦探 | +0.2 / +0.6 | −0.9 / −1.6 | −0.3 / −0.4 | +1.3 / +2.6 |
| 霍铎 | +1.5 / +3.6 | +0.3 / +1.1 | +0.6 / +1.5 | +0.6 / +1.3 |
| 雀儿 | +0.5 / +1.0 | +0.4 / +0.9 | +0.5 / +1.0 | −2.6 / −5.3 |
| 阮清月 | +0.5 / +1.1 | +0.4 / +0.9 | +0.5 / +1.2 | −2.7 / −5.2 |

## 产物与复现

- 临时产物在 `.runtime/mpfb2-muscle/`：`presets/` 有 12 份 MPFB 人体预设；`muscle-receipt.json` 包含完整参数、校准前尺寸、截面和导出数据。
- `godot/` 有 12 份 GLB、三视图和两张试姿图（`01-front.png` 到 `05-stride.png`）。四组共用正交相机、布光和着色方式；蓝灰审阅衣是着色分区，没有额外衣物网格厚度。`pose-receipt.json` 记录每件模型的骨架与动作采样。
- 12 件均导入 Godot 并捕获 Forward+ 视口，均为 53 骨、26,756 身体三角面（加眼睛为 26,928）。采样到肘弯约 44.46°、膝弯约 43.48°。这些是保真底模，现有游戏角色资源保持原样。

使用[前次试验的隔离 Blender profile](mpfb2-character-test.md#复现)（已启用 MPFB 和安装 System Assets）。从仓库根目录运行：

```powershell
blender -b --python-exit-code 1 --python tools/mpfb2_test/muscle.py -- --out .runtime/mpfb2-muscle
$preview = '.runtime/mpfb2-muscle/godot'
Copy-Item tools/mpfb2_test/muscle.godot.txt "$preview/project.godot"
Copy-Item tools/mpfb2_test/MuscleReview.gd $preview
godot --headless --path $preview --import
godot --path $preview --rendering-method forward_plus --script res://MuscleReview.gd
```

`blender` 和 `godot` 未加入 PATH 时使用相应的绝对可执行文件路径。逻辑单测可在最后一条 Godot 命令加 `--headless` 和末尾 `-- --check-only`，实际截图走 Forward+。
