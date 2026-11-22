# 《沉睡学院》｜出征制作定稿

其他 AI 从本页进入。[独立 PDF](expedition-handoff.pdf) 用中文解释取舍；[现役文件表](workflow-paths.tsv) 给出逐文件入口、资产注册及测试路径；[仓库路径索引](source-inventory.tsv) 区分交付与本地遗留。索引以仓库根为起点，排除 `.git/`、引擎缓存和忽略项。PDF 内附机器可读索引与历史审计。

## 玩法合同

把公共大厅、折返闸、天文台画在地图固定位置。两个分支层引向同一座闸，闸后再选一个分支层。七张机关房取六张填入东西两线；每次出征实际经过其中三张。约束求解器保证各点可到达，按钮只列当前出口。地图允许预读将来的房间和收益。营地居民自行分配活动；玩家可招募后由队长指挥，也可独行。返程车只在开闸后可选一次，回血后从原闸续程，已领物资、背包、闸门状态都保留。

西侧节点给毛毡，东侧节点给棘轮。毛毡能消除回响或防湿，并在适用房保住更多箱子；棘轮能锁轴，把适用慢通路从 18 分钟缩至 3 分钟。每房限装一件；地图要让玩家有机会把工具留给关底。观测台保持同一装置和动作语法：毛毡→封存，或登记→棘轮→手摇，也可登记→手动制动→手摇。关底“Boss”是一场最终机关考验。游戏时钟与物资是两个不同的收益；当前没有倒计时追杀。

## 制作选择

1. **建筑**：ArchBuilder → Component Library → `catalog.json` → `ComponentFactory`。控制点定形的墙／栏／管归 `line`，重复几何与数学规则归 `rule`，椅柜等复合件归 `assembly`。洞口驱动墙网格和碰撞，窗扇再按挂点装配。详见[调参合同](../../../tools/building_construction/production/README.zh-CN.md)。旧脚本只承担兼容或已有场景专件。
2. **渲染**：选既有大厅 04：原分辨率 Forward+，低饱和 Lowpoly，柔色阶、选择性薄石墨线和 SDFGI。普通墙地和服装统一光响应，窗玻璃、发光和水保留自己的物理响应。门楣、地面转折与机关焦点优先；HUD 独立。详见[Shader、人物和光照](render.md)。正式编号人物有 17 个；R-05 与 fitted rig 只供专项。不会把角色试衣或室内样板当作第二种交付风格。
3. **参考**：[Sol 原始报告与主审取舍](reference-study.md)；[按文件核验的 194 帧和 13 张联系表](study-index/frames.csv)。参照岔路、道具焦点、推理线索出处；不移植卡牌战斗、整屏一位抖动或高密度等距 HUD。外部画面留本机，证据目录只分发本项目画面。
4. **专项**：R2 镜像校对、R5 观察—试重、R7 分批过桥、L03 双视接桥共用“先做安全试验，再改变一个条件”的教学方式。独立接桥的眼位、准入和死亡时序比自动走通更严格；R5 与 R7 未过门禁，均不混入出征牌池。

## 文档树｜只走现役工作流

```text
README.md                             玩家入口、启动、测试
AGENTS.md                             仓库维护、引擎版本与写作约束
mcp/game/README.md                    实机输入、观察与环境
tools/building_construction/production/README.zh-CN.md  建筑分类及调参
docs/handoff/expedition/
   README.md                          本页：执行顺序与分流
   expedition-handoff.pdf             可离线阅读的单文件交接
   render.md                          角色、Shader、照明
   reference-study.md                 视频证据与本项目采用项
   workflow-paths.tsv                 现役接线路径
   source-inventory.tsv               仓库快照；属地登记，非待办清单
   study-index/                       17 份来源 JSON、补录记录、逐帧哈希与时间索引
   evidence/                          两条实机路线、收据、四档同机位、编号人物
   verification.zip                   正式门禁与失败专项的日志
```

历史单独查：[逐页审计](audit-previous.md)、[28 条历史路线的出处与继任](retired-routes.csv)、[上一版 PDF 及其附件](../academy-workflow.pdf)。上次已从启动链退出的 Boot／Web、第一代战役、第三人称回归脚本不进入玩家流程；FreeSO 外部客户端退出启动依赖，原生 XML 地图仍在用。A/B/C 外部来料不再决定生产分类。01–03 大厅、R-05、AcademyCast、L03、十房评测保留对照，不提供另一条发布入口。不要根据文件仍存在就重新接线。

## 复验顺序

在仓库根目录：`dotnet build DualOntologyWorldReconstruct2.csproj` → `dotnet run --project core/rogue_topology/tests/DuelView.RogueTopology.Tests.csproj`。首次检出，用 Godot .NET `--headless --editor --path . --import` 准备资源。下面的每条 `.gd` 路径均用 `--headless --path . --script res://路径` 运行。正式实机启动命令在根 README。

| 检查 | 入口与判据 |
|---|---|
| 种子与库存 | `tools/expedition/route_test.gd`：256 种子各生成两次；检可达、去重、固定锚点及关底三解。 |
| 战役集成 | `tools/test/night_watch.gd -- --no-rule-save`：招募、实体门、三局、一次返营、已领收益与结局。 |
| 真实画面 | `python tools/expedition/viewport_run.py --seed 1 --lane east --out .runtime/expedition-east`；再用 `--seed 2 --lane west --out .runtime/expedition-west`。Python 需项目 MCP 依赖和 Pillow。每局输出六张 1080×720 JPG 与一份 JSON。 |
| 建筑 | `tools/building_construction/tests/production_pipeline_test.gd`，再跑 `tools/test/building_candidate_unit.gd`；七地块装修专项位于开发工作树，日志随附。改墙洞需用射线穿洞并验证两侧实体仍阻挡。 |
| 光照 | `tools/test/room_daylight.gd`，然后用同种子、同眼位复拍营地和折返闸；只允许外窗响应小时。 |
| 专项隔离 | `python -m unittest discover -s core/rule_evaluation -t . -p 'test*.py'`。本轮共 43 项，5 个断言失败、3 个错误；详见 PDF。L03 单独由 `tools/physics_lab/verify_airlock.gd` 检查。 |

**下一次验收**：让首次玩家在不听提示时指出两个出口、说出为何留工具、在结算后说出哪一步保了箱。转头时逐帧查地缝误识、钟前近景裁字、远处鞋与暗墙分离；在目标机记 p50/p95 帧时。这些项目没有用自动通关代签。

补充索引：[26 页纠错稿复审](audit-revision.md)。编号角色核验使用 `tools/expedition/numbered_roster_test.gd`，可用 Headless 或 Forward+；后者另保存独立视口 JPG。发布实机图取自独立检出的交付代码，种子 1 与 2 均在折返后通关。开发中尚未提交的其它房间装饰未计入验收。
