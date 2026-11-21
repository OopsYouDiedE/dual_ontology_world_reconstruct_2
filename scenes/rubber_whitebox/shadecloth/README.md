# 03 — The Airborne Shade / 风托黑幕

Bellflower 大厅的独立变体。保留原大厅、双导道、压力板、回程卡榫和低钟门，中央螺旋花冠换为三层遮光装置。

- **上层：** 11.47 m 处的搪瓷吊灯向下打出暖光。保留靠近出口的小范围侧光，让原版低钟的行程仍可取证。
- **中层：** 黑布长约 6 m，窄边时收时展，褶皱从布腹向两端移动。它绕大厅中轴偏心绕行，14 秒一圈；网格实测高度 4.52–7.54 m。投影直接来自布的轮廓，会扫过双导道、底座、地面和柱身。
- **下层：** 六台铸铁皮带鼓风机立在石基上。风口向内并略微向同一旋向偏转；机械配风凸轮沿一圈交替增加风量，设计意图是让布持续浮起并回到环内。样板以确定性的受控轨迹表示这一过程；叶轮跟随相位，风压和织物张力暂未做流固耦合模拟。

## 运行和审查

```powershell
$godot = '.runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64.exe'
& $godot --path . --rendering-method forward_plus res://scenes/rubber_whitebox/shadecloth/Shadecloth.tscn -- "--python=$((Get-Command python).Source)"
python -B scenes/rubber_whitebox/shadecloth/test_shadecloth.py
& .runtime/python/Scripts/python.exe tools/testing/shadecloth_capture.py
```

打开后大厅剖面自动播放。**1–4** 切剖面、贴地、布面近景及半圈后的同机位，各自停在审查相位；**空格** 播放/暂停；**G** 在该机位只移走黑布，风机和原关卡设备留在原位；**Enter** 回到可走的两人原型。现场可按 **V** 切换 27 射线显示。`--walk` 跳过审查，`--pause-review` 从静态剖面开始，`--smoke` 跑参考 AI。只移除布和审查机位均属于诊断路径。

游戏 MCP 使用 `on(scene="shadecloth")`，注册 `shade_a/b/c/d`、`shade_play`、`shade_uncover`、`shade_live`。实机截图写入 `.runtime/shadecloth/plates/`。A、D 为相隔 420 步的同机位；E 为 A 机位只移走黑布的对照图。

## 同源实现

- `arena.json` 定义风机分布、照明、布面尺寸与周期。`shadecloth.py` 继承 Bellflower 的 60 Hz 物理步、每 20 步 27 射线、暗处作废和 AST 许可。黑布的 299 个毫米顶点及 528 个三角面同时供裁判遮光与 Godot 双面投影使用；无投影贴花。诊断帧的放映时间和参赛观测隔离。
- 8 m、仰角 15° 的标准射线最高约 3.72 m，低于布面及其整个扫掠；玩家和比赛射线只通过它在下方产生的光照变化感知它。风机放在原直线导道之外，实体沿用白模凸体。内藏叶轮动画保持在机壳内，并不另占赛道或参加计分遮挡。
- 无头检查完整周期的净空、双面遮光、两相位地面阈值差异，以及普通/强档各三种子的 B4 回放。实机工具检查实际 Forward+ 阴影、同机位移除黑布后的复亮像素、布面随审查播放和物理步变化。
