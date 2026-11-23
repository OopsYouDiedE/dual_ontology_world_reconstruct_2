# 项目结构树

结构树是当前工作树的快照。每条分支按「目录 → 文件 → 类型或作用域 → 函数」组织，函数标有签名和起讫行。搜索支持文件路径、符号名、限定名和签名；筛选器可单独查看子模块、有本地改动的文件或解析提示。

## 生成与查看

在仓库根运行（需要 Python 3.10+、Git 与 PowerShell 7）：

```powershell
python -m pip install --target .runtime/project-tree/deps -r tools/project_structure/requirements.txt
$env:PYTHONPATH = (Resolve-Path .runtime/project-tree/deps).Path
python tools/project_structure/build.py
Start-Process (Resolve-Path .runtime/project-tree/index.html).Path
```

| 产物 | 用途 |
| --- | --- |
| `.runtime/project-tree/index.html` | 离线交互树，可独立打开；旁边两个文件供链接下载 |
| `.runtime/project-tree/tree.txt` | 展开后的全树，适合编辑器查看或文本比对 |
| `.runtime/project-tree/index.json` | 逐文件的结构化索引，含 Git 状态、符号范围和解析提示 |

加 `--project-only` 可跳过子模块内容，保留主仓库记录的子模块入口。快照留在 `.runtime/`；生成过程仅读取 Git 与工作树，不执行待索引的源码。

## 收录口径

- 文件表来自各已检出仓库的 Git 索引及未被忽略的本地新增。磁盘上的实体进入树，索引中登记但当前缺失的路径单列；未初始化子模块记录固定的提交号。Godot 资源、图像、模型、UID 和配置同样保留为文件节点。
- Python 与 PowerShell 使用各自 AST；GDScript、C#、JavaScript、Shader 和其他已配置语言使用 Tree-sitter。Godot 资源内嵌 GDScript、HTML 内嵌 JavaScript 也会解析。汇编和批处理以词法标签呈现；其余无解析器的格式保留文件节点。
- 索引列出声明和匿名函数，不追踪调用点。函数条目包含方法、构造器、访问器、脚本块、委托签名和带参数的宏；类型、命名空间等单作分组。解析器恢复过的文件列出诊断，保留成功识别的声明。行、列为 1 起算；Python 和 Tree-sitter 的列以 UTF-8 字节计，PowerShell 的列以 UTF-16 代码单元计。
