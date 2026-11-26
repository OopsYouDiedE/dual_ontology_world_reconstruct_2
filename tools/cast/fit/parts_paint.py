"""Recolour a Tripo part atlas from the hero's character sheet (called by build_tripo_parts.py).

    python parts_paint.py --hero quer --npz <hero>-paint.npz --tex <tripo atlas png> --out <albedo png>

Runs in the MediaPipe venv (numpy, OpenCV, SciPy). Inputs per vertex from Blender: rest position, normal,
part index, front visibility (faces the viewer and nothing in front), atlas UV, and the vertex's pixel in
a front render of the model whose pose and face landmarks were detected.

1. Render pixels map onto the sheet by a similarity on the pose landmarks; inside the face oval by a
   piecewise-affine warp on the 468 face landmarks (blended in from the oval edge).
2. The atlas is rasterised part by part. Each part's texels are split into up to three colour clusters
   (k-means in Lab, near-identical clusters merged): Tripo's own regions (lapel, lining, band, sole...).
3. Each cluster takes the median sheet colour under its front-visible vertices. Clusters seen only from
   behind borrow the median of their nearest seen vertices, matched on position and Tripo colour.
4. Texels become their cluster's flat colour, keeping an eighth of Tripo's lightness detail (seams, folds).
   The head part with its eyes and brows has its own unwrap (Tripo scatters faces over many atlas
   fragments) and its own texture: flat colours, with the sheet's face drawn through the warp.
"""
import argparse
import json
from pathlib import Path

import cv2
import numpy as np
from scipy.spatial import Delaunay, cKDTree

FIT = Path(__file__).resolve().parent
REF = FIT.parent / "reference"
OVAL = [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377, 152,
        148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109]
POSE_IDS = (0, 2, 5, 7, 8, 11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28)
DETAIL = 0.12


def similarity(src, dst):
    mu_s, mu_d = src.mean(0), dst.mean(0)
    a, b = src - mu_s, dst - mu_d
    u, sig, vt = np.linalg.svd(b.T @ a)
    d = np.sign(np.linalg.det(u @ vt))
    rot = u @ np.diag([1, d]) @ vt
    s = (sig[0] + d * sig[1]) / (a ** 2).sum()
    return lambda p: s * (rot @ (p - mu_s).T).T + mu_d


def to_lab(rgb_u8):
    return cv2.cvtColor(rgb_u8.reshape(-1, 1, 3), cv2.COLOR_RGB2LAB).reshape(-1, 3).astype(np.float32)


def to_rgb(lab):
    lab = np.clip(lab, 0, 255).astype(np.uint8)
    return cv2.cvtColor(lab.reshape(-1, 1, 3), cv2.COLOR_LAB2RGB).reshape(-1, 3)


def sample(img, x, y):
    h, w = img.shape[:2]
    xi = np.clip(np.round(x).astype(int), 0, w - 1)
    yi = np.clip(np.round(y).astype(int), 0, h - 1)
    return img[yi, xi]


def poly_dist(pts, poly):
    """Distance from points to a closed polyline."""
    d = np.full(len(pts), np.inf)
    for p, q in zip(poly, np.roll(poly, -1, axis=0)):
        e = q - p
        t = np.clip(((pts - p) @ e) / max(e @ e, 1e-12), 0, 1)
        d = np.minimum(d, np.linalg.norm(pts - (p + t[:, None] * e), axis=1))
    return d


PAIRS = json.loads((FIT / "face_pairs.json").read_text())


def symmetric(pts, pair, axis=None):
    """Average each landmark with its partner's mirror image. axis: (point, unit direction) of the
    symmetry line; fitted through the pair midpoints when not given."""
    if axis is None:
        mid = 0.5 * (pts + pts[pair])
        c = mid.mean(0)
        u = np.linalg.svd(mid - c)[2][0]
        u = u if u[1] >= 0 else -u
    else:
        c, u = axis

    def refl(p):
        d = p - c
        return c + 2 * np.outer(d @ u, u) - d

    out = 0.5 * (pts + refl(pts[pair]))
    # landmarks without a partner stay where they are, except the midline ones, which go onto the axis
    alone = (pair == np.arange(len(pair)))
    alone[PAIRS["midline"]] = False
    out[alone] = pts[alone]
    return out


def raster(tp, res):
    """Texels (x, y) inside one triangle given in pixels, with barycentric weights."""
    lo = np.floor(tp.min(0)).astype(int)
    hi = np.ceil(tp.max(0)).astype(int)
    xs, ys = np.meshgrid(np.arange(lo[0], hi[0] + 1), np.arange(lo[1], hi[1] + 1))
    pts = np.c_[xs.ravel() + 0.5, ys.ravel() + 0.5]
    m = np.array([tp[1] - tp[0], tp[2] - tp[0]]).T
    if abs(np.linalg.det(m)) < 1e-12:
        return None
    bc = (pts - tp[0]) @ np.linalg.inv(m).T
    wts = np.c_[1 - bc.sum(1), bc]
    keep = (wts >= -0.05).all(1)
    if not keep.any():
        return None
    wts = np.clip(wts[keep], 0, None)
    wts /= wts.sum(1, keepdims=True)
    return np.clip(pts[keep].astype(int), 0, res - 1), wts


def bleed(img, valid, rounds=10):
    """Grow colours past island borders so mip levels and seams stay clean."""
    img *= valid[..., None]
    for _ in range(rounds):
        acc = cv2.blur(img, (3, 3))
        cnt = cv2.blur(valid, (3, 3))
        grow = (valid == 0) & (cnt > 0)
        img[grow] = acc[grow] / cnt[grow, None]
        valid[grow] = 1.0


def clusters(lab, max_k=3, merge=12.0, min_frac=0.02):
    if len(lab) < 60:
        return lab.mean(0, keepdims=True)
    pick = lab if len(lab) <= 20000 else lab[np.random.default_rng(1).choice(len(lab), 20000, replace=False)]
    k = min(max_k, len(pick))
    crit = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 0.5)
    _, lbl, cen = cv2.kmeans(pick.astype(np.float32), k, None, crit, 2, cv2.KMEANS_PP_CENTERS)
    cen = [c for c in cen]
    counts = [int((lbl.ravel() == i).sum()) for i in range(k)]
    changed = True
    while changed and len(cen) > 1:
        changed = False
        for i in range(len(cen)):
            for j in range(i + 1, len(cen)):
                small = min(counts[i], counts[j]) < min_frac * len(pick)
                if np.linalg.norm(cen[i] - cen[j]) < merge or small:
                    tot = counts[i] + counts[j]
                    cen[i] = (cen[i] * counts[i] + cen[j] * counts[j]) / max(tot, 1)
                    counts[i] = tot
                    del cen[j], counts[j]
                    changed = True
                    break
            if changed:
                break
    return np.array(cen)


def nearest(lab, cen):
    return np.argmin(((lab[:, None, :] - cen[None]) ** 2).sum(-1), axis=1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hero", required=True)
    ap.add_argument("--npz", type=Path, required=True)
    ap.add_argument("--tex", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--face-out", type=Path, required=True)
    a = ap.parse_args()
    d = np.load(a.npz)
    co, part, vis, uv = d["co"], d["part"], d["visible"].astype(bool), d["uv"]
    tri_v, tri_uv, rpx = d["tri_v"], d["tri_uv"], d["render_px"]
    head = int(d["head"][0])
    n = len(co)

    sheet = cv2.cvtColor(cv2.imread(str(REF / "sheets" / f"{a.hero}.jpg")), cv2.COLOR_BGR2RGB)
    sh, sw = sheet.shape[:2]
    sheet_lab = to_lab(sheet).reshape(sh, sw, 3)
    ref = json.loads((REF / "landmarks" / f"{a.hero}-sheet.json").read_text())

    # 1. render pixel -> sheet pixel
    pose = d["render_pose"]
    ids = [i for i in POSE_IDS if len(pose) and pose[i][2] > 0.5 and ref["pose"][i][2] > 0.5]
    body_map = similarity(np.array([pose[i][:2] for i in ids]), np.array([ref["pose"][i][:2] for i in ids]))
    pp = body_map(rpx)
    face_w = np.zeros(n)
    face_v = np.zeros(n, bool)
    rface = d["render_face"]
    if len(rface) and ref["face"]:
        src = rface[:468, :2].astype(float)
        dst = np.array(ref["face"])[:468, :2].astype(float)
        # The head mesh is mirror-symmetric about plane_px: pair the landmarks there and make both the
        # render's and the sheet's landmark sets symmetric, so the warp cannot tilt eyes or bend the nose.
        axis_x = float(d["plane_px"][0])
        pair = np.array(PAIRS["pair"])
        src = symmetric(src, pair, (np.array([axis_x, 0.0]), np.array([0.0, 1.0])))
        dst = symmetric(dst, pair)
        tri = Delaunay(src)
        oval = src[OVAL]
        width = np.ptp(oval[:, 0])
        # eyes and brows sit in their sockets under the lids: every front-facing point of them is drawn
        front = d["nrm"][:, 1] < -0.3
        cand = d["near_head"].astype(bool) & (vis | (front & d["paired"].astype(bool)))
        simplex = tri.find_simplex(rpx)
        inside = cand & (simplex >= 0)
        # inside the oval polygon
        from matplotlib.path import Path as MPath  # noqa: E402  (matplotlib ships with mediapipe)
        inside &= MPath(oval).contains_points(rpx)
        idx = np.nonzero(inside)[0]
        s = simplex[idx]
        T = tri.transform[s]
        bc2 = np.einsum("nij,nj->ni", T[:, :2], rpx[idx] - T[:, 2])
        bc = np.c_[bc2, 1 - bc2.sum(1)]
        verts = tri.simplices[s]
        fpp = np.einsum("ni,nij->nj", bc, dst[verts])
        w = np.clip(poly_dist(rpx[idx], oval) / (0.12 * width), 0, 1)
        pp[idx] = pp[idx] * (1 - w[:, None]) + fpp * w[:, None]
        face_w[idx] = w
        face_v[idx] = True
    on_sheet = (pp[:, 0] > 1) & (pp[:, 0] < sw - 2) & (pp[:, 1] > 1) & (pp[:, 1] < sh - 2)
    vsheet = sample(sheet_lab, pp[:, 0], pp[:, 1])
    bg = sheet_lab[5:40, 5:40].reshape(-1, 3).mean(0)
    figure = np.linalg.norm(vsheet - bg, axis=1) > 6
    seen = vis & on_sheet & figure

    # 2. atlas raster by part, Tripo colours
    tex = cv2.cvtColor(cv2.imread(str(a.tex)), cv2.COLOR_BGR2RGB)
    H, W = tex.shape[:2]
    tex_lab = to_lab(tex).reshape(H, W, 3)
    pmap = np.full((H, W), -1, np.int32)
    tri_part = part[tri_v[:, 0]]
    px = np.c_[tri_uv[..., 0].ravel() * W, (1 - tri_uv[..., 1].ravel()) * H].reshape(-1, 3, 2)
    fixed = np.round(px * 16).astype(np.int32)
    for p in np.unique(tri_part):
        sel = fixed[tri_part == p]
        cv2.fillPoly(pmap, list(sel), int(p), lineType=cv2.LINE_8, shift=4)
    vtex = sample(tex_lab, uv[:, 0] * W, (1 - uv[:, 1]) * H)

    # 3. clusters and their sheet colours
    out = np.zeros((H, W, 3), np.float32)
    stats, colour, centres, vlabel = {}, {}, {}, np.zeros(n, int)
    for p in np.unique(part):
        tx = pmap == p
        lab = tex_lab[tx]
        cen = clusters(lab) if len(lab) else vtex[part == p].mean(0, keepdims=True)
        centres[p] = cen
        rows = np.nonzero(part == p)[0]
        vlabel[rows] = nearest(vtex[rows], cen)
        for c in range(len(cen)):
            r = rows[(vlabel[rows] == c) & seen[rows]]
            if len(r) >= 6:
                smp = vsheet[r]
                light = smp[smp[:, 0] > 30]
                if len(light) >= 0.4 * len(smp):
                    smp = light
                colour[(p, c)] = np.median(smp, axis=0)
    resolved = np.array([(int(part[i]), int(vlabel[i])) in colour for i in range(n)]) & seen
    feat = np.c_[co * 100.0, vtex * 0.25]
    tree = cKDTree(feat[resolved])
    rcol = np.array([colour[(int(part[i]), int(vlabel[i]))] for i in np.nonzero(resolved)[0]])
    borrowed = 0
    for p in np.unique(part):
        rows = np.nonzero(part == p)[0]
        for c in range(len(centres[p])):
            if (p, c) in colour:
                continue
            r = rows[vlabel[rows] == c]
            if len(r) == 0:
                got = [cc for cc in range(len(centres[p])) if (p, cc) in colour]
                if got:
                    best = min(got, key=lambda cc: np.linalg.norm(centres[p][cc] - centres[p][c]))
                    colour[(p, c)] = colour[(p, best)]
                continue
            q = feat[r] if len(r) <= 400 else feat[r][np.linspace(0, len(r) - 1, 400).astype(int)]
            _, nb = tree.query(q, k=12)
            colour[(p, c)] = np.median(rcol[nb.ravel()], axis=0)
            borrowed += 1
    # 4. flat colours with a little of Tripo's lightness
    for p in np.unique(part):
        tx = pmap == p
        if not tx.any():
            continue
        lab = tex_lab[tx]
        cen = centres[p]
        lbl = nearest(lab, cen)
        fill = np.zeros_like(lab)
        for c in range(len(cen)):
            m = lbl == c
            col = colour.get((p, c))
            if col is None:
                col = np.median(vsheet[part == p], axis=0)
            fill[m] = col
            fill[m, 0] += DETAIL * (lab[m, 0] - cen[c][0])
        out[tx] = fill
        stats[int(p)] = len(cen)
    rgb = to_rgb(out.reshape(-1, 3)).reshape(H, W, 3).astype(np.float32)
    bleed(rgb, (pmap >= 0).astype(np.float32))
    cv2.imwrite(str(a.out), cv2.cvtColor(np.clip(rgb, 0, 255).astype(np.uint8), cv2.COLOR_RGB2BGR))
    # Face texture (own unwrap): each vertex's flat cluster colour, then the sheet's face through the
    # warp, faded in from the oval.
    vlab = np.array([colour.get((int(part[i]), int(vlabel[i])), vsheet[i]) for i in range(n)], np.float32)
    vrgb = to_rgb(vlab).astype(np.float32)
    FR = 1024
    face_img = np.zeros((FR, FR, 3), np.float32)
    covered = np.zeros((FR, FR), np.float32)
    tri_uv2, tri_face = d["tri_uv2"], d["tri_face"].astype(bool)
    fpx = np.c_[tri_uv2[..., 0].ravel() * FR, (1 - tri_uv2[..., 1].ravel()) * FR].reshape(-1, 3, 2)
    for t in np.nonzero(tri_face)[0]:
        got = raster(fpx[t], FR)
        if got is None:
            continue
        xy, wts = got
        tv = tri_v[t]
        col = wts @ vrgb[tv]
        if face_v[tv].any():
            q = wts @ pp[tv]
            alpha = (wts @ face_w[tv])[:, None]
            src = sheet[np.clip(q[:, 1].astype(int), 0, sh - 1), np.clip(q[:, 0].astype(int), 0, sw - 1)]
            col = col * (1 - alpha) + src.astype(np.float32) * alpha
        face_img[xy[:, 1], xy[:, 0]] = col
        covered[xy[:, 1], xy[:, 0]] = 1.0
    bleed(face_img, covered)
    cv2.imwrite(str(a.face_out), cv2.cvtColor(np.clip(face_img, 0, 255).astype(np.uint8), cv2.COLOR_RGB2BGR))
    fv = np.nonzero(face_v)[0]
    info = {"atlas": [W, H], "parts": int(len(np.unique(part))), "clusters": int(sum(stats.values())),
            "clusters_from_sheet": int(len(colour) - borrowed), "clusters_borrowed": borrowed,
            "seen_vertices": int(seen.sum()), "vertices": int(n), "pose_points": len(ids),
            "face_warp": bool(face_v.any()), "face_pairs": int((pair != np.arange(len(pair))).sum()) if face_v.any() else 0, "face_vertices": fv.tolist(), "face_weight": face_w[fv].round(3).tolist()}
    (a.npz.parent / f"{a.hero}-paint.json").write_text(json.dumps(info))
    print("PAINT", a.hero, {k: v for k, v in info.items() if k not in ("face_vertices", "face_weight")})


if __name__ == "__main__":
    main()
