"""Review sheets for the landmark fit: painting vs fitted render vs baseline, with landmarks overlaid.

    python sheet.py --heroes detective,hale,quer,lucian --work .runtime/facefit --out <dir>

Per hero: face row (painting crop with painting landmarks in red and the fitted render's landmarks,
similarity-aligned onto the painting, in green; fitted render; baseline render) and a body row.
"""
import argparse
import json
from pathlib import Path

import cv2
import numpy as np

FIT = Path(__file__).resolve().parent
REF = FIT.parent / "reference"


def load(path):
    return cv2.imdecode(np.fromfile(str(path), dtype=np.uint8), cv2.IMREAD_COLOR)


def similarity(src, dst):
    mu_s, mu_d = src.mean(0), dst.mean(0)
    a, b = src - mu_s, dst - mu_d
    u, sig, vt = np.linalg.svd(b.T @ a)
    d = np.sign(np.linalg.det(u @ vt))
    rot = u @ np.diag([1, d]) @ vt
    s = (sig[0] + d * sig[1]) / (a ** 2).sum()
    return lambda p: s * (rot @ (p - mu_s).T).T + mu_d


def fit_h(img, h):
    return cv2.resize(img, (int(img.shape[1] * h / img.shape[0]), h), interpolation=cv2.INTER_AREA)


def label(img, text):
    cv2.putText(img, text, (8, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (255, 255, 255), 2, cv2.LINE_AA)
    return img


def hero_rows(hero, work, manifest, h=420):
    man = manifest[hero]
    src = load(REF / man["image"])
    ref = json.loads((work / "ref" / f"{hero}.json").read_text())
    fit = json.loads((work / f"{hero}-fit-face.json").read_text())
    rows = []
    x0, y0, x1, y1 = ref["face_box"]
    crop = src[y0:y1, x0:x1].copy()
    s = h / crop.shape[0]
    crop = cv2.resize(crop, None, fx=s, fy=s, interpolation=cv2.INTER_CUBIC)
    r = np.array([p[:2] for p in ref["face"][:468]])
    tiles = []
    if fit["face"]:
        f = np.array([p[:2] for p in fit["face"][:468]])
        on_ref = similarity(f, r)(f)
        for (ax, ay), (bx, by) in zip(r, on_ref):
            pa = (int((ax - x0) * s), int((ay - y0) * s))
            pb = (int((bx - x0) * s), int((by - y0) * s))
            cv2.line(crop, pa, pb, (0, 220, 255), 1)
            cv2.circle(crop, pa, 2, (40, 40, 255), -1)
            cv2.circle(crop, pb, 2, (60, 255, 60), -1)
    tiles.append(label(crop, f"{hero}: painting (red) / fit (green)"))
    for tag, name in (("fit", "fitted"), ("base", "baseline")):
        path = work / (f"{hero}-fit-face.png" if tag == "fit" else f"{hero}-base-fit-face.png")
        if path.exists():
            img = load(path)
            tiles.append(label(fit_h(img[96:672, 96:672], h), name))
    rows.append(np.hstack(tiles))
    body = [fit_h(src[man["box"][1]:man["box"][3], man["box"][0]:man["box"][2]], h * 2)]
    for path, name in ((work / f"{hero}-fit-body.png", "fitted"), (work / f"{hero}-base-fit-body.png", "baseline")):
        if path.exists():
            body.append(label(fit_h(load(path), h * 2), name))
    rows.append(np.hstack(body))
    return rows


def built_face_row(hero, work, manifest, h=420):
    """Painting face with painting (red) and built-GLB (green) landmarks, then the built close-up."""
    src = load(REF / manifest[hero]["image"])
    ref = json.loads((work / "ref" / f"{hero}.json").read_text())
    got = json.loads((work / "built" / f"{hero}-face.json").read_text())
    x0, y0, x1, y1 = ref["face_box"]
    crop = src[y0:y1, x0:x1].copy()
    plain = cv2.resize(crop, None, fx=h / crop.shape[0], fy=h / crop.shape[0], interpolation=cv2.INTER_CUBIC)
    s = h / crop.shape[0]
    marked = plain.copy()
    if got["face"]:
        r = np.array([q[:2] for q in ref["face"][:468]])
        f = np.array([q[:2] for q in got["face"][:468]])
        for (ax, ay), (bx, by) in zip(r, similarity(f, r)(f)):
            pa, pb = (int((ax - x0) * s), int((ay - y0) * s)), (int((bx - x0) * s), int((by - y0) * s))
            cv2.line(marked, pa, pb, (0, 220, 255), 1)
            cv2.circle(marked, pa, 2, (40, 40, 255), -1)
            cv2.circle(marked, pb, 2, (60, 255, 60), -1)
    img = load(work / "built" / f"{hero}-face.png")
    return np.hstack([label(plain, f"{hero}: painting"), label(marked, "red painting / green GLB"),
                      label(fit_h(img, h), "built GLB")])


def built_row(hero, work, manifest, h=900):
    """Painting next to the built GLB render (review_built.py), figures scaled to equal height."""
    man = manifest[hero]
    src = load(REF / man["image"])
    x0, y0, x1, y1 = man["box"]
    tiles = [label(fit_h(src[y0:y1, x0:x1], h), f"{hero}: painting")]
    img = load(work / "built" / f"{hero}.png")
    mask = (np.abs(img.astype(int) - img[2, 2].astype(int)).sum(2) > 18)
    ys, xs = np.nonzero(mask)
    pad = int(0.04 * (ys.max() - ys.min()))
    crop = img[max(0, ys.min() - pad):ys.max() + pad, max(0, xs.min() - pad * 3):xs.max() + pad * 3]
    score = json.loads((work / "built" / f"{hero}.json").read_text())
    text = " ".join(f"{k}={v}" for k, v in score.items())
    tiles.append(label(fit_h(crop, h), "built GLB"))
    row = np.hstack(tiles)
    cv2.putText(row, text, (8, h - 12), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 2, cv2.LINE_AA)
    return row


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--heroes", default="detective,hale,quer,lucian")
    p.add_argument("--work", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--built", action="store_true", help="sheet of built GLB renders instead of the fit")
    a = p.parse_args()
    manifest = json.loads((REF / "manifest.json").read_text(encoding="utf-8"))
    a.out.mkdir(parents=True, exist_ok=True)
    if a.built:
        rows = [built_row(h, a.work, manifest) for h in a.heroes.split(",")]
        cv2.imwrite(str(a.out / "built-sheet.jpg"), np.hstack(rows), [cv2.IMWRITE_JPEG_QUALITY, 88])
        faces = [built_face_row(h, a.work, manifest) for h in a.heroes.split(",")]
        w = max(f.shape[1] for f in faces)
        faces = [np.pad(f, ((0, 0), (0, w - f.shape[1]), (0, 0))) for f in faces]
        cv2.imwrite(str(a.out / "built-faces.jpg"), np.vstack(faces), [cv2.IMWRITE_JPEG_QUALITY, 90])
        print("SHEET built")
        return
    for hero in a.heroes.split(","):
        rows = hero_rows(hero, a.work, manifest)
        w = max(r.shape[1] for r in rows)
        rows = [np.pad(r, ((0, 0), (0, w - r.shape[1]), (0, 0))) for r in rows]
        cv2.imwrite(str(a.out / f"{hero}-fit-sheet.jpg"), np.vstack(rows), [cv2.IMWRITE_JPEG_QUALITY, 88])
        print("SHEET", hero)


if __name__ == "__main__":
    main()
