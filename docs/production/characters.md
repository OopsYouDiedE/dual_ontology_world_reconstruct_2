# 人物｜一套写实 6.5 头身制作管线

正式大厅、出征伙伴、沿途居民和暗房留影共用 [Roster](../../scenes/rogue_crossing/Roster.gd) → [ProductionCast](../../scenes/rogue_crossing/ProductionCast.gd) → **6.5 头身 GLB + CastDielectric Toon**。角色 ID、职业、证词、招募和行动规则沿用原数据；旧编号小人及其手办材质已退出运行与测试。

| 项目 | 约定 |
|---|---|
| 比例 | 中立直立、赤足。身高除以颏底到裸颅顶的高度为 **6.5**；发型、帽饰和鞋底不计。提交测量记录。统一缩放只改变身高。 |
| 造型与材质 | 依锁骨、肘、腰和膝重新安排衣片；发型、外套轮廓和主色承担远景辨识。按[正式美术](art.md)处理 Toon 明暗。 |
| 绑定与动作 | 同一骨架和播放协议统一站立、行走、跑步和短时操作。新增独立体型或坐姿时，核对脚底接地、手到交互点及衣领袖口穿插。 |
| 关卡接入 | 保留角色 ID；在营地招募和出征/折返回归中核对身份。所有最终导入的角色走同一个加载器，服装变体有自己的材质配方。 |

[侦探](../../assets/characters/toon_cast/detective-6p5.glb)是实测基模，由[生成器](../../tools/detective_study/build_detective.py)读取 Blender Studio Human Base Meshes v1.3.0 的 Realistic Male Body（CC0）。[测量记录](../../assets/characters/toon_cast/detective-measurement.json)：身高 177.00 cm、头高 27.23 cm，6.5000 头身。当前 16 名居民先共享这个基模和动作库，用身高、外套／马甲配色和名牌辨认；独立脸型、服装剪裁与完整动作是后续角色美术工作。

![6.5 头身侦探的静态三视图](media/detective-toon.jpg)
