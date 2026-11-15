# 本地视频动作工作流

该目录使用真实 MediaPipe 视频检测输出，直接重定向至游戏的 Mixamo 侦探骨架。

1. 环境：`.runtime/mocap/Scripts/python.exe`；需 MediaPipe、OpenCV、NumPy、SciPy。当前 MediaPipe 版本为 1.2.3。
2. 模型：`.runtime/mocap/models/pose_landmarker_full.task`；下载来源与 SHA256 写在旁侧 source 文件。
3. 提取：

```powershell
.runtime/mocap/Scripts/python.exe tools/mocap/video_to_motion.py --video <视频路径> --output .runtime/mocap/runs/<新任务名> --subject-height 1.72 --subject-x 0.5 --subject-y 0.5 --seconds 20
```

`--subject-x/y` 以全视频画面归一化坐标选择人物髋部。小人物可用 `--crop-width 0.4 --crop-height 0.5` 启用跟随裁切；原始记录保留每帧裁切框、候选人数、追踪距离和全部置信度。

4. 预览：在 Godot 打开 `tools/mocap/MocapPreview.tscn`，拖入视频或导出的 `motion.json`，也可用“选视频”。公开样片的工作台配置为 `assets/data/test_scenarios/mocap.yaml`。
5. 输出：原始 `landmarks.json`、`motion.json`、旋转 `motion.bvh`、`manifest.json`、检测示意图；预览输出 `retargeted.res`、`retarget-report.json`、`playback-observations.json` 和真实采集。
6. `retargeted.res` 是 Godot AnimationLibrary，含 `video` 动画。目标 AnimationPlayer 可 `add_animation_library("measured", library)` 后播放 `measured/video`。骨骼路径对应当前模型层级；换模型须重新重定向。

重定向支持两种根节点策略：默认 `--root-policy=measured` 保留经过滤波的横向与竖直测量；步行测试配置显式选择 `grounded`，将根节点 Y 固定以抑制足底估计噪声。跳跃、下蹲等视频使用 `measured` 并检查原始测量。两种模式均保留原始 JSON、held/置信度和滤波误差，深度位移继续标为未观测。

快回归可执行 `.runtime/python/Scripts/python.exe tools/testing/run_parallel.py --workers 2`；其中动捕任务验证导出轨道、关键帧、旋转与根位移限速、两种根节点模式和人工审片标记。正面样片现为 49/50 检测、1 个 held 帧，渲染预览与足底接地仍由 Terra 复核。

根节点 X 来源于固定相机下图像位移与身高标定，Y 来源于测量足底相对髋高；深度位移固定为 0，并在报告标为未观测。转头、遮挡与多人物切换可能造成姿态跳变，原始数据完整保留供修正。预览重定向层依据每帧可见度稳定局部旋转，并将根位移限制为已观测的水平 X；原始地面相对髋高、深度未观测状态、held 帧和全部置信度继续保存在 `motion.json` 与报告中。人工未审片前所有资源均为待检查。

公开 OpenCV 侧面步行样片记录在 `.runtime/mocap/sources/opencv-vtest.avi.source.json`。5 秒跟随裁切测试检测 45/50 帧，存在低置信度、旋转跳变与脚底离地；该样片用于验证管线，动作质量待修正。公开预览配置使用正面样片 `.runtime/mocap/runs/opencv-front-01/`，检测 49/50 帧、held 1 帧；质量状态仍需人工审片。开发输出保留在 `.runtime/mocap/runs/opencv-walk-02/` 与 `.runtime/mocap/previews/opencv-retarget-04/`。
