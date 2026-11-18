# 独立肉鸽实机 MCP

`server.py --service input` 通过 stdio 提供 `status / on / observe / step / close`。环境服务沿用 `server.py --service environment` 的 `prepare`。老客户端应重新建立 MCP 连接以刷新工具表。

## 场景接口

- 固定入口 `res://scenes/rogue/Run.tscn`，通过 Godot 命令行直接打开。根节点保持为 `current_scene`；房间切换、结算和重开可在根节点内切换子树或重新加载同路径。`project.godot` 的 `[autoload]` 只需 `GameMcp="*res://mcp/game/GameControl.gd"`。
- 按玩家正常路径接收鼠标和 Godot InputMap 事件。测试可用视口坐标点击，也可传 InputMap 动作名。桥接器在测试启动参数缺席时休眠。
- 可选只读 `mcp_observe() -> Dictionary`，请返回 JSON 可序列化的数据，例如 `phase`、`round`、`seed`、`player_cell`、`visible_choices`。没有此方法时仍可用画面、点击和 InputMap 测试。若要固定随机性，由场景解析 `OS.get_cmdline_user_args()` 中的 `--run-seed=<整数>` 并把它用于局内 RNG；普通启动维持游戏自己的默认行为。

## 调用

1. `status {}` 检查入口文件和 autoload。
2. `on {"seed":1}` 启动真实 Forward+，验证 Godot PID、项目路径与配置哈希、入口和实际渲染方式，返回 `session_id`、视口大小和 PNG。
3. `step {"session_id":"…","operation":"click","x":640,"y":360}`；`operation:"action"` 传 `action` 和 `frames`（1–120）；`operation:"wait"` 只推进观测间隔。`observe {"session_id":"…"}` 获取当前画面。`screenshot:false` 只取状态。
4. `close {"session_id":"…"}` 回收本连接启动的进程。日志、PNG、回复和隔离 profile 保留在 `.runtime/rogue-mcp/<session_id>/`。

项目根目录可运行 `& .runtime/python/Scripts/python.exe tools/testing/rogue_smoke.py --seed 1`。若需验证一个项目已登记的动作，追加 `--action <InputMap名称> --frames 8`；点击起始画面可用 `--click 450 680`（1280×720，seed 1）。运行前需完成场景资源导入；若场景调用 C#，需先构建当前项目程序集。
