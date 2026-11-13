# reconstruct_2 修正包

在 `dual_ontology_world_reconstruct_2` 仓库根目录覆盖解压本包（或 `git apply reconstruct_2-fix.patch`），然后：

```bash
tools/build/build.sh          # Windows: powershell -File tools/build/Build.ps1
# 用 Godot .NET (mono) 4.7.2 打开项目并运行
```

| 文件 | 修正内容 |
|---|---|
| `NuGet.Config` | 删除指向被 .gitignore 忽略的 `.runtime/godot/4.7.2/...` 的本地源（NU1301），只保留 nuget.org |
| `project.godot` | ① 窗口标题改为「安眠者有福 · 五人生活推演」② 修正音频键 `buses/default_bus_layout` ③ 补回 12 个缺失输入动作 ④ 入口改为 `Boot.tscn` |
| `scenes/main/Boot.gd/.tscn` | 新增：启动自检，非 .NET 版或程序集未编译时显示原因，不再空白；通过则进入 Main |
| `scenes/UIpanel/TitleUI/TitleUI.gd` | 「打开建筑设计工具」按钮补上悬停音效 |
| `tools/build/build.sh`, `run.sh` | 新增跨平台构建/运行脚本 |
