# 原版 FreeSO：启动契约与当前阻塞

`vendor/FreeSO` 的 gitlink 固定在 `4c6b3e8f5835b228723caea3c9f683c62f244f73`。父仓库仅记录上游地址和提交，未复制或分发 EA TSO 资产。引擎源码许可见该提交的 `LICENSE.md`（MPL 2.0）；外部依赖分别适用其许可，EA 原版内容由使用者自行准备。

## 游戏调用方

在仓库根目录执行：

```powershell
git submodule update --init --recursive --depth 1 -- vendor/FreeSO
powershell -NoProfile -File tools/freeso/freeso.ps1 -Action Check
powershell -NoProfile -File tools/freeso/freeso.ps1 -Action Build -NuGet C:/path/to/nuget.exe
powershell -NoProfile -File tools/freeso/freeso.ps1 -Action Launch -RoomId Generated_892-2
```

- `Check` 输出一行 JSON：`revision`、`assetRoot`、`buildReady`、`launchReady` 及三个问题列表。退出码 `0` 表示启动预检通过，`2` 表示有阻塞；构建可用性单看 `buildReady`。预检检查关键文件及路径，完整资源和运行环境由原版进程验证。
- `Build` 使用 Visual Studio MSBuild（优先 2019，也可传 `-MSBuild`）、NuGet CLI 和上游递归子模块。沿该提交的 `azure-pipelines.yml` 生成 FSOMonoGame 项目、恢复包并构建 Release/Any CPU 的 `FSO_IDE` 目标（引用 `FSO.Windows`）。从固定提交和递归子模块导出临时构建树，调用 `tools/freeso_bridge/install-hook.ps1` 把钩子接在原版 Sandbox 的 VM 更新周期；官方 checkout 保持原样。构建产物在 `.runtime/freeso/client/`；核对关键文件后才写 `.source-revision`。`Build` 不需要 EA 资产。
- `Launch` 从上述目录启动原版 `FreeSO.exe -ogl -tso w`，输出 `pid`、`revision`、`executable`、`snapshotPath`；调用方应异步读取输出。返回 PID 仅确认进程启动。调用方可以传 `-AssetRoot` 断言实际选择的路径；原版 `WindowsLocator` 依次查找输出目录的 `../The Sims Online/TSOClient`、Windows 32 位 Maxis 注册项、默认安装路径。脚本不写注册表、不复制资产。

启动时传 `-RoomId` 可启用原版 Sandbox 的实时 VM 导出。ID 允许 1–64 位 ASCII 字母、数字、连字符和下划线，以字母或数字开头，排除 Windows 设备名。默认输出 `.runtime/freeso/lots/<id>.json`；`-LotDirectory` 可覆盖目录，路径通过 `FREESO_VM_SNAPSHOT_PATH` 仅传给子进程。省略 RoomId 时清除子进程继承的这个变量。用 Check 获取解析后的绝对 snapshotPath。RoomId 只选择导出目标；请在原版 UI 中进入对应地块。同一路径保持一个写入者；旧 JSON 可能保留，读取端要等新文件发布。

## 使用原版 Sandbox 编辑学院模板

```powershell
powershell -NoProfile -File tools/freeso/freeso.ps1 -Action Check -BlueprintId academy_02
powershell -NoProfile -File tools/freeso/freeso.ps1 -Action Launch -BlueprintId academy_02 -RoomId Run_908
```


将团队提供的原版 FreeSO XML 放在 `content/academy_lots/<模板 ID>.xml`。`Check` 和 `Launch` 输出绝对 `blueprintPath`。启动器检查路径、XML 语法和 `<house>` 根；地块数据和资源 ID 由原版反序列化与解析。客户端加载完资源后进入原版 Sandbox；首次使用时先完成原版 Create A Sim。该模板加载强制使用指定 XML，跳过同名本地 FSOV 和旧版职业地块的路径数字裁切规则。省略 `-BlueprintId` 保留原版启动流程；`-RoomId` 仍独立控制实时快照。

在 FreeSO 的 **Build Mode** 编辑。编辑完按原版 **Ctrl+S**，在 **Save Lot** 输入新名称。原版 `VMWorldExporter` 将 XML 写到客户端用户目录的 `Blueprints/<名称>.xml`，另存 `LocalHouse/<名称>.fsov`。审查 XML 后，将它放回 `content/academy_lots/` 作为新模板或有意替换旧模板。启动和保存过程保持仓库输入只读。

## 原版边界

建筑界面入口为 `tso.client/UI/Panels/UIBuildMode.cs`；建筑命令由 `VMNetArchitectureCmd.Execute` 交给 `VMArchitecture.RunCommands`。角色交互走 `tso.files/Formats/IFF/Chunks/BHAV.cs` 和 `tso.simantics/Engine/VMThread.cs`；TSO 对象提供器读取 `objectdata/objects/objiff.far`。`LotFacadeGenerator` 消费现成 Blueprint 生成外立面渲染数据；规则式布局生成及 Godot 房间互转需要单独设计。

房间投影使用 `tools/freeso_bridge/README.md` 的 `freeso.lot-snapshot.v1` 契约。钩子只在原版 Sandbox 内发布。验收需先进入可编辑地块，再通过原版 Build Mode 放置墙与地板，确认 live JSON 更新；随后执行对象交互，记录实际 BHAV 和角色状态变化。

## 本机验证

固定提交的 filtered shallow fetch 取得提交和树，checkout 补取 blob 时出现 RPC 提前断流。保留 gitlink 与空的可初始化目录。已用该提交的原版 Sandbox 源文件和客户端项目文件验证钩子注入及幂等，且已验证动态 ID、自定义目录与启动阻塞退出。仍缺可构建的完整 checkout、NuGet CLI（可传路径）及授权 EA 资产（至少 `tuning.dat` 和 `objectdata/objects/objiff.far`）。原版客户端构建、窗口启动及真实 VM JSON 待实测。
