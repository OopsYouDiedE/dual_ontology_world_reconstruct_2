# 制作入口｜沉睡学院

从玩家能走的那条路组织工作：营地决定队伍和路线，房间让物资变成解题手段，固定的天文台检验一路的选择。正式制作分四层：**《蓝图王子》主导第一人称画面，《巴别塔圣歌》补充建筑色面；《邪恶冥刻》主导房间连接与事件节奏；单房布局按空间问题选参考；所有正式人形使用写实 6.5 头身。** 仓库内的专项实验另行验证。

```text
README.md                                         启动游戏与玩家操作
AGENTS.md                                         仓库维护与提交约束
docs/production/
  README.md                                       制作入口（本页）
  gameplay.md                                     《邪恶冥刻》式分支、汇合与事件节奏
  layout.md                                       单房动线、楼层与白盒
  art.md                                          房间构图、色面、Shader 和后处理
  characters.md                                   写实 6.5 头身与逐人替换
  media/detective-toon.jpg                        首件静态三视图
  verification.md                                 逻辑、资产、实机三层验证
tools/building_construction/production/README.zh-CN.md  建筑生成、参数与装配
mcp/game/README.md                                实机输入与观察协议
docs/research/expedition/
  README.md                                       参考游戏的画面与取舍
  frames.csv                                      本地研究帧尺寸、哈希依索引复核
  sources/                                        商店视频与采样时间清单
```

| 要交付的东西 | 从这里开始 | 通过什么验收 |
|---|---|---|
| 可玩的一个分支 | [路线](gameplay.md) | 门前读得懂收益；图、门、事件一致；三种背包都可过关 |
| 一间可辨认的房间 | [单房布局](layout.md) → [美术](art.md) → [建筑生成与参数](../../tools/building_construction/production/README.zh-CN.md) | 先在入口看懂门与高差，再走近辨认可操作部件；墙洞与实际碰撞一致 |
| 一个居民 | [人物](characters.md) | 裸足比例有测量，服饰、动作和角色 ID 都经过正式加载器 |
| 一次合入 | [验证](verification.md) → [实机协议](../../mcp/game/README.md) | 逻辑日志与同种子实机各回答自己的问题 |

**首轮制作顺序：** 用折返闸验证路线图、物理门与第一人称读图，再复查营地与天文台。沿用已接入的固定地标、一次折返和晨钟三解。人物以侦探静态首件做比例对照，按活动居民的交付流程逐一替换营地模型。
