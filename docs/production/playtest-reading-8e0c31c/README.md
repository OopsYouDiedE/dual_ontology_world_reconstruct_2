# 首征 AI：手册 × 现场提示

[打开离线交互报告](index.html)。按走法筛选四组轨迹，比较同策略同种子的增减，查看逐句台词、零命中、五页手册原文、逐局数据和三个可读物的独立近场核验。

游戏基线 `8e0c31c`；仅修改测试控制器与报告工具。三种策略 × 种子 1–18 × 四种阅读条件，共 216 局；每局 7,800 tick。另做残页、同声律刻板、独灯律刻板各两种阅读条件，共 6 次近场功能检查。后者单列，不计入自主触发概率。

## 本轮差异

- 只读现场提示时，21/54 局听到 Hale 查明插销，4/54 局抵达档案翼；两者都读时分别为 16/54、0/54。配对核查：16 对均听到插销台词，5 对只在不读手册时听到，0 对反向新增。
- 两个跳过现场提示的组均未触发插销台词。均跳过组仍有 4/54 局自行走进档案翼并收到塌拱台词。
- 阅读手册的 108 局均核实五页实际正文。读后按脚步声线索轻步，在读提示条件下，平均移动距离由 81.1 米降至 55.5 米。两组首次自主决策窗口相同。全部 216 局限时结束。
- 所有自主局都没有看到残页或刻板的 E 键阅读提示。在 6 个另计的可见位置对照中，AI 获取提示时三种可读物均按 E、收到对应正文；屏蔽提示时均未按 E、未收到正文。

## 复现（仓库根目录，PowerShell）

```powershell
$env:DOTNET_ROOT='C:/Program Files/dotnet'
$s=1..18
foreach ($arm in 'book-hints','closed-hints','book-skip','closed-skip') {
  python tools/expedition/human_batch.py run --seeds $s --ticks 7800 --jobs 8 --timeout 180 --reading $arm
  if ($LASTEXITCODE) { throw "Batch failed: $arm" }
}
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --fixed-fps 60 --path . --log-file .runtime/reading-sites.log -s res://tools/expedition/reading_site_check.gd -- --rogue-mcp-dir=
# 用上面四个 Batch: 路径替换下列占位符，批次次序不影响分组。
python -B docs/production/expedition-01/playtest/reading_report.py <batch1> <batch2> <batch3> <batch4> --sites-log .runtime/reading-sites.log --out .runtime/reading-report.html
```
