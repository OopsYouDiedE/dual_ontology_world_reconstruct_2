# 战役渲染交接 · 候选 04

## 选型和正式接入

沿用 04 的柔色阶、薄墨线和 SDFGI。原始 Forward+ 大厅对照在 `.runtime/art-convergence-20261122/look-contact-sheet.jpg`：01 的柱面过渡连续，02 把亮暗面分得更清，03 增加柱础和墙角的轮廓，04 加入 SDFGI 后，门洞、柱础和连续拱之间的距离最好读。

正式证人由 `HallWitnesses → Roster.attach → ImportedCharacter.attach` 加载已提交的 `UserModels/model_01.glb` 至 `model_17.glb`。编号 06 是 detective，其余为 Roster 的 16 名人物。导入器在原有的逐 surface 材质适配处为编号模型启用 `expedition_soft_toon`，混合量 `0.58`。沿用原贴图、底色、UV、顶点色、单双面分流与薄高光。AcademyCast 的五套 fitted rig 是另一条人物路径，本地曾试接同一柔色阶函数；旧前厅图中的 AcademyCast Detective 是该路径的试样。

## 生产 shader 分类

统一放在 `scenes/components/rendering/` 下的功能目录：

| 目录 | 作用与边界 |
| --- | --- |
| `surfaces/` | `AcademyTile` 负责石地、灰泥、护墙和陶砖，保留接缝、风化、法线细节及粗糙度输出。`KitchenFinish` 留在这一类，保留木作和带金属度饰面的响应。 |
| `actors/` | `ChibiFigurineSurface` / `ChibiFigurineDoubleSided` 共用 `FigurinePaint`，编号角色使用柔色阶，其它使用该导入器的角色保留原有着色曲线。`CastDielectric` 用于 AcademyCast 的服装、皮革和皮肤；眼球和裁切发片保留原材质。 |
| `post/` | `HallInk` 根据深度断点与法线折角乘色，以距离衰减和高光减墨控制覆盖。战役 viewport 强度 `0.40`；大厅实验保留原值。 |
| `feedback/` | `NightVeil` 继续承担夜巡状态反馈，和场景材质及 3D 调色分开。 |

`surfaces/SoftToonLight.gdshaderinc` 是公共直射光响应。`toon_on` 控制是否启用，`toon_strength` 默认 `0.86`，`two_tone` 默认关闭，`stone_sheen` 默认 `0`，用于可选的低幅高光。函数只对 `N·L` 分带，灯光色、距离衰减和投影保持连续。玻璃、水和发光表面继续使用原有专用响应。

## 光照和调色

主战役 expedition `RogueRoomView` 给自己的 3D Environment 启用统一 `adjustment_saturation = 0.76`，覆盖营地、return-junction 和同一房间视口内的其它 3D 画面。HUD、俯视图、提示与画布反馈保持自己的色彩。继续使用原 SDFGI 和曝光配置；普通主灯近中性，灯罩和炉火保留局部暖色。室内灯与炉火按 mood，外窗单独按时钟驱动。内窗与传菜口仍不引入时钟光。

## 核验

- 独立实验使用正式 `HallWitnesses.sync()` 实例化并读取 17 人实际的 `get_active_material()`。编号 01–17 各自唯一的 mesh surface 都使用 `actors/` 下的正式 shader，且读取到 `expedition_soft_toon=true`、`toon_strength=0.58`。Headless 和 RTX 3070 Forward+ 均通过。证据：`.runtime/expedition-render/numbered-headless.log`、`numbered-forward.log`、`numbered-roster-04.jpg`（1080×720）。
- 旧前厅带墨与关墨的同机位独立对照已经中央裁切为 1080×720 JPG：`.runtime/expedition-render/foyer-04.jpg`、`foyer-no-ink.jpg`。它们用于对照墨线；编号角色和新版调色以 `numbered-roster-04.jpg` 为准。
- 外窗昼夜逻辑由 `tools/test/room_daylight.gd` 验证。独立实验确认 SDFGI、战役墨线与调色参数已加载；正式入口另从独立检出的代码用种子 1、2 走通，见 `evidence/east/`、`evidence/west/`。营地角色可凭头肩外形区分，部分衣服贴入暗影；折返点的暖钟面清楚，天花很暗。候选大厅的拱廊不是当前营地的装修。
