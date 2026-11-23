# Structure Lab · 从房间输入到构件

**试验入口：** `Structure Lab → Example → Room kit study`（编辑态快捷键 `K`）。从左至右为 6.0 m 大厅、3.3 m 泵房、2.4 m 暗室。`F` 进入 1.60 m 眼高漫游，再按 `F` 返回。`Inspection hall` 恢复原来的双层门厅。两个示例共用同一个求解器和视图。

## 一次重建的顺序

1. **ReservationPass** 读取以米为单位的建筑坐标，建立避让体与必留开口索引，再确定楼梯井和入口。`footprint` / `operation` 用 `min`、`size` 给出轴对齐盒；`cone` 由 `apex`、`end`、终端 `radius` 确定，构件检测采用保守包围体。光路需要穿墙时另声明 `opening`；锥体本身不改变房间的围护拓扑。
2. **StructurePass** 按 4.2 m 轴网共用角柱及边梁，按本层最高室高确定下一层底标高。受占位阻挡的柱依次试原位和四向偏移 0.55 m，梁使用最终柱轴。登记板、井及骨架槽；不同包把同一开间表现为梁网、连续拱券或无柱空间。
3. **EnvelopePass** 以边键去重，确定两侧房间、墙厚、净洞与围护高度。一条 `opening` 同时决定墙身割洞和门窗尺寸。`Xx:z:l` 指从格点沿 X 的边，`Zx:z:l` 沿 Z；`room-kit-study.json` 的 `Z2:0:0` 只产生一道 1.50 m 宽的贯通门。普通禁窗外墙保留实墙，窗槽改装盲框。高厅默认把窗台抬至 `room_height - 1.65 m`。
4. **FinishPass** 派发两侧独立饰面、顶棚、铺地和灯槽，检查灯具净空。所有槽登记完后，`SlotCompiler` 再调用资源选出的 Recipe，生成视图消费的构件记录。最后将 `mounts` 接到已生成的挂点。建筑基础地板与竖向交通属于通行拓扑；Kit 的 `passes` 控制可选骨架、围护和饰面。每阶段可用 `extensions` 添加 `run(solver, cell_id)` 扩展。

## 添加或替换一种构件

复制 `HallKit.tres`，在 `recipe_overrides` 填入 `ColumnSlot → 新 Script`，然后在平面 `profiles[房间组].kit` 填该 `.tres` 的 `res://` 路径。键取 `rooms` 指定的组号字符串，未分组时取房型编号。Recipe 脚本的最小形态：

```gdscript
extends RefCounted
func supports(q): return q.radius >= 0.12
func emit(s, q):
    var h:float = q.height
    s.box(q.id, q.p + Vector3.UP*h/2, Vector3(.20,h,.20), "stone")
```

`p` 是槽的建筑坐标，`owner` 是开间地址，`id` 是覆盖键。窗另收 `w/low/high`；门收 `w/high/thick/yaw`；梁收端点 `a/b`；顶棚收 `polygon`。`capabilities[key]=[最低室高,最高室高]` 与 `supports(q)` 共同决定合法性。失败时按 `fallbacks[key]` 继续匹配；循环或无匹配写入诊断。另一个 key 可复用同一脚本，通过 `variants` 切换形态。例：低于 2.8 m 的大厅从吊灯退到吸顶灯，顶面变平，木墙裙压低。示例包也涵盖泵房的工字柱、明管和铁窗，以及天文台鼓座与穹顶。

## 机关与手工覆写

机关声明可直接参考同目录 JSON。`mounts` 中给 `id/anchor/near/scene` 和可选 `owner`：在同类合法挂点中找最近点，找不到则报告该机关 ID。可选类型：`BayCenter`、`ColumnFace`、`WallPanelCenter`、`PipeJunction`、`Threshold`。墙装件的局部 +Z 指向墙外法线。挂点校验的是安装点；大型装置应同时声明完整占地与操作净空。

底栏选 **Prefab slots → 槽 ID → Pin / update**，选择项目内、根节点为 Node3D 的 `.tscn`。实例可实现 `configure_slot(contract)` 读取真实尺寸，自行提供需要的碰撞和安装细节。柱原点在柱脚，窗在窗台，门扇原点为洞口下沿中心；门继续使用宿主的开关、碰撞及导航。**Clear override** 在此筛选下仅清除场景替换，轴偏移等调整保留。`Save / Load` 持久化输入和覆盖键；如果重绘删除了原轴或墙，覆写不会猜测另一构件作为替代目标。
