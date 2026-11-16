# 快照淡入淡出恢复检查

工程根目录：`C:\Users\iii\Desktop\dual_ontology_world_reconstruct_2`。

`StoryCheckpoint.gd` 继续使用 `story-checkpoint-v1` 外层格式，在 presentation 增加可选 `fade_transition`：语义意图、捕获 alpha、目标 alpha、总时长、经过时长和剩余时长。捕获活跃 Tween 时读取它的实际经过时间；再次保存已恢复的 Tween 时扣除本轮经过时间，保持原过渡终点。恢复先重建场景与回调对象、应用保存的 UI alpha，随后创建剩余 Tween。

旧快照按控制器阶段重建过渡：开场 `black` 保留遮罩并继续保存的阶段计时；`fade` 按剩余阶段时间淡入；开场 `free` 的历史残留遮罩以开场淡入速度平滑清除。走廊 `fadeout` 继续遮黑并在完成后建舞台，`out` 完成遮黑后进入目标房间；走廊入场、房间入场继续淡入。房间切换和章节切换的必要回调通过语义意图重建。

读取同时检查外层格式、项目标识、内容 SHA256、确切工程目录、源 PID 为正且与外层 host_pid 一致。新淡入字段检查类型、有限数值、alpha、目标及当前阶段意图。开发快照允许跨进程恢复，来源 PID 和接收 PID分别记录。

## 可复现 GPU 回归

在 PowerShell 执行：

```powershell
$fadeRunId = 'snapshot-fade-recheck-' + (Get-Date -Format yyyyMMddHHmmss)
& C:\Users\iii\Desktop\dual_ontology_world_reconstruct_2\tools\test\run_snapshot_fade_resume.ps1 -WorkId $fadeRunId
```

启动器使用本项目 `.runtime/godot/4.7.2-standard/Godot_v4.7.2-stable_win64.exe`。每次生成和恢复使用独立进程；Windows CIM 核验进程 PID、可执行和命令行工程路径，报告再次与操作系统 PID 对照。每次运行结果通过项目 review MCP 追加检查。

测试用生产入口创建中断位置，以 Tween.custom_step 定位确定性捕获点；实际恢复后检查初始 alpha、半程插值、再次保存/恢复的剩余时间，并让最后一段 Tween 按真实帧时间运行到生产终点。宿主控制器的移动在定点测试中暂停。截图前暂停 Tween 等待容器布局完成，截图由真实 GPU 视口生成，未修改 alpha、相机或快照源。

覆盖现有 opening-free、开场黑场/淡入、走廊遮黑/淡入/离场、普通换房遮黑/淡入，章节遮黑/淡入，以及八种旧格式兼容和身份拒绝。结果、复现快照、GPU 图片与相邻 source/hash sidecar 位于：

`C:\Users\iii\Desktop\dual_ontology_world_reconstruct_2\.runtime\fade-resume\final`

首轮布局完成前的开发图片保留在父目录。最终证据使用 `final` 子目录，每份报告含检查脚本 SHA256。所有证据标记 `acceptance_eligible=false`。

`-ResumeOnly` 复用已生成快照；`-Cases opening-fade,corridor-cover` 选择定点。工作完成后原 work_id 封闭，复查使用新的 `-WorkId`。

已有定点快照的最终版本复查可执行启动器并传入 `-ResumeOnly`；使用 `-Cases` 可选择案例。截图同时检查像素明暗范围，提前发现视口尚未绘制造成的空帧。
