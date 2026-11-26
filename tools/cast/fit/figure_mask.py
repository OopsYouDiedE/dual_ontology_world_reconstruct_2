"""Figure mask of a painting, seeded by the retopo mesh's own silhouette (GrabCut in a narrow band).

    python figure_mask.py --hero quer --render <front render png> --det <render landmarks json> --out <png>

The front render of the registered retopo mesh (flat background) gives a silhouette; a similarity on the
MediaPipe pose landmarks (render -> painting) carries it onto the painting. Well inside it is sure figure,
well outside sure background, and GrabCut decides the band between from the painting's colours. The mask
is eroded 2 px so the ink outline counts as outside. rig_retopo.py calls this for every hero.
"""
import argparse
import json
from pathlib import Path

import cv2
import numpy as np

REF = Path(__file__).resolve().parent.parent / "reference"
POSE_IDS = (0, 2, 5, 7, 8, 11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28)


def load(path, flag=cv2.IMREAD_COLOR):
    return cv2.imdecode(np.fromfile(str(path), np.uint8), flag)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--hero", required=True)
    p.add_argument("--render", type=Path, required=True)
    p.add_argument("--det", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    a = p.parse_args()
    man = json.loads((REF / "manifest.json").read_text(encoding="utf-8"))[a.hero]
    ref = json.loads((REF / "landmarks" / f"{a.hero}.json").read_text())
    det = json.loads(a.det.read_text())
    painting = load(REF / man["image"])
    render = load(a.render)
    sil = (np.abs(render.astype(int) - render[2, 2].astype(int)).sum(2) > 12).astype(np.uint8) * 255
    ids = [i for i in POSE_IDS if det["pose"][i][2] > 0.5 and ref["pose"][i][2] > 0.5]
    src = np.float32([det["pose"][i][:2] for i in ids])
    dst = np.float32([ref["pose"][i][:2] for i in ids])
    M, _ = cv2.estimateAffinePartial2D(src, dst)
    h, w = painting.shape[:2]
    prior = cv2.warpAffine(sil, M, (w, h), flags=cv2.INTER_NEAREST)
    tall = max(1, int(np.ptp(np.nonzero(prior)[0])))
    k = max(3, tall // 40)
    sure_fg = cv2.erode(prior, np.ones((k, k), np.uint8))
    maybe = cv2.dilate(prior, np.ones((2 * k, 2 * k), np.uint8))
    mask = np.full((h, w), cv2.GC_BGD, np.uint8)
    mask[maybe > 0] = cv2.GC_PR_BGD
    mask[prior > 0] = cv2.GC_PR_FGD
    mask[sure_fg > 0] = cv2.GC_FGD
    bgd, fgd = np.zeros((1, 65), np.float64), np.zeros((1, 65), np.float64)
    cv2.grabCut(painting, mask, None, bgd, fgd, 6, cv2.GC_INIT_WITH_MASK)
    fig = np.where((mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD), 255, 0).astype(np.uint8)
    fig = cv2.morphologyEx(fig, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    fig = cv2.erode(fig, np.ones((5, 5), np.uint8))
    a.out.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(a.out), fig)
    print("MASK", a.hero, int((fig > 0).sum()), "prior", int((prior > 0).sum()))


if __name__ == "__main__":
    main()
