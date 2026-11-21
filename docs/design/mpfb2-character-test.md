# MPFB2：侦探底模与 Godot 导出试验

**结论：MPFB2 可用作角色母版、尺寸拟合和初始绑骨工具。** 侦探近景模型建议由完整 HM08 母版做局部重布线，给眼口、耳、手指与活动关节分配面数。试过的 `male1591` 适合远景或占位；Blender 一键减面可用于快速试姿。

## 实测

2026-11-21，Blender 4.2.1 LTS + MPFB 2.0.18，Godot 4.7.2 .NET；画面由 RTX 3070 的 Vulkan Forward+ 实际渲染。这里只测单个侦探规格样体。

- 初始体型量得 172.91 cm、7.08 头身。只调整 MPFB 的整体身高和 `head-scale-vert-incr`，量得 **177.00 cm、6.500 头身、头高 27.23 cm**。头高使用 HM08 的颅顶 881 与颏底 791，身高从最低足底量至颅顶；根在地面，GLB 使用米。
- 四个 GLB 均通过导入和蒙皮检查，带 53 骨的 `game_engine` 骨架。Godot 读到试姿动画的约 44.46° 屈肘、43.48° 屈膝与 28.65° 抬腿。画面检查覆盖正面 A 姿、侧面跨步屈膝、脸和肩部近景、穿衣抬臂。单独的身体、双眼及衣件可随骨变形。

| GLB | 身体 | 双眼 | 衣件 | 合计 | 画面观察 |
| --- | ---: | ---: | ---: | ---: | --- |
| `full` | 26,756 | 172 | — | 26,928 | 耳廓、眼睑、口缘和脚趾细节最完整，适合作为编辑母版。 |
| `collapse` | 4,700 | 172 | — | 4,872 | 大轮廓和脚趾保留较多，近景能看到耳廓、眼鼻周及胸肩的折面。 |
| `proxy` (`male1591`) | 3,140 | 172 | — | 3,312 | 预算有余量，耳内结构和脚趾简化明显，侧面足跟轮廓更硬。 |
| `dressed` (`male_casualsuit01`) | 20,028 | 172 | 16,672 | 36,872 | 证实官方衣件的独立网格、遮挡组、权重和贴图可导出；衣件本身也要重布线。 |

三个素体的深色短裤区域是审阅用材质分区。正式接入前还需做身份雕形、关键部位重布线、全动作穿插验收，并将试验 GLB 的正面 `+Z` 和 MPFB 的 `hand_l/hand_r` 骨名转成项目约定的 `-Z`、`LeftHand/RightHand` 及现有动作。导出采用 Blender 默认的每顶点四骨影响；本轮不涉及现有角色替换。

## 复现

- 扩展： [Blender Extensions / MPFB](https://extensions.blender.org/add-ons/mpfb/)，固定 **2.0.18**，安装包 SHA-256 `c075b3e9b94b8e5556a5f03f4653602d02ea306de08126e8f55ed6dee28a2dad`。
- 衣件、双眼、`male1591` 来自 [MakeHuman System Assets（CC0）](https://static.makehumancommunity.org/Assets/AssetPacks/makehuman_system_assets.html)。使用缓存 `.runtime/academy-cast/system_cc0.zip` 或从项目站取 `makehuman_system_assets_cc0.zip`；构建脚本核对 SHA-256，并只解压用到的资产。MPFB 代码和数据留在本机测试目录。

在仓库根目录运行 PowerShell。首次用一份新 Blender 配置安装，已有本测试配置可跳过安装两条命令：

```powershell
$root = (New-Item -ItemType Directory -Force .runtime/mpfb2-test).FullName
$blender = 'C:/Program Files/Blender Foundation/Blender 4.2/blender.exe'
$godot = (Resolve-Path .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe).Path
$env:BLENDER_USER_RESOURCES = (New-Item -ItemType Directory -Force (Join-Path $root profile)).FullName
$env:BLENDER_USER_CONFIG = (New-Item -ItemType Directory -Force (Join-Path $env:BLENDER_USER_RESOURCES config)).FullName
$env:BLENDER_USER_SCRIPTS = Join-Path $env:BLENDER_USER_RESOURCES scripts
& $blender -b --factory-startup --python-expr 'import bpy; bpy.ops.wm.save_userpref()'
& $blender --command extension install-file --repo user_default --enable "$root/mpfb-2.0.18.zip"
& $blender -b --python-exit-code 1 --python tools/mpfb2_test/build.py -- `
  --output "$root/review" --system-pack .runtime/academy-cast/system_cc0.zip
$preview = (New-Item -ItemType Directory -Force "$root/godot-review").FullName
Copy-Item "$root/review/*.glb",tools/mpfb2_test/Review.gd $preview
Copy-Item tools/mpfb2_test/preview.godot.txt "$preview/project.godot"
& $godot --headless --path $preview --import
& $godot --headless --path $preview --script res://Review.gd -- --check-only
& $godot --path $preview --rendering-method forward_plus --script res://Review.gd
```

本地输出：`review/detective_mpfb.blend`（保留体型滑块、骨架及拟合衣件）、`review/blender_receipt.json`（尺寸、面数、骨架和 GLB 的上下界）、`godot-review/01-front.png` 至 `04-suit.png`。Godot 检查通过时输出 `MPFB2_GODOT_PASS`。
