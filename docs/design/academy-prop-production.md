# 学院建筑与物件：资产生产清单

执行入口：ArchBuilder → Props → Open Component Library。`tools/building_construction/catalog.json` 用现有组件 ID 登记生产路径，选中条目时显示路径，悬停可查看当前视觉来源。`mount` 保留安装方向和支撑语义；`production_route` 决定造型工具。新资产通过验收后，再接到对应的现有 ID、GUID 或机关宿主。

| 路径 | 制作范围 | 当前收口 |
| --- | --- | --- |
| A · 参数化建筑 | 墙体、地板、楼梯、平台、固定栏杆、温室承重框、门窗洞口 | 以米控制尺寸和装配点；线脚、饰框、护墙分格和梁柱按建筑结构生成。90° 可见硬边倒角；UV 按米展开，使用可平铺手绘墨线贴图。现有结构登记为待饰面复核。 |
| B · Tripo 文生 3D | 常规椅桌、木箱、麻袋、书堆、瓶罐、花盆等 | 每个提示词描述一个独立物件；静态普通道具 300–1,500 tris。 |
| C · GPT 概念图 → Tripo 图生 3D | 交互机构、特色门扇和窗扇、精细家具、雕像、仪器、线索物 | 概念图先过门禁；有铰接或滑动机构时分出固定件和活动件。近景核心道具 3,000–8,000 tris，活动件有独立物理轴心。 |

同一门窗条目可有 `frame_route: A` 和 `production_route: C`：墙上的通孔和参数化饰框保留为建筑模块，门窗的实体镶件及运动件走 C。水域是环境效果，单独标记。已有 GLB（如礼拜堂长椅、铅条彩窗）列入复核队列；现有脚本道具标为待换模，暂供旧场景使用。**路线标签只登记工作去向；资产质量以截图、导出件和实机操作记录为准。**

## 正式游戏的替换位置

| 组 | 现有绑定 | 换模边界 |
| --- | --- | --- |
| Native lot 木椅与通用家具 | `scenes/rogue_view/CatalogSilhouette.gd::populate` 及 `content/academy_lots/*.xml` 中的 GUID；另核对 ArchBuilder 的家具 ID | 保留 lot 的存在性、地格、朝向和碰撞。木椅先换 `0x5DEA43F0`；扶手椅 `0x68EA432A` 单独验收。 |
| 厨房炉台、台面、架子与传菜闸 | `scenes/rogue_view/render/HotKitchen.gd`、`content/archbuilder/hot-kitchen.json` | 台面锚点不变。炉门、冷藏门、传菜闸分别保有轴线或滑轨、接触目标和机械限位；按钮模型交给 `PhysicalButton`，触发规则留给厨房。 |
| Hall / Vesper | `scenes/blue_prince_lab/doors/`、`gears/`、`studies/` 及 `vesper/` | 对照每个现有的铰链、齿轮、指针和档位信号。活动前后的根节点、碰撞和完成信号保持稳定。 |
| 西翼、仪器图册（如已安装） | `scenes/mechanisms/`、`scenes/instrument_folio/` | 按房间或页面核对真实操纵件；独立保留折射、投影、轨迹等规则可视化。 |

## 首批物件物理规格单

### B-01 · 学院木椅

- **交付目标**：`assets/props/academy/academy_side_chair.glb`，先接 Native lot `0x5DEA43F0`。宽 0.46 × 深 0.49 × 高 0.88 m；座面约 0.45 m 高。深染白蜡木，四腿、座板、座框、横撑和三条竖靠背均固定。留出可看穿的腿间和靠背缝隙。
- **引擎接口**：四脚底面中心为根原点，+Y 向上，坐姿朝 -Z；原始 lot 朝向外层处理。弱化纹理噪声，保住椅脚接地与榫接轮廓。安排简化碰撞代理，保持原 lot 格位。
- **网页进度**：Tripo Studio → 3D Workspace → Model → Text，提示词已填，等待账号登录。生成前检查账户额度及 Privacy 选项。

**Tripo Text-to-3D（英文）**

> One isolated four-legged academy side chair, 46 cm wide, 49 cm deep and 88 cm high; seat at 45 cm. Dark stained ash wood, square tapered legs, exposed mortise-and-tenon seat rails, low side stretchers, solid softly beveled wooden seat and three upright back splats under a shaped crest rail. 1900s vintage design, stylized graphic-novel low-poly 3D game prop, chunky readable silhouette, crisp beveled edges, hand-painted muted wood grain and subtle dark ink contour lines. Clear air gaps between legs and splats, same finish front and back. Single object, no plinth, no upholstery, no text, no scene, no floating details.

### C-01 · 厨房传菜闸按钮

- **交付目标**：`assets/props/academy/serving_shutter_button.glb`。目录基准宽 0.32 × 高 0.28 × 出墙 0.105 m；厨房现有宿主另有 1.25 倍规格。暗黄铜背板用四角一字螺丝固定在墙上；发黑铸铁壳体内有套筒和圆形凹井。活动件为暗红珐琅圆帽及钢柱塞，钢杆直径约 0.108 m、帽径约 0.156 m。帽和壳保留足够装配间隙。
- **引擎接口**：`PhysicalButton_Root/Body_Static` 和 `PhysicalButton_Root/Button_Cap_Moving` 两个分支；根原点为背板贴墙中心。为了复用原 `PhysicalButton.pulse()` / `set_depressed()`，模型 +Y 沿安装面外法线，由安装宿主转到竖直墙面；活动件的原点在套筒滑轨中心线上。运动轴为本地 Y，位移 `0 → -0.023 m → 0`（目录基准）。移动时帽和钢柱塞一起走，套筒和四颗螺丝固定。按钮使用独立拾取代理，传菜闸保持原有导轨和状态逻辑。
- **网页进度**：两份 GPT 生图要求已就绪；等概念图视觉过门后，再分别进入 Tripo 的 Image-to-3D。先维持零件独立，DCC 内按轴装配。

**GPT 概念图 1：固定件**

> One stationary housing only for a 1903 academy kitchen wall-mounted mechanical pushbutton, 320 mm wide, 280 mm tall, 80 mm deep. A thick rectangular aged dark-brass backplate with crisp chamfered edges and exactly four inset slotted screws, supporting a smaller blackened cast-iron housing. A deep round recessed well with a rigid internal steel guide sleeve and one clearly open central bore for a separate plunger. Readable wall contact thickness, hardware seats and wear at the bevels. No cap, no plunger, no wire, no lock, no lettering. Single object fully in frame, front three-quarter view showing front, top and right side with generous margins. Flat neutral gray #808080, evenly diffuse shadowless light, zero cast shadow or halo. Graphic-novel low-poly design, hand-painted muted metal, restrained ink contour and subtle hatching, no gloss flare or photographic noise.

**GPT 概念图 2：活动件**

> One separate mechanical pushbutton plunger only for the same 1903 academy kitchen fixture. A stout circular dark oxblood enamel cap, 156 mm in diameter, crisp edge bevel and three shallow embossed grip ribs; a concentric turned-steel rear stem, 108 mm in diameter, with a shallow retaining shoulder. The stem extends from the back of the cap; tilt the part as a whole so the rear stem and the cap face are both legible in the three-quarter view. One mechanical part, no mounting panel, no wire, no words. Uncropped and centered with generous margins on perfectly flat neutral gray #808080. Fully diffuse even shadowless light, no cast shadow, halo or glossy glare. Styled as a hand-painted low-poly graphic-novel prop, muted aged metal and enamel, restrained dark ink edges and light hatching.

## 人工验收与归档

1. **参考图**：核对尺寸比例、轮廓、螺丝和套筒、活动间隙；确认 3/4 构图完整、平灰背景、无投影或脏黑。合格图才上传。一次只用该零件的合格参考图。
2. **Tripo 模型**：在网页检查正面、侧面、背面、45° 俯视；看背面连接、真实机械空腔和贴图。记录可用的拓扑、面数、PBR 和可见性设置。问题模型退回生成阶段，原始下载先放 `.runtime/prop-production/`。
3. **DCC**：核对米制包围盒和接触面，应用 Scale `(1, 1, 1)`；清重合点和无用内部面、统一外侧法线、在面数预算里保留倒角。分别检查 Base Color、Roughness、Metallic；导出 GLB 原点和节点树。碰撞代理单独维护；透明与活动关节的接触面保留实际需要的几何。
4. **引擎**：组内比较比例和墨线；手动看四角度、接地/贴墙、不同安装方向。活动件操作到两个限位，检查留缝、回程、碰撞和机关输出的实机结果。确认后将 GLB、来源/导出设置、节点名、尺寸、轴和限位一起登记；替换已验收的对应视觉，保留游戏绑定。
