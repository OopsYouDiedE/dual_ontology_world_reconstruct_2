# 关卡设计清单：R-01 · 北翼编号门廊与二层海侧侧廊 (`chapter1_r01_corridor`)

- **校验状态**：`PASS`（错误 0 条）
- **能力特例**：`allow_jump=true`, `allow_lamp=true`, `allow_stomp=true`, `allow_command_wheel=true`

## 1. 场景物体（统一家具库 `AcademyFurnitureCatalog`）
| ID | 资产类型 | 家具库 ID | 坐标 | 分区 |
|---|---|---|---|---|
| `r01_bench_w` | recipe | `bench` | `(-2.40, 0.00, -3.50)` | 门廊西侧 |
| `r01_desk_guard` | recipe | `reception_desk` | `(2.30, 0.00, -4.80)` | 编号登记台 |
| `r01_lamp_desk` | recipe | `banker_lamp` | `(2.30, 1.08, -4.50)` | 编号登记台 |
| `r01_shelf_n` | recipe | `bookshelf` | `(-2.60, 0.00, -8.20)` | 北端门牌柜 |
| `r01_table_side` | glb | `manor_table_long` | `(2.40, 0.00, -8.60)` | 海侧窗台旁 |
| `r01_candle` | glb | `brass_candle_triple` | `(2.40, 0.74, -8.60)` | 海侧窗台旁 |
| `r01_supply_chest` | glb | `manor_chest` | `(-2.30, 0.00, -6.20)` | 门廊西侧 |

## 2. 可交互点（双模三态 `DualModeInteractionHud`）
| 组 ID | 标题 | 局部热点 | 动作动词 | 触发动作 ID | 解锁条件 |
|---|---|---|---|---|---|
| `r01_logbook` | 北翼编号登记簿 | 登记簿 | 核对通道编号 | `read_corridor_log` | 默认开放 |
| `r01_drifted_letter` | 窗台湿咸信件 | 陌生邮戳信件 | 俯身观察（勿徒手收起） | `inspect_drifted_letter` | 默认开放 |
| `r01_drifted_letter` | 窗台湿咸信件 | 工具拨离 | 用铜尺拨离主通道 | `sweep_drifted_letter` | letter_inspected |

## 3. 触发方式总表
| 触发 ID | 触发方式 | 来源对象 | 条件 | 结果动作 / 台词 |
|---|---|---|---|---|
| `trg_enter_r01` | 进入区域自动触发 | `r01_entry_zone` | 首次跨过北门 | 启动霍铎沿门廊自主排查 |
| `trg_foghorn_h2` | 远海汽笛声事件 | `r01_sea_window` | 霍铎行至海侧窗前 | 霍铎立刻背对所有窗户（演示 H2） |
| `trg_lantern_r04` | 无风室焰色倒伏前摇 | `r01_mist_pocket` | 进入低洼雾囊且未拦截 | 4.0s 可视前摇：玩家按 Q/E 喊停并盖灭提灯 |

## 4. 台词清单（已过认知防火墙校验）
| 台词 ID | 说话人 | 声线 | 台词内容（中文） |
|---|---|---|---|
| `dlg_hale_entry` | 霍铎 | `hale` | 门牌写着 N-01。记住编号，如果前面走廊长得一模一样，立刻原路退回这里。 |
| `dlg_log_read` |  | `resident` | 登记簿记着正常编号序列：N-01 门廊 → N-02 下沉档案廊。墨迹干燥，没有撕页。 |
| `dlg_letter_salt` |  | `resident` | 信封潮湿并带着浓重海盐味，邮戳日期竟是昨天——绝不能带回主楼。 |
| `dlg_hale_h2_turn` | 霍铎 | `hale` | ……汽笛声。别看窗户，低头等它过去。 |
| `dlg_hale_r04_mistake` | 霍铎 | `hale` | 奇怪，这儿没风，提灯火苗怎么发白还往一边倒？我把灯芯拧大一点看看…… |
| `dlg_chest_supplies` |  | `resident` | 箱里只有几截受潮的蜡烛头和一卷麻绳，封条完好。 |
| `dlg_hale_h5_nod` | 霍铎 | `hale` | 做得对，别徒手碰带海盐味和近日期的东西。我们可以往 N-02 走了。 |

## 5. AI 动作路线与规则前摇
### 角色：霍铎 (Hale) (`hale`)
| 序号 | 路径点坐标 | 动作 | 关联规则 | 前摇秒数 | 联动台词 |
|---|---|---|---|---|---|
| 1 | `(0.00, 0.00, -2.50)` | 核对 N-01 门牌并停步等待 | `Rule-03` | 0.0s | `dlg_hale_entry` |
| 2 | `(1.20, 0.00, -5.20)` | 闻汽笛声瞬间背对海侧廊窗 | `H2` | 0.0s | `dlg_hale_h2_turn` |
| 3 | `(0.60, 0.00, -7.80)` | 提灯焰色发白倒伏，准备拧大灯芯（需玩家喊停） | `Rule-04` | 4.0s | `dlg_hale_r04_mistake` |
| 4 | `(1.50, 0.00, -9.20)` | 示意远离湿咸信件，准备转入 N-02 | `H5` | 0.0s | `dlg_hale_h5_nod` |
