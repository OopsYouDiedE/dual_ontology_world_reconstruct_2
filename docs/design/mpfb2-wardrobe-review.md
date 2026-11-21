# 学院八人审阅：原始模型与 MPFB 试衣

[学院八位重点人物](academy-featured-character-export.md#本轮名单)为侦探 R-05、卢西安 R-01、沃德 R-04、雀儿 R-03、沈鼎 R-07、霍铎 R-06、阮清月 R-10、代管者。审阅场景读取各自已有模型：前一批的四人有 MPFB 试衣 GLB 和内嵌动作，新加入的四人有独立的静态底模及打底短裤。

## 原厂 MPFB 衣件：四人、九套

用 Blender 4.2.1 / MPFB 2.0.18 试装，在 Godot 4.7.2 .NET 的 Forward+ 审阅场景对照同一人的正面、抬臂（0.75 s）、屈膝（2.25 s）和背面。另播放各套 GLB 内嵌的 `MPFB_Pose_Check` 检查换装后的连续动作。

| 角色 | 实测衣件（官方 System Assets） | 观察与设计参考 |
| --- | --- | --- |
| R-05 侦探 | `male_elegantsuit01`、`male_casualsuit05`、`male_casualsuit03` | 西装的翻领、白袖口和腰线贴合侦探轮廓；夹克的前襟、口袋、内领与下摆更适合借鉴叠穿结构；衬衫与牛仔的强对比可换成低饱和内搭。 |
| R-06 霍铎 | `male_casualsuit05`、`male_worksuit01` | 夹克在宽肩上保住了方正肩线，抬臂时弯肘处可见压褶。工装的白内衫、背带扣、胸兜和背部 Y 字背带最适合拿来定分件方案。 |
| R-03 雀儿 | `female_casualsuit02`、`female_sportsuit01` | 短裤让小腿量感和屈膝姿势都好读，近景牛仔纹有明显颗粒。运动短上衣和长裤轮廓干净，现成鞋袜在裤管踝部穿出。 |
| R-10 阮清月 | `female_elegantsuit01`、`female_casualsuit01` | 条纹上衣配素色半裙的分界最清楚；屈膝时裙摆有明显抬升，背面可见开衩。牛仔长裤也与鞋袜穿插，背面尤其明显。 |

雀儿和阮清月在同一背面姿势分别切换 **Show shoe mesh**，关闭后踝部紫灰斑块随鞋袜一起消失，定位为衣物层之间的相交。调试开关保留衣下身体遮罩，所以关闭鞋后脚部也会缺失。制作正式衣件时可给长裤配短袜或独立遮掉袜筒，并预留裤脚与鞋口的间隙。本次八人回归取正面、抬臂、屈膝、侧面和背面 65 张，鞋袜隔离另有 2 张；全动作接触、独立布料和可拆层版型留给定制服装。表里衬衫配裤裙、内搭配夹克或背带等组合均按原资产整体切换，鞋袜另件。

## 体型与动作校验

- R-05 从原烘焙工作台导出试装副本；通过同坐标 HM08 助手网格运行插件的 MHCLO 插值。助手网格与原模型重合、骨骼静置矩阵误差为 0，身体保留 67 个形态键。
- 其余三人各自用前轮的 `human.*-fit.json` 和身高重建同一作者数据。对照原 `*-fit.glb` 逐点检查无遮罩身体、53 骨的名称／层级／静置变换和逆绑定矩阵，六套的最大差均为 0。所有九套的每个原生动作通道（时间、采样值、插值及骨名）与对应人物原 GLB 的 SHA-256 一致。没有重定向。
- 所有试装单独烘焙官方衣物和鞋的 Delete 组，仅遮住衣下身体。`wardrobe-*.json` 另外记录未遮罩身体与衣件的近表面交叠采样，用于跟踪贴合，单位为顶点；可见边缘和衣鞋之间的碰撞由视口检查。服装 Toon 审阅保留资产底色，去掉高频法线。
- Godot MCP 对每个人核对各套的肘、膝四元数（与同人对照组差 < 0.15°），再按 Replay 检查原动作推进。生产角色、主场景、`goal.md` 保持原样。

## 四位静态原模：原打底衣件检查

卢西安、沃德、沈鼎和代管者使用[纯色低模](academy-anatomy-geometry.md)的独立 `anatomy-photo-relief-final/models/*.glb`。四份文件都有独立身体和打底短裤网格，`skins` 和 `animations` 均为空。Godot 直接载入原 GLB，保留眉眼、沈鼎的胡须和原衣件，拍正侧背三面（共 12 张）。只用相机缩放统一 1 m 审阅导出的构图；拼图下排不用于比较角色设定身高。四人的测试范围是静态体态和打底衣件，没有新增 MPFB 外衣或动作。

用 Blender BVH 对身体与打底短裤做三角形相交检查。下表统计至少与身体一片三角形相交的衣件三角形；自交筛查排除了共享几何顶点的三角形对。数值用于定位原版衣件，未修改源网格。

| 人物 | 相交衣件三角形 / 衣件总数 | 观察 |
| --- | ---: | --- |
| 卢西安 | 0 / 571 | 静态未检测到身体与打底衣件相交。 |
| 沃德 | 47 / 693 | 集中于裆与裤脚一带，正面也能看到局部折痕；短裤另有非邻接片自交。 |
| 沈鼎 | 5 / 609 | 相交集中在腰口附近。 |
| 代管者 | 60 / 588 | 集中在裆部区域；短裤另有非邻接片自交。 |

## 复现

沿用[隔离的 Blender/MPFB 配置与官方 System Assets 包](mpfb2-character-test.md#复现)，保留[四人 LOCAL FIT](mpfb2-reference-fit.md#验证与复现)的 `.runtime/mpfb2-fit/{presets,godot}` 和 [R-05 烘焙工作台](mpfb2-style-pilot.md#复现)的 `.runtime/mpfb2-face-fit`。若配置只安装过前轮的一套衣件，从已校验的 `system_cc0.zip` 补齐上表中的 `clothes/<资产 ID>/` 及 `clothes/shoes04/`、`clothes/shoes05/`，保留目录结构，解到隔离配置的 `extensions/.user/user_default/mpfb/data/`。

在仓库根目录运行；每套使用独立 Blender 进程。八人整组回归还需要上述四份静态底模：

```powershell
$p = (Resolve-Path .runtime/mpfb2-test/profile).Path
$env:BLENDER_USER_RESOURCES = $p
$env:BLENDER_USER_CONFIG = Join-Path $p config
$env:BLENDER_USER_SCRIPTS = Join-Path $p scripts
$env:PYTHONDONTWRITEBYTECODE = '1'
$blender = 'C:/Program Files/Blender Foundation/Blender 4.2/blender.exe'
$python = '.runtime/python/Scripts/python.exe'
$out = '.runtime/mpfb2-wardrobe'

foreach ($outfit in 'suit','jacket','shirt') {
  & $blender -b --python-exit-code 1 --python tools/mpfb2_test/wardrobe.py -- `
    --outfit $outfit --source .runtime/mpfb2-face-fit `
    --original-glb assets/characters/mpfb/r05_styled.glb --out $out
  if ($LASTEXITCODE) { throw "R-05: $outfit failed" }
}
foreach ($entry in 'halvard:jacket','halvard:workwear','jane:shorts','jane:sport','qingyue:skirt','qingyue:jeans') {
  $who, $outfit = $entry.Split(':')
  & $blender -b --python-exit-code 1 --python tools/mpfb2_test/wardrobe.py -- `
    --actor $who --outfit $outfit --source .runtime/mpfb2-fit `
    --original-glb ".runtime/mpfb2-fit/godot/$who-fit.glb" --out $out
  if ($LASTEXITCODE) { throw "${who}: $outfit failed" }
}
$static = '.runtime/academy-body-pilot/anatomy-photo-relief-final/models'
& $blender -b --factory-startup --python-exit-code 1 --python tools/mpfb2_test/audit_static_cloth.py -- `
  --source $static --out "$out/static-cloth-audit.json"
& $python -B tools/testing/mpfb_wardrobe.py > "$out/eight-viewport.json"
& $python -B tools/testing/mpfb_wardrobe_sheets.py "$out/eight-viewport.json"
```

手动打开 `res://tools/mpfb2_test/WardrobeReview.tscn`，或用 Game MCP 的 `mpfb_wardrobe` 入口。没有本地生成文件时，对应角色或衣件按钮显示为灰色。`MPFB_WARDROBE_VIEWPORT_PASS` 的 JSON 包含 79 张真实视口截图和日志路径、四份静态源文件审计；各试装回放另等到动作完成。拼图为 `eight-cast-{overview,motion,static}.jpg`。试装 GLB、视口图与各套报告均留在 `.runtime/`。
