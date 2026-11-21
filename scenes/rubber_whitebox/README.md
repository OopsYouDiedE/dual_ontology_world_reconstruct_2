# Rubber Yard · Test Cell A

独立白模，含第三人称测试角色、坡道与落阶、跳跃块、可推动的配重、压力板和可通过的升降闸。游戏 UI 与场内标注采用英文。白模尺寸、位置与碰撞可直接在 Godot 编辑器中调整；测试角色也可单独实例化到其他样板场景。正常运行入口仍是 Rogue Run。

参考 Bilibili 的《当你给游戏加入真实的物理引擎！》（BV1Gvw9eiEhe）约 00:32–00:52：红墙、蓝地面与浅色闸框用于快速读出场地结构。白模里的材质与场景几何为原创。

## 试玩

从仓库根目录执行，或在 Godot 中打开 `RubberYard.tscn` 后按 **F6**：

```powershell
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64.exe --path . res://scenes/rubber_whitebox/RubberYard.tscn
```

| 输入 | 作用 |
| --- | --- |
| WASD / 方向键 | 随相机方向移动 |
| Space / Shift | 跳跃 / 跑步 |
| 点击后移动鼠标，或 Q / R | 环绕相机 |
| Esc | 释放鼠标 |
| 滚轮或 Z / X | 拉近 / 拉远 |
| Page Up / Page Down | 抬高 / 压低相机视线 |
| Backspace | 复位角色、配重与闸门 |
| H | 切换 HUD |

站上 **LOAD** 可升闸；离开后闸门短暂保持开启。把 **PUSH** 配重从右侧向左推上压力板，可以持续开启。闸口内有角色或配重时，已抬起的闸会继续保持通行。

## 地板与光照

`RubberTile.gdshader` 以世界坐标投影 1 米见方的橡胶贴片。墙与器材共用压缝、圆边和定位十字；地板另外启用模压颗粒、细色屑和不同区域的哑光磨痕。颗粒在远处按像素覆盖渐隐。地板每两格印一条浅色粗线，中间夹一条细线；将蓝色地板材质的 `floor_grid_ink` 设为 `0`，即可只保留橡胶本身的压缝与场内路线标识。

`YardLook.tres` 是本场景的独立 WorldEnvironment，包含冷色天空补光、AgX、接触遮蔽与 SDFGI；开放的庭院使用暖色日光与软阴影。场景在 Forward+ 下以原分辨率渲染并启用 TAA。近看地板可以滚轮拉近，再向下转动相机；`H` 适合取干净画面。

## 实机验证

```powershell
& .runtime/python/Scripts/python.exe tools/testing/rubber_yard_smoke.py
```

脚本用项目的游戏 MCP 启动独立 Forward+ 窗口，检查跳跃着陆、坡道与台阶、墙体碰撞、压力闸通行与关闭、配重、复位及相机，并在 `.runtime/rogue-mcp/` 留下全景、近景和日志的路径。

## 夜班房间白模审查

[Room Review](room_review/README.md) 按主线顺序摆出 11 种关卡布局，复用本场的墙地橡胶贴片和第三人称测试角色。
