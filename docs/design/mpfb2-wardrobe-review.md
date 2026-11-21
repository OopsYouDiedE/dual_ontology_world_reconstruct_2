# 学院八人审阅：原始模型与 MPFB 试衣

[学院八位重点人物](academy-featured-character-export.md#本轮名单)现均使用各自的 MPFB 模型与内嵌验姿动作。卢西安、沃德、沈鼎、代管者由新 MPFB 配方生成，在本地审阅场景替换上一轮的静态底模。侦探、霍铎、雀儿、阮清月沿用已验收的模型。

## 原厂衣件：八人、十三组试装

用 Blender 4.2.1 / MPFB 2.0.18 试装，在 Godot 4.7.2 .NET 的 Forward+ 审阅场景对照同一人的正面、抬臂（0.75 s）、屈膝（2.25 s）和背面。另播放各套 GLB 内嵌的 `MPFB_Pose_Check` 检查换装后的连续动作。

| 角色 | 实测衣件（官方 System Assets） | 观察与设计参考 |
| --- | --- | --- |
| R-05 侦探 | `male_elegantsuit01`、`male_casualsuit05`、`male_casualsuit03` | 西装的翻领、白袖口和腰线贴合侦探轮廓；夹克的前襟、口袋、内领与下摆更适合借鉴叠穿结构；衬衫与牛仔的强对比可换成低饱和内搭。 |
| R-06 霍铎 | `male_casualsuit05`、`male_worksuit01` | 夹克在宽肩上保住了方正肩线，抬臂时弯肘处可见压褶。工装的白内衫、背带扣、胸兜和背部 Y 字背带最适合拿来定分件方案。 |
| R-03 雀儿 | `female_casualsuit02`、`female_sportsuit01` | 短裤让小腿量感和屈膝姿势都好读，近景牛仔纹有明显颗粒。运动短上衣和长裤轮廓干净，现成鞋袜在裤管踝部穿出。 |
| R-10 阮清月 | `female_elegantsuit01`、`female_casualsuit01` | 条纹上衣配素色半裙的分界最清楚；屈膝时裙摆有明显抬升，背面可见开衩。牛仔长裤也与鞋袜穿插，背面尤其明显。 |
| R-01 卢西安 | `male_casualsuit03` | 条纹衬衫与牛仔裤验姿。 |
| R-04 沃德 | `male_elegantsuit01` | 正式西装验肩线、袖口和肘部。 |
| R-07 沈鼎 | `male_worksuit01` | 背带工装验厚腰腹的衣身空间。 |
| 代管者 | `male_elegantsuit01` | 正式西装作为活动测试服，角色设定中的燕尾服仍属独立服装设计。 |

雀儿和阮清月在同一背面姿势分别切换 **Show shoe mesh**，关闭后踝部紫灰斑块随鞋袜一起消失，定位为衣物层之间的相交。调试开关保留衣下身体遮罩，所以关闭鞋后脚部也会缺失。制作正式衣件时可给长裤配短袜或独立遮掉袜筒，并预留裤脚与鞋口的间隙。本次八人回归取正面、抬臂、屈膝、侧面和背面 105 张，鞋袜隔离另有 2 张；全动作接触、独立布料和可拆层版型留给定制服装。表里衬衫配裤裙、内搭配夹克或背带等组合均按原资产整体切换，鞋袜另件。

## 体型与动作校验

- R-05 从原烘焙工作台导出试装副本；通过同坐标 HM08 助手网格运行插件的 MHCLO 插值。助手网格与原模型重合、骨骼静置矩阵误差为 0，身体保留 67 个形态键。
- 其余七人各自用 `human.*-fit.json` 和试装身高重建同一作者数据。对照原 `*-fit.glb` 逐点检查无遮罩身体、53 骨的名称／层级／静置变换和逆绑定矩阵，十组的最大差均为 0。所有十三组的每个原生动作通道（时间、采样值、插值及骨名）与对应人物原 GLB 的 SHA-256 一致。没有重定向。
- 所有试装单独烘焙官方衣物和鞋的 Delete 组，仅遮住衣下身体。`wardrobe-*.json` 另外记录未遮罩身体与衣件的近表面交叠采样，用于跟踪贴合，单位为顶点；可见边缘和衣鞋之间的碰撞由视口检查。服装 Toon 审阅保留资产底色，去掉高频法线。
- Godot MCP 对每个人核对各套的肘、膝四元数（与同人对照组差 < 0.15°），再按 Replay 检查原动作推进。生产角色、主场景、`goal.md` 保持原样。

## 新增四位的 MPFB 造型配方

| 人物 | 人物卡年龄 | 试装身高 | Muscle | 轮廓与面部方向 |
| --- | --- | ---: | ---: | --- |
| 卢西安 | 21 | 179 cm | 0.44 | 瘦长，略收肩和胸廓；窄长颅形、下巴渐收。 |
| 沃德 | 38 | 180 cm | 0.56 | 宽肩、方下颌、短宽头形；四位中肩关节距离最大（41.0 cm）。 |
| 沈鼎 | 44 | 175 cm | 0.64 | 厚胸背、发力前臂、圆面宽颌；保留腰腹体积，试装腰线 87.9 cm。 |
| 代管者 | 成年人外观，无人类年龄 | 184 cm | 0.40 | 窄体态、高颅、长而收的下巴与纤细手指；MPFB 年龄滑块以 38 岁外观为输入。 |

身高为本轮审阅尺寸。`featured-fit-receipt.json` 记载实际局部目标、身高和横截面数据。四位当前是带各自骨架、眼件与内嵌测试动作的初版光头；定制发件、沈鼎的胡须、代管者的琥珀竖瞳与燕尾服另行制作。八人组使用同机位、同灯光对照。上一轮审阅用的四份静态 GLB 及对应 `.blend` 已从 `anatomy-photo-relief-final/models/` 移除；历史参考图与审计记录保留。

## 复现

沿用[隔离的 Blender/MPFB 配置与官方 System Assets 包](mpfb2-character-test.md#复现)，保留[四人 LOCAL FIT](mpfb2-reference-fit.md#验证与复现)的 `.runtime/mpfb2-fit/{presets,godot}` 和 [R-05 烘焙工作台](mpfb2-style-pilot.md#复现)的 `.runtime/mpfb2-face-fit`。若配置只安装过前轮的一套衣件，从已校验的 `system_cc0.zip` 补齐上表中的 `clothes/<资产 ID>/` 及 `clothes/shoes04/`、`clothes/shoes05/`，保留目录结构，解到隔离配置的 `extensions/.user/user_default/mpfb/data/`。

在仓库根目录运行。`--featured-additions` 只生成新增四位，不重写老四位；每套试衣使用独立 Blender 进程：

```powershell
$p = (Resolve-Path .runtime/mpfb2-test/profile).Path
$env:BLENDER_USER_RESOURCES = $p
$env:BLENDER_USER_CONFIG = Join-Path $p config
$env:BLENDER_USER_SCRIPTS = Join-Path $p scripts
$env:PYTHONDONTWRITEBYTECODE = '1'
$blender = 'C:/Program Files/Blender Foundation/Blender 4.2/blender.exe'
$python = '.runtime/python/Scripts/python.exe'
$out = '.runtime/mpfb2-wardrobe'

& $blender -b --python-exit-code 1 --python tools/mpfb2_test/muscle.py -- `
  --out .runtime/mpfb2-fit --design-fit --featured-additions
if ($LASTEXITCODE) { throw 'Featured MPFB model build failed' }

foreach ($outfit in 'suit','jacket','shirt') {
  & $blender -b --python-exit-code 1 --python tools/mpfb2_test/wardrobe.py -- `
    --outfit $outfit --source .runtime/mpfb2-face-fit `
    --original-glb assets/characters/mpfb/r05_styled.glb --out $out
  if ($LASTEXITCODE) { throw "R-05: $outfit failed" }
}
foreach ($entry in 'halvard:jacket','halvard:workwear','jane:shorts','jane:sport','qingyue:skirt','qingyue:jeans',`
                   'lucian:shirt','ward:suit','shending:workwear','caretaker:suit') {
  $who, $outfit = $entry.Split(':')
  & $blender -b --python-exit-code 1 --python tools/mpfb2_test/wardrobe.py -- `
    --actor $who --outfit $outfit --source .runtime/mpfb2-fit `
    --original-glb ".runtime/mpfb2-fit/godot/$who-fit.glb" --out $out
  if ($LASTEXITCODE) { throw "${who}: $outfit failed" }
}
& $python -B tools/testing/mpfb_wardrobe.py > "$out/eight-mpfb-viewport.json"
& $python -B tools/testing/mpfb_wardrobe_sheets.py "$out/eight-mpfb-viewport.json"
```

手动打开 `res://tools/mpfb2_test/WardrobeReview.tscn`，或用 Game MCP 的 `mpfb_wardrobe` 入口。没有本地生成文件时，对应角色或衣件按钮显示为灰色。`MPFB_WARDROBE_VIEWPORT_PASS` 的 JSON 包含 107 张真实视口截图和日志路径；各试装回放另等到动作完成。拼图为 `eight-mpfb-overview.jpg` 和 `four-new-mpfb-{body,motion}.jpg`。试装 GLB、视口图与各套报告均留在 `.runtime/`。
