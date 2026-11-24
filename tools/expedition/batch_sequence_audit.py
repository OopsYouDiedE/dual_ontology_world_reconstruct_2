#!/usr/bin/env python3
"""Batch Permutation Probe & Visual HTML Statistics Generator.

Runs all Expedition-01 route/rule permutations in 60Hz real-physics Godot,
audits dialogue trigger order and region traversal sequence, flags anomalies,
and writes an editorial HTML visual statistics report.
"""

from __future__ import annotations

import argparse
import html
import json
import os
import subprocess
from pathlib import Path
from typing import Any, Dict, List

SCENARIOS = [
    ("S1_Standard_North", "常规线：试闸 → B2/B3 → 北窗盯桥+熄灯 → 拔芯撤离"),
    ("S2_A2Niche_B6Pump_North", "侧龛+泵房线：A2静步取油 → B3 → B6飞轮 → 北窗过桥"),
    ("S3_Cheese_IgnoreHale_Solo", "逃课线：甩掉Hale → 零补给 → 潜行硬过主桥 → 拔芯狂奔"),
    ("S4_B4Dark_SouthCatwalk", "南栈桥线：B4暗房补油 → 熄灯走南侧耗油窄栈桥"),
    ("S5_B4Loft_Metronome_Bridge", "诱饵线：B4信号夹层拿节拍器 → 投饵强冲主桥"),
    ("S6_DoubleLamp_Breach", "独灯律违规线：带Hale进井不按R熄灯 → 检验规则台词与惩罚"),
]


def run_scenario(godot: str, repo: Path, sid: str) -> Dict[str, Any]:
    cmd = [
        godot, "--headless", "--fixed-fps", "60",
        "--path", str(repo),
        "--script", "res://tools/expedition/batch_sequence_probe.gd",
        "--", f"--scenario={sid}",
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=140)
    for line in (proc.stdout + "\n" + proc.stderr).splitlines():
        if line.startswith("PROBE_RESULT "):
            return json.loads(line.split("PROBE_RESULT ", 1)[1])
    return {"scenario": sid, "success": False, "fail_reason": "no_output", "ticks": 0, "duration_s": 0.0, "oil_left": 0.0, "peak_exposure": 0.0, "region_seq": [], "dialogue_seq": [], "action_seq": []}


def build_html(results: List[Dict[str, Any]], out_html: Path, title_note: str) -> None:
    total = len(results)
    cheese = next((r for r in results if r["scenario"] == "S3_Cheese_IgnoreHale_Solo"), None)
    cheese_blocked = cheese is not None and not cheese["success"]
    total_lines = sum(len(r.get("dialogue_seq", [])) for r in results)

    rows_html = []
    for r, (_, desc) in zip(results, SCENARIOS):
        sid = r["scenario"]
        regs = " → ".join(x["region"] for x in r.get("region_seq", []))
        lines = r.get("dialogue_seq", [])
        dlg_items = []
        for idx, d in enumerate(lines, 1):
            t_s = d["tick"] / 60.0
            dlg_items.append(
                f"<li><span class='tk'>#{idx} [{t_s:.1f}s · {html.escape(d['region'])}]</span> "
                f"<b>{html.escape(d['speaker'])}</b>：{html.escape(d['text'])}</li>"
            )
        status_cls = "ok" if (r["success"] if sid != "S3_Cheese_IgnoreHale_Solo" else not r["success"]) else "warn"
        if sid == "S3_Cheese_IgnoreHale_Solo":
            badge = "已拦截逃课" if not r["success"] else "逃课漏过!"
        elif sid == "S6_DoubleLamp_Breach":
            badge = "规则已触发" if r.get("both_lamp_triggered") else "未触发规则"
        else:
            badge = "通关" if r["success"] else f"失败 ({html.escape(r['fail_reason'])})"
        rows_html.append(f"""
        <div class="card">
          <div class="card-head">
            <div><h3>{html.escape(sid)}</h3><p class="sub">{html.escape(desc)}</p></div>
            <span class="badge {status_cls}">{badge}</span>
          </div>
          <div class="meta">
            <span>耗时 <b>{r['duration_s']}s</b> ({r['ticks']} ticks)</span>
            <span>余油 <b>{r['oil_left']}%</b></span>
            <span>峰值警戒 <b>{r['peak_exposure']}</b></span>
            <span>台词数 <b>{len(lines)}</b></span>
          </div>
          <div class="route-line"><b>动线顺序：</b><code>{html.escape(regs or '—')}</code></div>
          <ol class="dlg-list">{''.join(dlg_items) or '<li>无台词触发</li>'}</ol>
        </div>
        """)

    page = f"""<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>Expedition-01 批量动线与台词顺序统计报告</title>
<style>
  body{{font-family:'Microsoft YaHei','Noto Sans CJK SC',sans-serif;background:#161412;color:#efe6d5;margin:0;padding:28px;line-height:1.55}}
  .wrap{{max-width:1100px;margin:0 auto}}
  h1{{color:#ffbf75;margin:0 0 6px;font-size:26px}}
  .lead{{color:#b9a68a;margin:0 0 20px}}
  .kpis{{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:22px}}
  .kpi{{background:#221e1a;border:1px solid #3c342b;border-left:3px solid #ffbf75;padding:12px 14px;border-radius:4px}}
  .kpi .v{{font-size:24px;font-weight:700;color:#ffbf75}}
  .kpi .k{{font-size:12px;color:#b9a68a}}
  .card{{background:#201c18;border:1px solid #3a3229;border-radius:5px;padding:16px;margin-bottom:14px}}
  .card-head{{display:flex;justify-content:space-between;align-items:flex-start;gap:12px}}
  h3{{margin:0;color:#f6ead6;font-size:17px}}
  .sub{{margin:2px 0 0;color:#b9a68a;font-size:13px}}
  .badge{{padding:4px 10px;border-radius:3px;font-size:12px;font-weight:700}}
  .badge.ok{{background:#224335;color:#8ee6b8;border:1px solid #3e7a5e}}
  .badge.warn{{background:#4c221c;color:#ff9b85;border:1px solid #8a3d31}}
  .meta{{display:flex;gap:18px;font-size:13px;color:#d6c7b2;margin:10px 0 8px}}
  .route-line{{background:#181512;padding:8px 10px;border-radius:3px;font-size:13px;margin-bottom:10px}}
  code{{color:#9fd6e8;font-family:Consolas,monospace}}
  .dlg-list{{margin:0;padding-left:20px;font-size:13px}}
  .dlg-list li{{margin:4px 0}}
  .tk{{color:#b9a68a;font-family:Consolas,monospace;font-size:12px;margin-right:6px}}
</style>
</head>
<body>
<div class="wrap">
  <h1>Expedition-01 真实碰撞体批量动线与台词顺序统计</h1>
  <p class="lead">{html.escape(title_note)}</p>
  <div class="kpis">
    <div class="kpi"><div class="v">{total}</div><div class="k">实机物理测试动线</div></div>
    <div class="kpi"><div class="v">{'BLOCKED' if cheese_blocked else 'BYPASS'}</div><div class="k">单人潜行逃课拦截</div></div>
    <div class="kpi"><div class="v">{total_lines}</div><div class="k">采集真实台词事件</div></div>
    <div class="kpi"><div class="v">60 Hz</div><div class="k">真实胶囊物理与触发器</div></div>
  </div>
  {''.join(rows_html)}
</div>
</body>
</html>"""
    out_html.write_text(page, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default=os.path.expanduser("~/.local/godot-4.7.2-mono/Godot_v4.7.2-stable_mono_linux.x86_64"))
    parser.add_argument("--html", default=".runtime/batch_sequence_report.html")
    parser.add_argument("--note", default="基于 100% 正式游戏 CharacterBody3D 胶囊碰撞体与交互触发器的全路线实测统计")
    args = parser.parse_args()

    repo = Path(__file__).resolve().parents[2]
    results = []
    for sid, _ in SCENARIOS:
        r = run_scenario(args.godot, repo, sid)
        results.append(r)
        regs = "->".join(x["region"] for x in r.get("region_seq", []))
        print(f"[{sid}] ok={r['success']} t={r['duration_s']}s oil={r['oil_left']} exp={r['peak_exposure']} dlgs={len(r.get('dialogue_seq',[]))} regions={regs}")

    out_path = Path(args.html)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    build_html(results, out_path, args.note)
    print(f"HTML_REPORT {out_path}")


if __name__ == "__main__":
    main()
