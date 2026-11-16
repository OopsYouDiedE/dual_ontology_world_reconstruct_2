"""Export archived acceptance evidence to linked HTML and Markdown without changing originals."""
from __future__ import annotations

import argparse
import csv
from datetime import datetime
from hashlib import sha256
from html import escape
from html.parser import HTMLParser
import json
import math
import os
from pathlib import Path
import re
import sys
from urllib.parse import quote, unquote, urlsplit

import yaml
from mainline_reviews import capture_time, load_reviews

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "mcp"))
import capture_provenance as provenance

OUT = ROOT / "artifacts/review"
DIMENSIONS = ["流畅度", "字数", "动作音效", "响度", "视听剧情替代", "参考相似度", "剧情流畅性"]
RUN_LABELS = {"reconstruction": "厨房三段推演", "expressions": "五表情预览", "kitchen": "厨房真实输入", "mocap": "视频动捕预览", "lighting": "多时段光照", "building": "64 建筑组合", "interaction": "9 类物件交互", "sleeve": "袖口拖拽", "lighting-attempt-1-missing-close": "光照首轮 · 缺关闭回执"}
REPORT_LABELS = {"terra-20261115": "历史基线 · 错误工程已隔离", "terra-correct-root-20261115": "采集路径修复与真实链路", "terra-20261116": "正式起床序列与标题设置书", "terra-workbench-20261116": "交互 / 光照 / 建筑遍历", "terra-integrated-20261116": "动捕 / 厨房输入 / 光照复采", "terra-reconstruction-expression-20261116": "五表情与三段推演复采", "blind-wardrobe-20261116": "衣柜视觉盲测", "terra-title-book-materials-20261116":"标题与设置书页材质复采", "terra-motion-fast-20261116":"正面视频动捕数值优化", "terra-wardrobe-fast-20261116":"衣柜物件修正", "terra-animation-cache-20261116":"动画缓存与跨进程复用", "parallel-integration-20261116":"并行回归与批次集成"}

CSS = """
:root{--bg:#f3f1e9;--paper:#fffef9;--ink:#263532;--muted:#68746d;--line:#dedfd4;--gold:#9a6a27;--red:#a24435;--green:#326557}*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.65 'Segoe UI','Microsoft YaHei',sans-serif}a{color:#35695d;text-underline-offset:3px}header{background:#233631;color:#f5f1df;padding:32px max(24px,calc((100vw - 1240px)/2));border-bottom:4px solid #b99558}.eyebrow{font-size:11px;letter-spacing:2px;color:#c6cfbe;text-transform:uppercase}h1{font-size:34px;line-height:1.3;margin:10px 0}h2{font-size:23px;margin:0 0 15px}h3{font-size:17px;margin:22px 0 10px}p{margin:10px 0}.lede{max-width:850px;color:#d5decf}main{max-width:1290px;margin:auto;padding:26px 24px 64px}nav{display:flex;gap:20px;flex-wrap:wrap;margin-top:20px}header a{color:#f2deaf}section,.card{background:var(--paper);border:1px solid var(--line);border-radius:13px;padding:24px;margin-bottom:24px;box-shadow:0 4px 18px #26353205}.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin-bottom:25px}.stat{border:1px solid var(--line);border-radius:10px;padding:18px;background:#faf9f2}.stat b{display:block;font-size:30px;line-height:1.25}.stat span{font-size:12px;color:var(--muted)}.toolbar{display:flex;gap:10px;flex-wrap:wrap;margin:14px 0 20px}input,select{font:inherit;border:1px solid #c8cec1;border-radius:7px;padding:9px 12px;background:white;color:var(--ink)}input{flex:1;min-width:230px}table{border-collapse:collapse;width:100%;font-size:13px;margin:16px 0}th,td{padding:11px 12px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top}th{background:#ebeede;font-weight:600;color:#40594b}tbody tr:hover{background:#f7f7ed}.scroll{overflow-x:auto}.score-table{min-width:1040px}.score-table td{white-space:nowrap}.score-table td:first-child{min-width:190px;white-space:normal}.score{display:inline-block;min-width:38px;font-weight:700;border-radius:5px;padding:3px 8px;background:#eef0e8;color:#778173}.score.fail{background:#f7e3dd;color:var(--red)}.score.ok{background:#dfede3;color:var(--green)}.badge{font-size:11px;padding:4px 8px;border-radius:5px;background:#ede9dc;color:#6d6249;white-space:nowrap}.badge.bad{background:#f8e2db;color:var(--red)}.muted,.meta{color:var(--muted);font-size:12px}.note{border-left:3px solid #b99558;padding:10px 14px;background:#f5f0e1;margin:14px 0}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}.gallery{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:16px}.gallery figure{margin:0;min-width:0;border:1px solid var(--line);border-radius:8px;overflow:hidden;background:#edf0e7}.gallery img,.compare img{display:block;width:100%;height:200px;object-fit:contain;background:#202b2b}.gallery figcaption{padding:10px;font-size:12px;word-break:break-word}.compare{display:grid;grid-template-columns:1fr 1fr;gap:14px}.compare figure{margin:0;min-width:0}.compare img{height:250px;border-radius:7px}.compare figcaption{font-size:12px;color:var(--muted);margin:8px 0}.report-body{max-width:1050px;margin:auto;overflow-wrap:anywhere}.report-body img{max-width:100%}.report-body table{display:block;overflow:auto}pre{background:#20312d;color:#e4eadc;padding:18px;border-radius:8px;overflow:auto;white-space:pre-wrap}code{font:12px/1.6 Consolas,monospace;background:#e9edde;padding:2px 4px;border-radius:3px}pre code{background:transparent;color:inherit}blockquote{margin:18px 0;border-left:3px solid #b99558;padding:8px 16px;background:#f5f0e1}details{margin:12px 0}summary{cursor:pointer;font-weight:600}.run-details[hidden],.report-card[hidden]{display:none}.run-details{padding:17px 0;border-top:1px solid var(--line)}.links{display:flex;gap:14px;flex-wrap:wrap;font-size:12px;margin-top:12px}.rule{font-size:13px;color:var(--muted)}footer{font-size:12px;color:var(--muted);padding:8px}.lightbox{position:fixed;inset:0;background:#07100ff0;z-index:10;display:flex;align-items:center;justify-content:center;padding:48px;cursor:zoom-out}.lightbox[hidden]{display:none}.lightbox img{max-width:100%;max-height:100%;object-fit:contain}.close{position:fixed;right:18px;top:12px;background:#f5f0dd;color:#20312d;border:0;padding:10px 16px;border-radius:6px;cursor:pointer}body.modal{overflow:hidden}@media(max-width:800px){header{padding:25px 20px}h1{font-size:28px}main{padding:18px 12px}.stats{grid-template-columns:repeat(2,1fr)}.grid,.compare{grid-template-columns:1fr}.gallery{grid-template-columns:repeat(2,minmax(0,1fr))}section,.card{padding:18px}.gallery img{height:150px}}@media print{.toolbar,nav,.lightbox{display:none}.gallery{grid-template-columns:repeat(3,1fr)}section{break-inside:avoid}header{color:#20312d;background:white}body{background:white}}
"""
JS = """
const search=document.querySelector('#search'),scope=document.querySelector('#scope');
function filter(){const q=(search?.value||'').toLowerCase(),s=scope?.value||'all';document.querySelectorAll('[data-search]').forEach(e=>{e.hidden=!(e.dataset.search.toLowerCase().includes(q)&&(s==='all'||e.dataset.scope===s))})}search?.addEventListener('input',filter);scope?.addEventListener('change',filter);
const lb=document.querySelector('#lightbox');document.querySelectorAll('a.zoom').forEach(a=>a.addEventListener('click',e=>{e.preventDefault();lb.querySelector('img').src=a.href;lb.hidden=false;document.body.classList.add('modal')}));function closeLightbox(){lb.hidden=true;lb.querySelector('img').removeAttribute('src');document.body.classList.remove('modal')}lb?.addEventListener('click',closeLightbox);document.addEventListener('keydown',e=>{if(e.key==='Escape')closeLightbox()});
"""


def read_json(path: Path, default=None):
    return json.loads(path.read_text(encoding="utf-8-sig")) if path.is_file() else default


def href(path: Path, page: Path) -> str:
    return quote(os.path.relpath(path.resolve(), page.parent.resolve()).replace(os.sep, "/"), safe="/#:")


def local_path(value: str, source: Path) -> Path | None:
    value = unquote(value.strip().strip("<>"))
    if value.startswith("res://"):
        value = value[6:]
    if value.startswith(("http://", "https://", "#")):
        return None
    value = re.sub(r":\d+$", "", value)
    candidates = [Path(value)] if Path(value).is_absolute() else [source.parent / value, ROOT / value]
    for candidate in candidates:
        if candidate.exists() and candidate.resolve().is_relative_to(ROOT):
            return candidate.resolve()
    return None


def link(path: Path, label: str, page: Path) -> str:
    return f'<a href="{href(path, page)}">{escape(label)}</a>'


def inline(text: str, source: Path, page: Path) -> str:
    chunks = []
    position = 0
    pattern = r"!?\[[^\]]+\]\([^)]+\)|`[^`]+`|\*\*[^*]+\*\*"
    for match in re.finditer(pattern, text):
        chunks.append(escape(text[position:match.start()]))
        token = match.group()
        if token.startswith("`"):
            value = token[1:-1]
            resolved = local_path(value, source)
            chunks.append(link(resolved, value, page) if resolved else f"<code>{escape(value)}</code>")
        elif token.startswith("**"):
            chunks.append(f"<strong>{escape(token[2:-2])}</strong>")
        else:
            parts = re.match(r"(!?)\[([^\]]+)\]\(([^)]+)\)", token)
            image, label, target = parts.groups()
            resolved = local_path(target, source)
            target = href(resolved, page) if resolved else target if target.startswith(("https://", "http://", "#")) else "#"
            chunks.append(f'<img alt="{escape(label)}" src="{escape(target, quote=True)}" loading="lazy">' if image else f'<a href="{escape(target, quote=True)}">{escape(label)}</a>')
        position = match.end()
    chunks.append(escape(text[position:]))
    return "".join(chunks)


def markdown_html(text: str, source: Path, page: Path) -> str:
    """Render the headings, tables, lists, quotes and fenced code used by local reports."""
    lines = text.splitlines()
    result = []
    index = 0
    while index < len(lines):
        line = lines[index]
        if not line.strip():
            index += 1
            continue
        if line.startswith("```"):
            code = []
            index += 1
            while index < len(lines) and not lines[index].startswith("```"):
                code.append(lines[index]); index += 1
            result.append("<pre><code>" + escape("\n".join(code)) + "</code></pre>")
        elif index + 1 < len(lines) and line.lstrip().startswith("|") and re.match(r"^\s*\|[\s:|\-]+\|\s*$", lines[index + 1]):
            cells = lambda row: [cell.strip() for cell in row.strip().strip("|").split("|")]
            result.append("<div class='scroll'><table><thead><tr>" + "".join("<th>" + inline(c, source, page) + "</th>" for c in cells(line)) + "</tr></thead><tbody>")
            index += 2
            while index < len(lines) and lines[index].lstrip().startswith("|"):
                result.append("<tr>" + "".join("<td>" + inline(c, source, page) + "</td>" for c in cells(lines[index])) + "</tr>")
                index += 1
            result.append("</tbody></table></div>")
            continue
        elif re.match(r"^#{1,6} ", line):
            level = len(line) - len(line.lstrip("#"))
            result.append(f"<h{level}>" + inline(line[level:].strip(), source, page) + f"</h{level}>")
        elif line.startswith(">"):
            result.append("<blockquote>" + inline(line.lstrip("> "), source, page) + "</blockquote>")
        elif re.match(r"^\s*(?:[-*]|\d+\.)\s", line):
            ordered = bool(re.match(r"^\s*\d+\.", line))
            tag = "ol" if ordered else "ul"
            result.append("<" + tag + ">")
            while index < len(lines) and re.match(r"^\s*(?:[-*]|\d+\.)\s", lines[index]):
                result.append("<li>" + inline(re.sub(r"^\s*(?:[-*]|\d+\.)\s+", "", lines[index]), source, page) + "</li>")
                index += 1
            result.append("</" + tag + ">")
            continue
        elif re.match(r"^[-_]{3,}\s*$", line):
            result.append("<hr>")
        else:
            result.append("<p>" + inline(line, source, page) + "</p>")
        index += 1
    return "\n".join(result)


def wrap(title: str, content: str, page: Path, subtitle: str = "") -> str:
    return f'''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{escape(title)} · 场景评分</title><style>{CSS}</style></head><body><header><div class="eyebrow">DUAL ONTOLOGY · EVIDENCE REVIEW</div><h1>{escape(title)}</h1><p class="lede">{escape(subtitle)}</p><nav>{link(OUT / 'gameplay.html', '游戏场景评分', page)}{link(OUT / 'index.html', '全部评分与报告', page)}{link(OUT / '评分总览.md', 'Markdown 总览', page)}{link(OUT / 'score_records.json', '结构化记录', page)}</nav></header><main>{content}<footer>导出于 {datetime.now().astimezone().isoformat(timespec='seconds')} · 原始采集与报告保留原文件。此页面支持直接打开和打印。</footer></main><div id="lightbox" class="lightbox" hidden><button class="close" type="button">关闭 · Esc</button><img alt="证据原图"></div><script>{JS}</script></body></html>'''


def image_figure(path: Path, page: Path, caption: str = "") -> str:
    digest = sha256(path.read_bytes()).hexdigest()
    provenance_text = "模型生成参考" if path.parent.name == "imagegen" else "原始截图 / 关联序列"
    try:
        checked = provenance.verify_image(path, ROOT, allow_fixture=True)
        provenance_text = "当前工程 · SHA256 已核验"
        if "development" in checked.get("capture_kind", ""):
            provenance_text += " · 开发预览"
    except (ValueError, OSError, KeyError):
        if "/sheets/" in path.as_posix() or "contact" in path.name:
            provenance_text = "派生序列表 · 原帧见报告"
    return f'<figure><a class="zoom" href="{href(path, page)}"><img loading="lazy" src="{href(path, page)}" alt="{escape(caption or path.name)}"></a><figcaption><b>{escape(caption or path.name)}</b><br><span class="meta">{escape(provenance_text)} · {digest[:12]}</span><br>{link(path, "原图", page)} · {escape(path.relative_to(ROOT).as_posix())}</figcaption></figure>'


def gallery(paths: list[Path], page: Path) -> str:
    return '<div class="gallery">' + "".join(image_figure(p, page) for p in paths) + "</div>"


def collect_runs(annotations: dict) -> list[dict]:
    records = []
    for run in sorted((ROOT / "artifacts/acceptance").glob("terra-*/runs/*")):
        if not (run / "frames.csv").is_file():
            continue
        with (run / "frames.csv").open(encoding="utf-8-sig", newline="") as stream:
            frames = list(csv.DictReader(stream))
        times = [float(f["frame_ms"]) for f in frames]
        timeline = yaml.safe_load((run / "timeline.yaml").read_text(encoding="utf-8-sig"))
        samples = timeline.get("timeline", [])
        text_counts = [s.get("total_visible_characters", s.get("content_text", {}).get("characters")) for s in samples]
        text_counts = [n for n in text_counts if n is not None]
        audio = read_json(run / "audio.json", {})
        ordered = sorted(times)
        key = run.parents[1].name + "/" + run.name
        note = annotations.get(key, {})
        historical = run.parents[1].name == "terra-workbench-20261116" and run.name.startswith(("lighting", "sleeve"))
        maximum = max(text_counts, default=None)
        limit = 25 if run.name in ("kitchen", "reconstruction") else 40
        scores = [None] * 7
        reasons = ["待评"] * 7
        spikes = sum(t > 33.3 for t in times)
        if timeline["metadata"].get("measurement_context") == "rendered_runtime" and spikes:
            scores[0] = 6
            reasons[0] = f"{spikes} 次 >33.3 ms，最大 {max(times):.3f} ms。按用户阈值计 6。"
        if maximum is not None and not (historical and run.name.startswith("lighting")):
            scores[1] = 10 if maximum == 0 else 8 if maximum <= limit else 6
            reasons[1] = f"后台采样最大 {maximum} 字，限制 {limit} 字；自动测量记录。"
        elif historical and run.name.startswith("lighting"):
            reasons[1] = f"历史计数 {maximum}，当时包含隐藏 Label3D，已被复采替代。"
        if note.get("action_score") is not None:
            scores[2] = note["action_score"]
            reasons[2] = note["reason"]
        loudness, peak = audio.get("integrated_lufs"), audio.get("true_peak_dbtp")
        if audio.get("signal_present") and isinstance(loudness, (int, float)) and isinstance(peak, (int, float)) and all(math.isfinite(v) for v in (loudness, peak)):
            scores[3] = 8 if loudness < -20 and peak < 0 else 6
            reasons[3] = f"{loudness:.3f} LUFS / {peak:.3f} dBTP；按平均响度与无削波阈值计算。"
        else:
            reasons[3] = "音频无检测信号，LUFS / dBTP 缺测。"
        row = {"id": key, "label": RUN_LABELS.get(run.name, run.name), "scope": "history" if historical else "current", "bundle": run.parents[1].name,
               "run_path": run.relative_to(ROOT).as_posix(), "scene_limit": limit, "frame_samples": len(times), "spikes_over_33_3_ms": spikes,
               "max_frame_ms": max(times), "p95_ms": ordered[max(0, math.ceil(len(times)*.95)-1)], "p99_ms": ordered[max(0, math.ceil(len(times)*.99)-1)],
               "avg_fps": len(times)*1000/sum(times), "max_characters": maximum, "audio": {k:audio.get(k) for k in ("status","signal_present","integrated_lufs","true_peak_dbtp","duration_s")},
               "scores": scores, "score_reasons": reasons, "annotation": note, "acceptance": "incomplete", "overall_passed": False,
               "metric_sources": {p.name: {"path": p.relative_to(ROOT).as_posix(), "sha256":sha256(p.read_bytes()).hexdigest()} for p in (run / "frames.csv",run / "timeline.yaml",run / "audio.json") if p.is_file()},
               "previews": [p.relative_to(ROOT).as_posix() for p in sorted(run.rglob("*.jpg")) if "sheets" in p.parts or "contact" in p.name]}
        records.append(row)
    return sorted(records, key=lambda r: (r["scope"] != "current", -int(r["bundle"].rsplit("-",1)[-1]), r["bundle"], r["label"]))


def canonical_images(base: Path) -> list[Path]:
    paths = [p for p in base.rglob("*") if p.suffix.lower() in (".png", ".jpg")]
    primary = [p for p in paths if "captures" in p.parts or "sheets" in p.parts or "expressions" in p.parts or "frames" in p.parts or ("mocap" in p.parts and p.name.startswith("preview-"))]
    return sorted(primary or paths)


def linked_markdown(text: str, source: Path) -> str:
    """Keep local links usable when a report moves into the review folder."""
    def replace(match):
        prefix, label, target = match.groups()
        resolved = local_path(target, source)
        if resolved is None:
            return match.group()
        return f'{prefix}[{label}](<{resolved.as_posix()}>)'
    return re.sub(r'(!?)\[([^\]]*)\]\((<?[^)]+>?)\)', replace, text)


def review_timeline(scene: dict, history: list[dict], page: Path) -> tuple[str, str]:
    label = scene['label']
    body = '<section id="trajectory-' + escape(scene['id']) + '"><h2>' + escape(label) + ' · 迭代轨迹</h2>'
    md = '\n## ' + label + ' · 迭代轨迹\n'
    if not history:
        return body + '<p class="muted">待独立 Terra 抵达该主线段落。</p></section>', md + '\n待独立 Terra 抵达该主线段落。\n'
    previous = None
    superseded = {record['supersedes'] for record in history if record.get('supersedes')}
    for record in history:
        captured = capture_time(record, ROOT).isoformat(timespec='seconds')
        title = '采集 ' + captured + ' · ' + record['revision'][:8] + ' · ' + record['status']
        if record.get('source_isolated'):
            title += ' · 历史来源已隔离'
        body += '<article class="trajectory-entry"><h3>' + escape(title) + '</h3><p class="meta">' + escape(record['reviewer'] + ' / ' + record['source']['session_id']) + '</p>'
        audit = '评分核定 ' + record['observed_at']
        if record['id'] in superseded:
            audit += ' · 已有追加核定，原记录保留'
        if record.get('supersedes'):
            audit += ' · 核定记录 ' + record['supersedes']
        body += '<p class="meta">' + escape(audit) + '</p>'
        body += '<div class="scroll"><table><tr>' + ''.join('<th>' + d + '</th>' for d in DIMENSIONS) + '</tr><tr>'
        md += '\n### ' + title + '\n\n| ' + ' | '.join(DIMENSIONS) + ' |\n|' + ' --- |' * 7 + '\n| '
        for index, score in enumerate(record['scores']):
            css = '' if score is None else 'ok' if score >= 8 else 'fail'
            delta = ''
            if previous and score is not None and previous['scores'][index] is not None:
                difference = score - previous['scores'][index]
                delta = f' ({difference:+g})'
            text = '待评' if score is None else str(score) + delta
            body += '<td><span class="score ' + css + '">' + escape(text) + '</span></td>'
            md += text + ' | '
        md += '\n'
        md += '\n' + audit + '\n'
        body += '</tr></table></div>'
        if record.get('summary'):
            body += '<p>' + escape(record['summary']) + '</p>'
            md += '\n' + record['summary'] + '\n'
        body += '<ul>' + ''.join('<li>' + escape(d + '：' + str(reason)) + '</li>' for d, reason in zip(DIMENSIONS, record['score_reasons']) if reason) + '</ul>'
        if record.get('metrics'):
            measurement = read_json(ROOT / record['metrics'], {}).get('segments', {}).get(scene['id'], {})
            if measurement:
                performance = f"{measurement['frame_samples']:,} 帧 · 平均 {measurement['avg_fps']:.1f} FPS · P95/P99 {measurement['frame_p95_ms']:.2f}/{measurement['frame_p99_ms']:.2f} ms · {measurement['spikes_over_33_3_ms']} 次尖峰 · 最大 {measurement['max_frame_ms']:.2f} ms"
                body += '<p class="note">' + escape(performance) + '</p><p>' + link(ROOT / record['metrics'], '该段原始指标与音频分析', page) + '</p>'
                md += '\n' + performance + '\n'
        for dimension, reason in zip(DIMENSIONS, record['score_reasons']):
            if reason: md += '\n- ' + dimension + '：' + str(reason)
        images = [ROOT / image['path'] for image in record['images']]
        if previous:
            before = ROOT / previous['images'][-1]['path']
            body += '<div class="compare">' + image_figure(before, page, '上一轮 · ' + previous['revision'][:8]) + image_figure(images[0], page, '本轮 · ' + record['revision'][:8]) + '</div>'
        body += gallery(images, page)
        for image in record['images']:
            md += '\n\n![' + image.get('caption', label) + '](<' + (ROOT / image['path']).as_posix() + '>)\n'
        report = ROOT / record['report']
        converted = OUT / 'reports' / ('--'.join(report.relative_to(ROOT).with_suffix('').parts[1:]) + '.html')
        body += '<p class="links">' + link(converted, '完整图文报告', page) + link(report, '原始评审', page) + link(ROOT / record['source']['on_receipt'], '启动回执', page) + link(ROOT / record['source']['start_receipt'], '新游戏回执', page) + '</p></article>'
        md += '\n[原始评审](<' + report.as_posix() + '>)\n'
        if record['id'] not in superseded and not record.get('source_isolated'):
            previous = record
    return body + '</section>', md


def gameplay_pages(records: list[dict]) -> tuple[str, str, list[dict]]:
    plan = read_json(ROOT / "assets/data/test_scenarios/gameplay_review_plan.json", {"scenes": []})
    reviews = read_json(ROOT / "artifacts/acceptance/gameplay_reviews.json", {})
    history = load_reviews(ROOT)
    page = OUT / "gameplay.html"
    body = '<section id="gameplay"><h2>第一章 · 游戏场景测试评分</h2>'
    status = "当前工程等待独立 Terra 主线采集；历史评分与画面按原版本保留。"
    body += '<p class="note">' + escape(status) + '</p>'
    body += '<p class="rule">只沿正式标题、新游戏和真实玩家输入评价主线。每段保留所有版本、原图、输入回执、七项分数与原因；待测项随真实测试补齐。</p>'
    md = "# 第一章游戏场景测试评分\n\n" + status + "\n\n[打开图文 HTML](<" + page.as_posix() + ">)\n\n"
    header = '| 游戏段落 | ' + ' | '.join(DIMENSIONS) + ' | 测试状态 |\n| --- |' + ' --- |' * 8 + '\n'
    md += header
    body += '<div class="scroll"><table class="score-table"><thead><tr><th>游戏段落</th>' + ''.join('<th>' + d + '</th>' for d in DIMENSIONS) + '<th>测试状态</th></tr></thead><tbody>'
    entries = []
    by_run = {record['id']: record for record in records}
    fragments = []
    for scene in plan.get("scenes", []):
        versions = [record for record in history if record['segment_id'] == scene['id']]
        superseded = {record['supersedes'] for record in versions if record.get('supersedes')}
        effective = [record for record in versions if record['id'] not in superseded and not record.get('source_isolated')]
        review = effective[-1] if effective else {}
        scores = review.get("scores", [None] * 7)
        if len(scores) != 7 or any(s is not None and (isinstance(s, bool) or not isinstance(s, (int, float)) or not 0 <= s <= 10) for s in scores):
            raise ValueError("Invalid gameplay scores: " + scene['id'])
        if any(score is not None for score in scores) and not review.get("report"):
            raise ValueError("Gameplay scores require an independent source report: " + scene['id'])
        label = scene['label']
        state = review.get('status', '待独立玩家测试记录')
        report = local_path(review['report'], ROOT / 'artifacts/acceptance/gameplay_reviews.json') if review.get('report') else None
        if review.get('report') and report is None:
            raise ValueError('Missing gameplay review report: ' + scene['id'])
        body += '<tr><td><a href="#trajectory-' + escape(scene['id']) + '"><b>' + escape(label) + '</b></a><div class="meta">' + escape(' / '.join(scene['rooms'])) + ' · ' + str(len(versions)) + ' 轮</div></td>'
        for score in scores:
            cls = '' if score is None else 'ok' if score >= 8 else 'fail'
            body += f'<td><span class="score {cls}">{score if score is not None else "待评"}</span></td>'
        body += '<td>' + escape(state) + (('<br>' + link(report, '独立测试报告', page)) if report else '') + '</td></tr>'
        md += '| ' + label + ' | ' + ' | '.join(str(s) if s is not None else '待评' for s in scores) + ' | ' + state + ' |\n'
        entries.append({**scene, **review, "scores": scores, "status": state, "history": versions})
        fragment = by_run.get(scene.get('fragment_run'))
        if fragment:
            fragments.append((scene, fragment))
    body += '</tbody></table></div></section>'
    for scene in plan.get('scenes', []):
        section, markdown = review_timeline(scene, [record for record in history if record['segment_id'] == scene['id']], page)
        body += section
        md += markdown
    body += '<section><details><summary>历史辅助采集归档 · 已停止，排除于主线评价</summary><p class="rule">以下旧 Mock 片段保留供追溯。</p>'
    md += '\n## 历史辅助采集归档（已停止，排除于主线评价）\n\n'
    for scene, fragment in fragments:
        body += '<h3>' + escape(scene['label']) + '</h3><div class="scroll"><table><tr>' + ''.join('<th>' + d + '</th>' for d in DIMENSIONS) + '</tr><tr>'
        for score in fragment['scores']:
            body += '<td>' + (str(score) if score is not None else '待评') + '</td>'
        body += '</tr></table></div><ul>' + ''.join('<li>' + escape(d + '：' + reason) + '</li>' for d, reason in zip(DIMENSIONS, fragment['score_reasons']) if reason != '待评') + '</ul>'
        run = ROOT / fragment['run_path']
        previews = [ROOT / p for p in fragment['previews']] or sorted(run.rglob('*.png'))[:3]
        if previews:
            body += gallery(previews, page)
        body += '<p>' + link(OUT / 'index.html', '全部指标、原图和报告', page) + '</p>'
        md += '\n### ' + scene['label'] + '\n\n' + header
        md += '| ' + scene['label'] + ' | ' + ' | '.join(str(s) if s is not None else '待评' for s in fragment['scores']) + ' | 片段采集 |\n'
        for preview in previews:
            md += f'\n![{preview.stem}](<{preview.as_posix()}>)\n'
    body += '</details></section>'
    page.write_text(wrap('第一章游戏场景测试评分', body, page, '按实际游戏段落查看测试进度、七项评分与运行画面。'), encoding='utf-8')
    (OUT / '游戏场景评分.md').write_text(md, encoding='utf-8')
    return body, md, entries


def report_page(source: Path) -> tuple[Path, list[Path]]:
    relative = source.relative_to(ROOT)
    page = OUT / "reports" / ("--".join(relative.with_suffix("").parts[1:]) + ".html")
    md_page = page.with_suffix(".md")
    page.parent.mkdir(parents=True, exist_ok=True)
    base = source.parent
    is_capture = base.name in REPORT_LABELS
    images = canonical_images(base) if is_capture and source.name in ("CAPTURE_REPORT.md", "BASELINE.md", "CAPTURE_PATH_VERIFICATION.md") else []
    if source.name == "BLIND_REVIEW.md":
        images = [ROOT / "artifacts/acceptance/terra-workbench-20261116/runs/interaction/sheets/wardrobe.jpg"]
    history = base.name == "terra-20261115" or source.name in ("FORMAL_UI_AUDIT.md", "provenance_verification.json")
    title = REPORT_LABELS.get(base.name, source.stem)
    text = source.read_text(encoding="utf-8-sig")
    top = '<div class="note">历史隔离记录：实际来源为 engine 工程，当前项目的评分与对照图继续使用正确来源采集。</div>' if history else ""
    body = f'<section class="report-body">{top}<div class="links">{link(source,"原始报告",page)}{link(md_page,"带图 Markdown",page)}</div>' + markdown_html(text, source, page) + "</section>"
    if images:
        body += f'<section><h2>关联画面 · {len(images)} 张</h2><p class="meta">点击放大；每张保留原图链接。序列表可追溯到原始截图。</p>' + gallery(images, page) + "</section>"
    page.write_text(wrap(title, body, page, source.relative_to(ROOT).as_posix()), encoding="utf-8")
    md = f"# {title}\n\n原始报告：[打开原文](<{source.as_posix()}>)\n\n" + linked_markdown(text, source)
    if images:
        md += "\n\n## 关联截图与序列\n"
        for image in images:
            md += f"\n### {image.name}\n\n![{image.name}]({image.as_posix()})\n\n[原始图片](<{image.as_posix()}>)\n"
    md_page.write_text(md, encoding="utf-8")
    return page, images


def validate_export() -> dict:
    class Links(HTMLParser):
        def __init__(self):
            super().__init__()
            self.links = []
            self.ids = set()

        def handle_starttag(self, tag, attrs):
            attrs = dict(attrs)
            if "id" in attrs:
                self.ids.add(attrs["id"])
            for name in ("href", "src"):
                if name in attrs:
                    self.links.append((tag, attrs[name]))

    documents = {}
    for path in OUT.rglob("*.html"):
        parsed = Links()
        parsed.feed(path.read_text(encoding="utf-8-sig"))
        documents[path.resolve()] = parsed
    broken = []
    checked = 0
    image_count = 0
    for page, parsed in documents.items():
        for tag, url in parsed.links:
            target = urlsplit(url)
            if target.scheme or url == "#":
                continue
            checked += 1
            path = (page.parent / unquote(target.path)).resolve() if target.path else page
            if not path.exists() or (target.fragment and path in documents and target.fragment not in documents[path].ids):
                broken.append({"page": str(page), "url": url})
            if tag == "img":
                image_count += 1
    for page in OUT.rglob("*.md"):
        for url in re.findall(r"!\[[^\]]*\]\(([^)]+)\)", page.read_text(encoding="utf-8-sig")):
            path = Path(unquote(url.strip().strip("<>")))
            if urlsplit(url.strip().strip("<>")).scheme in ("http", "https"):
                continue
            if not path.is_absolute() or not path.is_file():
                broken.append({"page": str(page), "image": url})
    data = read_json(OUT / "score_records.json")
    if data["overall_passed"] or any(r["overall_passed"] or len(r["scores"]) != 7 for r in data["runs"]):
        raise ValueError("Incomplete reviews must retain the incomplete acceptance state")
    report = {"generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
              "html_files": len(documents), "markdown_files": len(list(OUT.rglob("*.md"))),
              "local_links_checked": checked, "html_image_instances": image_count,
              "broken_links": broken, "scores_verified": len(data["runs"]), "overall_passed": False}
    (OUT / "export-verification.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    if broken:
        raise ValueError(f"Export contains {len(broken)} broken local links; see export-verification.json")
    return report


def main() -> int:
    global OUT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=OUT)
    args = parser.parse_args()
    OUT = provenance.project_path(args.output, ROOT)
    OUT.mkdir(parents=True, exist_ok=True)
    annotations = read_json(ROOT / "artifacts/acceptance/score_annotations.json", {})
    records = collect_runs(annotations.get("annotations", {}))
    gameplay_body, gameplay_md, gameplay_entries = gameplay_pages(records)
    manifest = read_json(ROOT / "assets/data/test_scenarios/reference_manifest.json", {})
    refs = [r for r in manifest.get("entries", []) if r.get("status") == "ready_for_comparison" and r.get("reference_image")]
    reports = sorted((ROOT / "artifacts/acceptance").rglob("*.md"))
    reports += sorted((ROOT / "artifacts/references").rglob("*.md"))
    reports += [ROOT / p for p in ("docs/采集路径修复.md", "docs/剧情重构实施状态.md", "docs/第一章可玩版本范围.md", "docs/主线评分轨迹.md", "docs/代码依赖与清理.md")]
    converted = []
    for source in reports:
        if source.is_file():
            page, images = report_page(source)
            converted.append({"source":source.relative_to(ROOT).as_posix(),"html":page.relative_to(ROOT).as_posix(),"markdown":page.with_suffix('.md').relative_to(ROOT).as_posix(),"images":len(images)})
    data = {"schema_version":1,"generated_at":datetime.now().astimezone().isoformat(timespec="seconds"),"dimensions":DIMENSIONS,"overall_passed":False,
            "scoring_basis":"Threshold entries recomputed from archived CSV/YAML/audio. Subjective missing reviews remain null. Visual-only blind scores are separate from audiovisual narrative acceptance.",
            "runs":records,"gameplay_scenes":gameplay_entries,"text_exemptions":read_json(ROOT/'assets/data/test_scenarios/text_exemptions.json'),"converted_reports":converted,"references_ready":len(refs),"references_accepted":0}
    (OUT / "score_records.json").write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding="utf-8")
    page = OUT / "index.html"
    current = [r for r in records if r["scope"]=="current"]
    body = gameplay_body + '<div class="stats">' + ''.join(f'<div class="stat"><b>{v}</b><span>{k}</span></div>' for k,v in [("当前采集会话",len(current)),("已导出报告",len(converted)),("可比较参考图",len(refs)),("七项全部通过",0)]) + '</div>'
    body += '<section id="scores"><h2>七项评分记录</h2><p class="rule">绿色为单项阈值满足，红色为已确认失败，灰色为待评。字数来自后台采样；视听盲测、美学相似度与剧情评审保留待评。总体验收持续进行。</p><div class="toolbar"><input id="search" aria-label="搜索场景" placeholder="搜索场景或采集批次"><select id="scope" aria-label="记录范围"><option value="all">全部记录</option><option value="current">当前使用</option><option value="history">历史复采 / 缺项记录</option></select></div><div class="scroll"><table class="score-table"><thead><tr><th>场景 / 采集批次</th>' + ''.join(f'<th>{d}</th>' for d in DIMENSIONS) + '<th>状态</th></tr></thead><tbody>'
    md = "# 采集与评分总览\n\n更新：" + data["generated_at"] + "\n\n[游戏场景评分](<" + (OUT / '游戏场景评分.md').as_posix() + ">) · [打开 HTML 总览](<" + page.as_posix() + ">)\n\n已确认的阈值分与待评项目分别保留；七项全部通过数：0。\n\n| 场景 | " + " | ".join(DIMENSIONS) + " | 状态 |\n| --- |" + " --- |"*8 + "\n"
    for index, record in enumerate(records):
        record["anchor"] = f"run-{index}"
        scope = "历史" if record["scope"]=="history" else "当前"
        body += f'<tr data-search="{escape(record["label"]+" "+record["bundle"],quote=True)}" data-scope="{record["scope"]}"><td><a href="#{record["anchor"]}"><b>{escape(record["label"])}</b></a><div class="meta">{escape(record["bundle"])}</div></td>'
        for score, reason in zip(record["scores"], record["score_reasons"]):
            cls = "" if score is None else "fail" if score<8 else "ok"
            body += f'<td><span class="score {cls}" title="{escape(reason,quote=True)}">{score if score is not None else "待评"}</span></td>'
        body += f'<td><span class="badge">{scope} · 待完成</span></td></tr>'
        md += f'| {record["label"]}（{record["bundle"]}） | ' + ' | '.join(str(s) if s is not None else "待评" for s in record["scores"]) + ' | 待完成 |\n'
    body += '</tbody></table></div><div class="note">标题菜单与标题入口的书本设置页按用户批准豁免字数，保留现有布局。剧情案卷和推演保持 25 字上限；辅助测试场景 40 字。</div><details><summary>评分依据与盲测现有记录</summary><p>任一 &gt;33.3 ms 帧尖峰 → 流畅度 6；任一错误人物动作 → 动作维度 6。无字 10，限制内 8。响度低于 −20 LUFS 且无削波时记阈值 8；缺测保留待评。</p><p>衣柜视觉盲测：画面传意 6/10，叙事连贯性 5/10。评审者未能试听音频，视听剧情替代度继续待评。</p>' + link(ROOT/'artifacts/acceptance/blind-wardrobe-20261116/BLIND_REVIEW.md','盲测原始归档',page) + '</details></section>'
    body += '<section><h2>场景证据与指标</h2>'
    for record in records:
        run = ROOT / record["run_path"]
        body += f'<article class="run-details" id="{record["anchor"]}" data-search="{escape(record["label"]+" "+record["bundle"],quote=True)}" data-scope="{record["scope"]}"><h3>{escape(record["label"])}</h3><p class="meta">{escape(record["run_path"])}</p><p>{record["frame_samples"]:,} 帧 · 平均 {record["avg_fps"]:.1f} FPS · P95 / P99 {record["p95_ms"]:.2f} / {record["p99_ms"]:.2f} ms · <b>{record["spikes_over_33_3_ms"]} 次尖峰</b> · 最大 {record["max_frame_ms"]:.3f} ms</p>'
        body += '<ul>' + ''.join(f'<li>{escape(d)}：{escape(reason)}</li>' for d,reason in zip(DIMENSIONS,record["score_reasons"]) if reason!="待评") + '</ul>'
        if record["annotation"].get("visual_clarity_score"):
            body += '<p class="note">衣柜视觉盲测：画面传意 6/10，连贯性 5/10；音频评审待完成。</p>'
        body += '<div class="links">' + ''.join(link(run/f,f,page) for f in ("frames.csv","timeline.yaml","audio.json","mix.wav","events.json") if (run/f).is_file()) + '</div>'
        previews = [ROOT/p for p in record["previews"]]
        if not previews:
            previews = sorted(run.rglob('*.png'))[:6]
        if previews:
            body += gallery(previews,page)
        body += '</article>'
        md += f'\n## {record["label"]} · {record["bundle"]}\n\n'
        md += '\n'.join(f'- {d}：{reason}' for d,reason in zip(DIMENSIONS,record['score_reasons']) if reason!='待评') + '\n\n'
        md += ' '.join(f'[{name}](<{(run/name).as_posix()}>)' for name in ('frames.csv','timeline.yaml','audio.json','mix.wav') if (run/name).is_file()) + '\n'
        for preview in previews:
            md += f'\n![{preview.stem}]({preview.as_posix()})\n'
    body += f'</section><section id="references"><h2>实机与 Astra 参考图</h2><p class="meta">{len(refs)} 张可比较参考；相似度均待评分。点击图片放大。</p>'
    md += '\n## 实机与 Astra 参考图\n\n相似度评分均待完成。\n'
    for ref in refs:
        reference = ROOT/ref['reference_image']
        sources = ref.get('source_images',[])
        source = next((ROOT/s['path'] for s in sources if isinstance(s,dict) and s.get('path') and (ROOT/s['path']).is_file()),None)
        body += f'<h3>{escape(ref["label"])}</h3><div class="compare">'
        if source:
            body += image_figure(source,page,"实机来源 · "+source.name)
        body += image_figure(reference,page,"Astra 参考 · 待评分") + '</div>'
        md += f'\n### {ref["label"]}\n\n'
        if source:
            md += f'![实机来源]({source.as_posix()})\n\n'
        md += f'![Astra参考]({reference.as_posix()})\n'
    body += '</section><section id="reports"><h2>全部报告 · HTML / Markdown</h2><div class="grid">'
    md += '\n## 全部报告\n\n'
    for item in converted:
        source = ROOT/item['source']; destination = ROOT/item['html']
        title = REPORT_LABELS.get(source.parent.name,source.stem)
        body += f'<div class="card report-card"><b>{escape(title)}</b><div class="meta">{escape(item["source"])}</div><p>{item["images"]} 张关联画面</p><div class="links">{link(destination,"图文 HTML",page)}{link(destination.with_suffix(".md"),"带图 Markdown",page)}{link(source,"原报告",page)}</div></div>'
        md += f'- {title}：[HTML](<{destination.as_posix()}>) · [带图 Markdown](<{destination.with_suffix(".md").as_posix()}>) · [原报告](<{source.as_posix()}>)\n'
    body += '</div></section>'
    page.write_text(wrap('采集与评分记录',body,page,'按场景查看七项记录、实际画面、参考图和原始测量。'),encoding='utf-8')
    (OUT/'评分总览.md').write_text(md,encoding='utf-8')
    (OUT/'score_records.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
    verification = validate_export()
    print(json.dumps({'html':str(page),'markdown':str(OUT/'评分总览.md'),'reports':len(converted),'runs':len(records),'images':sum(x['images'] for x in converted),'references':len(refs),'links_checked':verification['local_links_checked'],'broken_links':len(verification['broken_links'])},ensure_ascii=False))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
