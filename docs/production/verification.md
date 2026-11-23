# 正式验收：从公共大厅走到晨钟

准备 Godot 4.7.2 .NET、.NET 8 和装有项目 MCP 依赖及 Pillow 的 Python。在仓库根运行同一个[验收入口](../../tools/expedition/verify.py)：

```powershell
& .runtime/python/Scripts/python.exe tools/expedition/verify.py
```

依次构建、导入资源、验证拓扑与 256 个种子、检查 ArchBuilder 构件和窗光、完成三次战役集成、在 Forward+ 验证 6.5 头身角色，最后用项目 MCP 分别跑东西两线。任一阶段失败即停止；按阶段命名的日志和路线截图保存在 `.runtime/production-check/`。没有图形设备时加 `--logic-only` 只跑前面的非图形检查。`DV_GODOT` 可指定同版本控制台程序。

人工复核同样从 [Run.tscn](../../scenes/rogue/Run.tscn) 进入：项目 MCP `on(scene="rogue", seed=2)` 应显示 `room=camp`、`phase=camp`、两条路线和 16 名居民。使用 `step` 操作、`observe` 截图、`close` 结束。大厅 04 原图见[画面基准](art.md)。

每局保存六张 1080×720 JPG 和一份 `frames.json`。先核对折返前后库存与结局，再按[入口全景、走近操作](art.md)复看画面。沿[布局](layout.md)记录入口、操作位和出口回望；检查路线图预告、门牌与实体门指向一致。给第一次玩的玩家遮掉提示，问「哪边能回营？为什么留这个工具？」把答错的位置记到该房的修改单。独立物理实验、规则解题基准在各自场景验证，不能代替这条出征测试。
