# MPFB2：按学院角色示意图拟合肌肉分布

2026-11-21 · Blender 4.2.1 LTS / MPFB 2.0.18 → Godot 4.7.2 .NET Forward+。

沿用[四人三档试样](mpfb2-muscle-study.md)选出的全身 Muscle 值，在每人一组「仅全局 / 追加局部目标」中固定性别、年龄、体重、身高和头身。局部调节使用 MPFB 自带的左右三角肌、上臂、前臂、股部、小腿、背阔、胸大肌、肩距、横向胸廓、腰围与腹部张力目标；左右成对调整。具体名称、正负方向和目标强度见 `tools/mpfb2_test/muscle.py` 的 `FIT_TARGETS`。

## 对齐方向和结果

| 角色 | 固定 Muscle | 参考图里的造型重点 | 局部拟合结果 |
| --- | ---: | --- | --- |
| 侦探 | 0.50 | 匀称偏瘦，肩胸有浅轮廓，腿线较窄 | 保留 177 cm / 6.5 头身；略收躯干、前臂、腿，胸背只增加浅体块。大腿 −2.2 cm、小腿 −1.9 cm。 |
| 霍铎 | 0.75 | 胸背宽厚，上臂、前臂和小腿最结实 | 加肩距、胸背和四肢；上臂 +5.8 cm、前臂 +5.1 cm、小腿截面 +6.6 cm；腰线前后约 85.0 cm。 |
| 雀儿 | 0.75 | 紧凑运动体：肩背和前臂结实、腹面连贯 | 加肩背和前臂、大腿及小腿；前臂 +1.7 cm，小腿 +2.3 cm。放回腰线 +3.6 cm，降低腹部张力，保留自然腹部 v3 的平顺过渡。 |
| 阮清月 | 0.50 | 肩臂、躯干和腿部用柔和连续的体面 | 小幅减肩、上臂、前臂和腿部峰值；上臂 −0.8 cm、前臂 −0.5 cm、小腿 −0.6 cm。 |

厘米数是同一角色两版模型的变化量。小腿取骨轴 31% 的截面，其他部位沿用前轮的截面定义。霍铎的左右上臂骨根距离实际增加 1.9 cm；雀儿增加 0.9 cm。关闭贴图后仍可检查肩背和手臂的体量差，雀儿与阮清月使用相同审阅服覆盖和同一灯位。

正面参考使用学院光头底模示意图的单人源图：侦探的 6.5 头身校正稿、霍铎和阮清月的光头正面稿、雀儿的自然腹部 v3。排版用颅顶到足底整图等比校准，保留参考站姿。雀儿、阮清月另对看对应侧背示意。这里拟合肌肉和体量分布；参考的站距、掌心方向、肩髋标点以及脸型仍可在独立轮次校正。图里的光影也参与了肌肉观感，当前纯色渲染保留自己的照明。

## 验证与复现

- `.runtime/mpfb2-fit/presets/`：4 份全局基线和 4 份局部拟合 MPFB 预设；4 份拟合 JSON 已在干净 Blender 场景回读，核对全身 Muscle 和全部局部目标强度。
- `.runtime/mpfb2-fit/godot/`：8 份 GLB。导入后全数检查 53 骨及屈肘、屈膝；Forward+ 拍摄正、侧、背与两张试姿。各人物的两版沿用同机位、灯光和 A 姿。
- `.runtime/mpfb2-fit/00-design-comparison.jpg`：左示意图，中全局基线，右局部拟合。`fit-receipt.json` 记录每份形态输入、精确截面和三角面数。当前游戏人物资源保持原样。

继续使用[前轮配置的 Blender 隔离 profile](mpfb2-character-test.md#复现)，从仓库根目录运行：

```powershell
$out = '.runtime/mpfb2-fit'
$preview = "$out/godot"
blender -b --python-exit-code 1 --python tools/mpfb2_test/muscle.py -- --out $out --design-fit
Copy-Item tools/mpfb2_test/muscle.godot.txt "$preview/project.godot"
Copy-Item tools/mpfb2_test/MuscleReview.gd $preview
godot --headless --path $preview --import
godot --path $preview --rendering-method forward_plus --script res://MuscleReview.gd -- --design-fit
python tools/mpfb2_test/design_sheet.py $out .runtime/academy-body-pilot/jane-qingyue-underwear-v1
```
