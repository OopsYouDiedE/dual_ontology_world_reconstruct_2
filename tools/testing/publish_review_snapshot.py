"""Build a compact, portable snapshot of the generated Chapter 1 review."""
from __future__ import annotations

import argparse
import hashlib
from html import escape
from pathlib import Path
import shutil
from urllib.parse import unquote, urlsplit

import export_review_site as review


def select_frames(images):
    if len(images) <= 3:
        return images
    return [images[0], images[len(images) // 2], images[-1]]


def frame_strip(entry, output):
    images = entry.get('development_images', [])
    if not images:
        return '<p class="muted">开发截图待采集。</p>'
    rendered = []
    for image in select_frames(images):
        path = review.project_file(image['path'])
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        name = digest + path.suffix.lower()
        destination = output / 'images' / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        if not destination.exists() or hashlib.sha256(destination.read_bytes()).hexdigest() != digest:
            shutil.copyfile(path, destination)
        caption = escape(image.get('caption', path.stem))
        rendered.append('<figure><a class="zoom" href="images/' + name + '"><img loading="lazy" src="images/' + name + '" alt="' + caption + '"></a><figcaption>' + caption + '</figcaption></figure>')
    return '<div class="trajectory">' + ''.join(rendered) + '</div>'


def validate(output):
    pages = {}
    for page in output.glob('*.html'):
        parsed = review.Links()
        parsed.feed(page.read_text(encoding='utf-8'))
        pages[page.resolve()] = parsed
    checked = 0
    for page, parsed in pages.items():
        for _, url in parsed.links:
            target = urlsplit(url)
            if target.scheme or url == '#':
                continue
            checked += 1
            path = (page.parent / unquote(target.path)).resolve() if target.path else page
            if not path.is_relative_to(output.resolve()) or not path.exists():
                raise ValueError('Broken snapshot link: ' + url)
            if target.fragment and path in pages and target.fragment not in pages[path].ids:
                raise ValueError('Broken snapshot anchor: ' + url)
    return checked


def publish(source, output):
    source = review.provenance.project_path(source, review.ROOT)
    output = review.provenance.project_path(output, review.ROOT)
    allowed_root = (review.ROOT / '.runtime').resolve()
    published_root = (review.OUT / 'published').resolve()
    if output != published_root and not output.is_relative_to(allowed_root):
        raise ValueError('Snapshot output must be the published directory or a runtime sandbox')
    if output == allowed_root or source.is_relative_to(output):
        raise ValueError('Snapshot output must be separate from the source')
    data = review.read_json(source)
    if not isinstance(data, dict) or len(data.get('dimensions', [])) != 7:
        raise ValueError('A generated seven-category score record is required')
    entries = data.get('gameplay_scenes', [])
    if not entries or any(len(entry.get('scores', [])) != 7 for entry in entries):
        raise ValueError('Each chapter segment must contain seven score values')
    output.mkdir(parents=True, exist_ok=True)
    image_directory = output / 'images'
    for name in ('review.css', 'review.js'):
        shutil.copyfile(Path(__file__).parent / name, output / name)
    audit = data.get('history_evidence', {})
    status = '完整' if audit.get('complete') else '不完整 · 正式验收待评'
    counts = audit.get('counts', {})
    body = '<aside class="evidence-banner"><b>历史证据：' + status + '</b><p>' + escape(str(counts)) + '</p><p>本页为便携评分快照；完整轨迹、修订记录及证据请在原工程内生成完整报告。</p></aside>'
    for index, entry in enumerate(entries, 1):
        record = entry.get('current') or {}
        body += '<article class="segment" id="trajectory-' + escape(entry['id'], quote=True) + '"><h2>' + str(index).zfill(2) + ' · ' + escape(entry['label']) + '</h2>'
        body += '<p>开发截图 · 精选帧；正式验收以独立评审记录为准。</p>' + frame_strip(entry, output)
        body += '<h3>七项正式评分</h3>' + review.dimension_scores(record) + review.score_editor(record) + review.semantic_score_summary(entry.get('semantic')) + '</article>'
    html = ('<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>第一章 · 评分便携快照</title><link rel="stylesheet" href="review.css"></head><body><header><div class="brand">DUAL ONTOLOGY · CHAPTER 01</div><h1>第一章 · 评分便携快照</h1><p>报告版本 ' + escape(data.get('revision', '')) + ' · 生成时间 ' + escape(data.get('generated_at', '')) + '</p><p><a href="index.html">评分总览</a> · <a href="gameplay.html">游戏场景评分</a> · <a href="scoring_overview.md">Markdown 总览</a></p></header><main>' + body + '</main><dialog id="image-view"><button aria-label="关闭原图">关闭 · Esc</button><img alt="实机截图"></dialog><script src="review.js"></script></body></html>')
    for name in ('index.html', 'gameplay.html'):
        (output / name).write_text(html, encoding='utf-8')
    lines = ['# Chapter 1 scoring snapshot', '', 'Revision: ' + data.get('revision', ''), '', 'Historical evidence: ' + status, '']
    for entry in entries:
        record = entry.get('current') or {}
        scores = record.get('scores', [None] * 7)
        reasons = record.get('score_reasons', [None] * 7)
        lines += ['## ' + entry['label'], '']
        for label, score, reason in zip(data['dimensions'], scores, reasons):
            lines.append('- ' + label + ': ' + ('待评' if score is None else str(score) + '/10') + ' — ' + str(reason or '等待独立实机评审'))
        lines.append('')
    (output / 'scoring_overview.md').write_text('\n'.join(lines), encoding='utf-8')
    return validate(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=review.OUT / 'score_records.json')
    parser.add_argument('--output', type=Path, default=review.OUT / 'published')
    args = parser.parse_args()
    review.provenance.assert_runtime_root(review.ROOT)
    print('Snapshot local links checked:', publish(args.source, args.output))


if __name__ == '__main__':
    main()
