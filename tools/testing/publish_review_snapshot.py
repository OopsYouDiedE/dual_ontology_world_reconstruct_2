"""Explicitly export a portable copy of the current seven-dimension report."""
from __future__ import annotations

import argparse
import hashlib
from html import escape
from pathlib import Path
import shutil
from urllib.parse import unquote, urlsplit

import export_review_site as review
import test_results


def select_frames(images):
    if len(images) <= 3:
        return images
    return [images[0], images[len(images) // 2], images[-1]]


def copy_evidence(path, output):
    """Copy a project-local evidence file under a stable content-addressed name."""
    path = review.project_file(path)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    name = digest + path.suffix.lower()
    destination = output / 'images' / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    if not destination.exists() or hashlib.sha256(destination.read_bytes()).hexdigest() != digest:
        shutil.copyfile(path, destination)
    return 'images/' + name


def frame_strip(images, output):
    rendered = []
    for image in select_frames(images):
        path = review.project_file(image['path'])
        expected = image.get('sha256')
        if expected and hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError('Screenshot hash mismatch: ' + str(image['path']))
        url = escape(copy_evidence(path, output), quote=True)
        caption = escape(image.get('caption', path.stem))
        rendered.append('<figure><a href="' + url + '"><img loading="lazy" src="' + url
                        + '" alt="' + caption + '"></a><figcaption>' + caption + '</figcaption></figure>')
    return '<div class="trajectory">' + ''.join(rendered) + '</div>' if rendered else ''


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
    if output == allowed_root or not output.is_relative_to(allowed_root) or source.is_relative_to(output):
        raise ValueError('Snapshot output must be a separate directory inside .runtime')
    data = review.read_json(source)
    if not isinstance(data, dict) or data.get('schema_version') != 3 or len(data.get('dimensions', [])) != 7:
        raise ValueError('A schema 3 seven-category score record is required')
    scenes = data.get('gameplay_scenes', [])
    if not scenes or any(len(entry.get('scores', [])) != 7 for entry in scenes):
        raise ValueError('Each chapter segment must contain seven score values')
    latest = {}
    for entry in scenes:
        result = entry.get('test')
        if result is None:
            if any(value is not None for value in entry['scores']):
                raise ValueError('Scores require a test record')
            continue
        if (not isinstance(result, dict) or result.get('segment_id') != entry.get('id')
                or result.get('scores') != entry['scores'] or len(result.get('reasons', [])) != 7):
            raise ValueError('Each score must belong to its displayed test')
        test_results.normalize(result['id'], result['segment_id'], result['revision'], result['at'],
                               result['scores'], result['reasons'])
        latest[entry['id']] = result
    output.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(Path(__file__).parent / 'review.css', output / 'review.css')

    def portable_link(path, label, page):
        url = escape(copy_evidence(path, output), quote=True)
        return '<a href="' + url + '">' + escape(str(label)) + '</a>'

    def portable_trajectory(images, page):
        return frame_strip(images, output)

    body = test_results.matrix(scenes, latest)
    body += ''.join(test_results.card(scene, latest.get(scene['id']), output / 'index.html',
                                     portable_link, review.project_file, portable_trajectory)
                    for scene in scenes)
    html = ('<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width,initial-scale=1">'
            '<title>第一章 · 测试评分</title><link rel="stylesheet" href="review.css"></head>'
            '<body><header><div class="brand">DUAL ONTOLOGY · CHAPTER 01</div>'
            '<h1>第一章 · 测试评分</h1><p>报告版本 ' + escape(data.get('revision', ''))
            + ' · 生成时间 ' + escape(data.get('generated_at', ''))
            + '</p><p><a href="index.html">评分总览</a> · <a href="gameplay.html">游戏场景评分</a>'
            + ' · <a href="scoring_overview.md">Markdown 总览</a></p></header><main>' + body + '</main></body></html>')
    for name in ('index.html', 'gameplay.html'):
        (output / name).write_text(html, encoding='utf-8')
    (output / 'scoring_overview.md').write_text(
        test_results.markdown(scenes, latest, data.get('revision', '')), encoding='utf-8')
    return validate(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=review.OUT / 'score_records.json')
    parser.add_argument('--output', type=Path, default=review.ROOT / '.runtime/review-export/portable')
    args = parser.parse_args()
    review.provenance.assert_runtime_root(review.ROOT)
    print('Snapshot local links checked:', publish(args.source, args.output))


if __name__ == '__main__':
    main()
