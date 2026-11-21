# 学院八人审阅：原始模型与 MPFB 试衣

[学院八位重点人物](academy-featured-character-export.md#本轮名单)现均使用各自的 MPFB 模型与内嵌验姿动作。卢西安、沃德、沈鼎、代管者由新 MPFB 配方生成，在本地审阅场景替换上一轮的静态底模。侦探、霍铎、雀儿、阮清月沿用已验收的模型。

## 衣件：八人、十七组试装

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

雀儿和阮清月在同一背面姿势分别切换 **Show shoe mesh**，关闭后踝部紫灰斑块随鞋袜一起消失，定位为衣物层之间的相交。调试开关保留衣下身体遮罩，所以关闭鞋后脚部也会缺失。制作正式衣件时可给长裤配短袜或独立遮掉袜筒，并预留裤脚与鞋口的间隙。本次八人回归取正面、抬臂、屈膝、侧面和背面 125 张，鞋袜隔离另有 2 张；全动作接触、独立布料和可拆层版型留给定制服装。表里衬衫配裤裙、内搭配夹克或背带等组合均按原资产整体切换，鞋袜另件。

## 体型与动作校验

- R-05 从原烘焙工作台导出试装副本；通过同坐标 HM08 助手网格运行插件的 MHCLO 插值。助手网格与原模型重合、骨骼静置矩阵误差为 0，身体保留 67 个形态键。
- 其余七人各自用 `human.*-fit.json` 和试装身高重建同一作者数据。对照原 `*-fit.glb` 逐点检查无遮罩身体、53 骨的名称／层级／静置变换和逆绑定矩阵，十四组的最大差均为 0。所有十七组的每个原生动作通道（时间、采样值、插值及骨名）与对应人物原 GLB 的 SHA-256 一致。没有重定向。
- 所有试装单独烘焙官方衣物和鞋的 Delete 组，仅遮住衣下身体。`wardrobe-*.json` 另外记录未遮罩身体与衣件的近表面交叠采样，用于跟踪贴合，单位为顶点；可见边缘和衣鞋之间的碰撞由视口检查。服装 Toon 审阅保留资产底色，去掉高频法线。
- Godot MCP 对每个人核对各套的肘、膝四元数（与同人对照组差 < 0.15°），再按 Replay 检查原动作推进。生产角色、主场景、`goal.md` 保持原样。

## 新增四位的 MPFB 造型配方

| 人物 | 人物卡年龄 | 试装身高 | Muscle | 轮廓与面部方向 |
| --- | --- | ---: | ---: | --- |
| 卢西安 | 21 | 179 cm | 0.44 | 瘦长，略收肩和胸廓；窄长颅形、下巴渐收。 |
| 沃德 | 38 | 180 cm | 0.56 | 宽肩、方下颌、短宽头形；四位中肩关节距离最大（41.6 cm）。 |
| 沈鼎 | 44 | 175 cm | 0.64 | 厚胸背、发力前臂、圆面宽颌；保留腰腹体积，试装腰线 88.8 cm。 |
| 代管者 | 成年人外观，无人类年龄 | 184 cm | 0.40 | 窄体态、高颅、长而收的下巴与纤细手指；MPFB 年龄滑块以 38 岁外观为输入。 |

身高为本轮审阅尺寸。`featured-fit-receipt.json` 记载实际局部目标、身高和横截面数据。四位当前是带各自骨架、眼件与内嵌测试动作的初版光头；定制发件、沈鼎的胡须与代管者的燕尾服另行制作。八人组使用同机位、同灯光对照。上一轮审阅用的四份静态 GLB 及对应 `.blend` 已从 `anatomy-photo-relief-final/models/` 移除；历史参考图与审计记录保留。

### 面部细化与原型混合

这四位启用各自的 MPFB Phenotype 混合，并叠加独立眼睑、鼻梁、鼻尖、颧骨、嘴唇和颌部目标。下表使用插件参数名与顺序，数值是制模形态权重；人物卡里的出生地与身份设定沿用原文。肤色独立选色，试装不沿用纹理化皮肤。

| 角色 | `asian / caucasian / african` | 近景辨识点 |
| --- | --- | --- |
| 卢西安 | `0.14 / 0.77 / 0.09` | 窄长脸、收下巴、较开眼裂、灰眼。 |
| 沃德 | `0.11 / 0.72 / 0.17` | 宽方下颌、重上眼睑、略隆的鼻梁、较薄上唇、蓝绿色虹膜。 |
| 沈鼎 | `0.83 / 0.11 / 0.06` | 饱满脸颊、圆宽颌、较宽鼻尖、柔和鼻梁、棕眼。 |
| 代管者 | `0.31 / 0.55 / 0.14` | 高窄颅形、长而窄的下颌、清晰颧骨、窄鼻尖与琥珀竖瞳；用官方眼 UV 生成独立虹膜贴图。 |

审阅场景可切 **Face / Face profile**。若同角色上一版 GLB 存在 `.runtime/mpfb2-wardrobe/face-before/`，可用 **Previous face** 在同光位、同正交尺寸比较；某角色无旧版时，仅拍新版。新版预设序列化后核对 Phenotype 权重，试装重新读取这份预设并核对无遮罩体型、绑定和动作采样。

### 衣服下的轮廓

四位各加一组共用版型 **Fitted T-shirt**：用 `male_casualsuit06` 的短袖与裤件，给两片连通网格分别上低对比素色；袖口露出上臂，去掉条纹和高对比洗色。只在腰腹与肋部收多余松量，向原身体表面靠近最多 13 mm，目标静态余量 12 mm，保留领口、袖口和下摆的原版型。这个试样用于对照体态，正式外套仍可保留其衣身厚度。

同机位对照身体涂色试衣、原套装和短袖版。四位肩关节距离依序为 37.9 / 41.6 / 37.4 / 37.6 cm，腰线 77.6 / 84.8 / 88.8 / 79.8 cm。沃德的上身更横向展开，沈鼎的腰腹前后体积和前臂更明显；卢西安和代管者以相对较窄的腰肩及不同的脸颌、头身区分。衣服收版数值在各 `wardrobe-*_fitted.json` 的 `silhouette_fit` 中。

## 复现

沿用[隔离的 Blender/MPFB 配置与官方 System Assets 包](mpfb2-character-test.md#复现)，保留[四人 LOCAL FIT](mpfb2-reference-fit.md#验证与复现)的 `.runtime/mpfb2-fit/{presets,godot}` 和 [R-05 烘焙工作台](mpfb2-style-pilot.md#复现)的 `.runtime/mpfb2-face-fit`。若配置只安装过前轮的一套衣件，从已校验的 `system_cc0.zip` 补齐上表中的 `clothes/<资产 ID>/`、`clothes/male_casualsuit06/` 及 `clothes/shoes04/`、`clothes/shoes05/`，保留目录结构，解到隔离配置的 `extensions/.user/user_default/mpfb/data/`；眼件所需 `eyes/materials/` 含 `grey`、`bluegreen`、`brown` 和 `brownlight` 色图。

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
                   'lucian:shirt','ward:suit','shending:workwear','caretaker:suit',`
                   'lucian:fitted','ward:fitted','shending:fitted','caretaker:fitted') {
  $who, $outfit = $entry.Split(':')
  & $blender -b --python-exit-code 1 --python tools/mpfb2_test/wardrobe.py -- `
    --actor $who --outfit $outfit --source .runtime/mpfb2-fit `
    --original-glb ".runtime/mpfb2-fit/godot/$who-fit.glb" --out $out
  if ($LASTEXITCODE) { throw "${who}: $outfit failed" }
}
& $python -B tools/testing/mpfb_wardrobe.py > "$out/face-and-fit-viewport.json"
& $python -B tools/testing/mpfb_wardrobe_sheets.py "$out/face-and-fit-viewport.json"
```

手动打开 `res://tools/mpfb2_test/WardrobeReview.tscn`，或用 Game MCP 的 `mpfb_wardrobe` 入口。没有本地生成文件时，对应角色或衣件按钮显示为灰色。`MPFB_WARDROBE_VIEWPORT_PASS` 的 JSON 包含 真实视口截图和日志路径；各试装回放另等到动作完成。有前版 GLB 时共拍 143 张。新增对照拼图为 `four-face-detail.jpg`、`four-silhouette-fit.jpg` 和 `four-fitted-motion.jpg`。试装 GLB、视口图与各套报告均留在 `.runtime/`。

## 八人二轮微调及 UV 改绘

本轮生成独立的 `.runtime/mpfb2-detail/` 审阅副本，保留八人原有身高、宏观肌肉和肤色配置。沿用各自 LOCAL FIT 的局部目标并累加小幅修正，重新按各自身体生成骨架、按原姿势脚本原生烘焙；没有跨人物重定向。R-05 另走自己的风格化工作台，保留发块、服饰、柔化法线、烘焙底色和 67 个面部形态键。Game MCP 可切 **Trial clothes / Refined body**；全员支持 **Face / Face profile**。

| 角色 | 本轮轮廓重点 | 面部重点 |
| --- | --- | --- |
| 侦探 | 稍收腰、加强胸和前臂 | 鼻尖略窄、下巴前推、上眼轮廓微调 |
| 霍铎 | 肩关节跨度 +0.58 cm，增厚颈和小腿 | 宽下颌、短下巴、鼻尖更宽 |
| 雀儿 | 小腿围 +1.16 cm，增强大腿和腰部量感 | 圆颊、短下巴、眼裂更开 |
| 阮清月 | 腰线 −2.50 cm，缩胸廓深度、拉长颈线 | 窄下巴和鼻梁、纵向拉长脸形 |
| 卢西安 | 肩关节跨度 −0.41 cm，收薄胸廓和上臂 | 收下颌，保留一点颊部体积 |
| 沃德 | 肩关节跨度 +1.81 cm，上臂围 +1.09 cm | 方下颌、强调颧骨 |
| 沈鼎 | 腰线 +2.11 cm，增厚胸背和前臂 | 丰颊、鼻尖略宽 |
| 代管者 | 肩关节跨度 −1.22 cm，拉长颈和指节 | 更长的下巴和内收脸颊，保留竖瞳 |

### 服装改绘验证

本机 MPFB 2.0.18 的 `MaterialService` 在游戏材质中把 `.mhmat` 的 `diffuseTexture` 接到 Principled Base Color；MHCLO 负责衣件的贴体映射。已有衣件保留 UV 和版型，复制原始贴图，在 Blender **Texture Paint** 里用 UV 布局或直接在模型上绘制，保存 sRGB PNG 再替换 Base Color。需要在 MPFB 资产库复用时，给项目自己的副本保存新 `.mhmat` 配置；这次原始 CC0 衣件和插件代码均保持原样。

- **R-05 `male_casualsuit05`**：叠穿夹克改为铁锈帆布，保留领襟和袋口分色；浅麻色条纹内搭、灰蓝裤，补画背部双针迹。
- **R-10 `female_elegantsuit01`**：象牙色底配冷色细条纹，墨蓝半裙增加两道弧形裙边。屈膝时裙边随原网格变形。
- `repaint_wardrobe.py` 用相同 UV 的 PNG 替换 GLB 中的 Base Color 图像。每套除目标图像外，所有二进制 bufferView 逐字节相同（包括网格、UV、蒙皮、动画和其他贴图）；`repaint-receipt.json` 记录检查结果。实机对照切 **Stock color / Academy repaint**，两套均检查抬臂、屈膝并回放到结束。
- 缝线、印花、口袋分色、内外搭的材质区分适合用贴图。增加实际衣层、改变衣长和翻领轮廓、制作可拆外套、去鞋袜穿插需要改衣件网格并重新试装。在 Blender 中完成版型和 UV 后，可用 MPFB **MakeClothes** 构建项目的贴体衣件；正式衣件的层叠与碰撞仍需在人物自己的动作里验收。

沿用上一节的环境和旧版本地模型，执行以下命令：

```powershell
$d = '.runtime/mpfb2-detail'
& $blender -b -t 8 --python-exit-code 1 --python tools/mpfb2_test/muscle.py -- `
  --out $d --design-fit --detail-pass
if ($LASTEXITCODE) { throw 'Refined body build failed' }
& $blender -b -t 8 --python-exit-code 1 --python tools/mpfb2_test/style_pilot.py -- `
  --out "$d/r05" --presets "$d/presets" --detail-pass
if ($LASTEXITCODE) { throw 'Refined R-05 style build failed' }
& $blender -b -t 8 --python-exit-code 1 --python tools/mpfb2_test/wardrobe.py -- `
  --actor r05 --outfit jacket --source "$d/r05" --original-glb "$d/r05/r05-styled.glb" --out $d
if ($LASTEXITCODE) { throw 'R-05 jacket fit failed' }
& $blender -b -t 8 --python-exit-code 1 --python tools/mpfb2_test/wardrobe.py -- `
  --actor qingyue --outfit skirt --source $d --original-glb "$d/godot/qingyue-fit.glb" --out $d
if ($LASTEXITCODE) { throw 'R-10 skirt fit failed' }
& $python -B tools/mpfb2_test/repaint_wardrobe.py $d
if ($LASTEXITCODE) { throw 'Wardrobe repaint failed' }
& $python -B tools/testing/mpfb_wardrobe.py --detail > "$d/detail-viewport.json"
if ($LASTEXITCODE) { throw 'Detail viewport regression failed' }
& $python -B tools/testing/mpfb_wardrobe_sheets.py "$d/detail-viewport.json"
```

`MPFB_DETAIL_VIEWPORT_PASS` 报告包含旧／新体型、面部与服装的 112 张实机图。交付拼图包括 `eight-detail-{front,side,back,portrait}.jpg`、`body-before-after-{first,second}.jpg`、`wardrobe-repaint.jpg`，单独的 UV 改绘 PNG 可直接导回 Blender。
