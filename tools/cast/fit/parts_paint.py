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
4. Texels become their cluster's flat colour (labels mode-filtered so no speckle survives), keeping a
   little of Tripo's blurred lightness (folds, not its painted grime). Clusters seen by too few vertices
   take the part's main colour, shifted by their lightness. Islands are padded to the full atlas.
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
FEATURES = [
    [33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246],
    [263, 249, 390, 373, 374, 380, 381, 382, 362, 398, 384, 385, 386, 387, 388, 466],
    [70, 63, 105, 66, 107, 55, 65, 52, 53, 46],
    [300, 293, 334, 296, 336, 285, 295, 282, 283, 276],
    [61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291, 409, 270, 269, 267, 0, 37, 39, 40, 185],
]
POSE_IDS = (0, 2, 5, 7, 8, 11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28)
ATLAS = 2048


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


def bleed(img, valid):
    """Fill every empty texel with the nearest painted one: the black between islands otherwise creeps
    into the islands' edges at the lower mip levels and reads as dirt."""
    from scipy.ndimage import distance_transform_edt
    _, (iy, ix) = distance_transform_edt(valid == 0, return_indices=True)
    img[...] = img[iy, ix]


def layout_sheet(img, covered, sizes, puv, groups, path):
    """Review image of the atlas: the paint at half strength on white (padding hidden), every polygon's
    outline as modelled (quads stay quads), and each region's name over its band (groups in UV v)."""
    H, W = img.shape[:2]
    sheet = (img.astype(np.float32) * 0.55 + 255 * 0.45).astype(np.uint8)
    sheet[~covered] = 255
    pts = np.round(np.c_[puv[:, 0] * W, (1 - puv[:, 1]) * H] * 4).astype(np.int32)
    polys = np.split(pts, np.cumsum(sizes)[:-1])
    cv2.polylines(sheet, polys, True, (60, 64, 72), 1, cv2.LINE_AA, shift=2)
    for g in groups:
        y0 = int((1 - g["top"]) * H)
        cv2.line(sheet, (0, y0), (W, y0), (200, 60, 40), 3)
        cv2.putText(sheet, g["name"], (12, y0 + 44), cv2.FONT_HERSHEY_SIMPLEX, 1.4, (200, 60, 40), 3, cv2.LINE_AA)
    cv2.imwrite(str(path), cv2.cvtColor(sheet, cv2.COLOR_RGB2BGR))


def clusters(lab, max_k=3, merge=18.0, min_frac=0.15):
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


def dominant(smp):
    """Median of the larger of two colour groups: a cluster whose vertices straddle two sheet colours
    takes the one most of them see, not a muddy mean of both."""
    if len(smp) < 12:
        return np.median(smp, axis=0)
    crit = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 20, 0.5)
    _, lbl, cen = cv2.kmeans(smp.astype(np.float32), 2, None, crit, 2, cv2.KMEANS_PP_CENTERS)
    lbl = lbl.ravel()
    if np.linalg.norm(cen[0] - cen[1]) < 10:
        return np.median(smp, axis=0)
    big = int(np.argmax(np.bincount(lbl, minlength=2)))
    return np.median(smp[lbl == big], axis=0)


def nearest(lab, cen):
    return np.argmin(((lab[:, None, :] - cen[None]) ** 2).sum(-1), axis=1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hero", required=True)
    ap.add_argument("--npz", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    a = ap.parse_args()
    d = np.load(a.npz)
    co, part, vis = d["co"], d["part"], d["visible"].astype(bool)
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
    # Thin-plate spline on the pose points plus a few face-outline points: a single similarity leaves
    # hands, bags and hat bands a few sheet pixels off, onto their neighbours' colours.
    src_pts = [pose[i][:2] for i in ids]
    dst_pts = [ref["pose"][i][:2] for i in ids]
    rface = d["render_face"]
    if len(rface) and ref["face"]:
        for i in (10, 152, 234, 454):
            src_pts.append(rface[i][:2])
            dst_pts.append(ref["face"][i][:2])
    src_pts, dst_pts = np.array(src_pts, float), np.array(dst_pts, float)
    base = similarity(src_pts, dst_pts)
    from scipy.interpolate import RBFInterpolator
    tps = RBFInterpolator(src_pts, dst_pts - base(src_pts), kernel="thin_plate_spline", smoothing=1.0)
    pp = base(rpx) + tps(rpx)
    face_w = np.zeros(n)
    face_v = np.zeros(n, bool)
    mc = mu = None
    mouth = np.zeros(n, bool)
    if len(rface) and ref["face"]:
        src = rface[:468, :2].astype(float)
        dst = np.array(ref["face"])[:468, :2].astype(float)
        # The head mesh is mirror-symmetric about plane_px: pair the landmarks there and make both the
        # render's and the sheet's landmark sets symmetric, so the warp cannot tilt eyes or bend the nose.
        axis_x = float(d["plane_px"][0])
        pair = np.array(PAIRS["pair"])
        src = symmetric(src, pair, (np.array([axis_x, 0.0]), np.array([0.0, 1.0])))
        # the sheet face's own midline (forehead, nose ridge, philtrum, chin), for the mirrored samples below
        mid = dst[PAIRS["midline"]]
        mc = mid.mean(0)
        mu = np.linalg.svd(mid - mc)[2][0]
        dst = symmetric(dst, pair)
        # eyes, brows and lips on the sheet, each outline grown by 40 % about its centre
        from matplotlib.path import Path as MPath
        verts, codes = [], []
        for ring in FEATURES:
            pts = dst[ring]
            pts = pts.mean(0) + 1.4 * (pts - pts.mean(0))
            verts += pts.tolist() + [pts[0].tolist()]
            codes += [MPath.MOVETO] + [MPath.LINETO] * (len(ring) - 1) + [MPath.CLOSEPOLY]
        features = MPath(verts, codes)
        tri = Delaunay(src)
        from matplotlib.path import Path as MPath  # noqa: E402  (matplotlib ships with mediapipe)
        oval = src[OVAL]
        width = np.ptp(oval[:, 0])
        # eyes and brows sit in their sockets under the lids: every front-facing point of them is drawn
        front = d["nrm"][:, 1] < -0.3
        # Teeth and tongue parts behind the lips (found in Blender): head skin, never drawn.
        mouth = d["mouth"].astype(bool)
        cand = d["near_head"].astype(bool) & (vis | (front & d["paired"].astype(bool))) & ~mouth
        simplex = tri.find_simplex(rpx)
        inside = cand & (simplex >= 0)
        inside &= MPath(oval).contains_points(rpx)
        idx = np.nonzero(inside)[0]
        s = simplex[idx]
        T = tri.transform[s]
        bc2 = np.einsum("nij,nj->ni", T[:, :2], rpx[idx] - T[:, 2])
        bc = np.c_[bc2, 1 - bc2.sum(1)]
        verts = tri.simplices[s]
        fpp = np.einsum("ni,nij->nj", bc, dst[verts])
        w = np.clip(poly_dist(rpx[idx], oval) / (0.12 * width), 0, 1)
        # Only where the face looks at the viewer: on cheeks turning to the side, the sheet's lines would be
        # stretched into long gashes; there the face fades to flat skin.
        w *= np.clip((-d["nrm"][idx, 1] - 0.45) / 0.3, 0, 1)
        pp[idx] = pp[idx] * (1 - w[:, None]) + fpp * w[:, None]
        face_w[idx] = w
        face_v[idx] = True
    on_sheet = (pp[:, 0] > 1) & (pp[:, 0] < sw - 2) & (pp[:, 1] > 1) & (pp[:, 1] < sh - 2)
    vsheet = sample(sheet_lab, pp[:, 0], pp[:, 1])
    bg = sheet_lab[5:40, 5:40].reshape(-1, 3).mean(0)
    figure = np.linalg.norm(vsheet - bg, axis=1) > 6
    seen = vis & on_sheet & figure

    # 2. the readable atlas (UVs from Blender) rasterised part by part; Tripo colours per vertex
    H = W = ATLAS
    vtex = to_lab(d["vtex"].astype(np.uint8))
    pmap = np.full((H, W), -1, np.int32)
    tri_part = part[tri_v[:, 0]]
    px = np.c_[tri_uv[..., 0].ravel() * W, (1 - tri_uv[..., 1].ravel()) * H].reshape(-1, 3, 2)
    fixed = np.round(px * 16).astype(np.int32)
    for p in np.unique(tri_part):
        sel = fixed[tri_part == p]
        cv2.fillPoly(pmap, list(sel), int(p), lineType=cv2.LINE_8, shift=4)

    # 3. clusters (of the part's vertices' Tripo colours) and their sheet colours
    out = np.zeros((H, W, 3), np.float32)
    stats, colour, centres, vlabel, support = {}, {}, {}, np.zeros(n, int), {}
    for p in np.unique(part):
        rows = np.nonzero(part == p)[0]
        if p == head:
            # skin, and the hair Tripo painted on the back of the head; features come from the drawn face
            cen = clusters(vtex[rows], max_k=2, merge=25.0)
        else:
            cen = clusters(vtex[rows])
        centres[p] = cen
        vlabel[rows] = nearest(vtex[rows], cen)
        for c in range(len(cen)):
            r = rows[(vlabel[rows] == c) & seen[rows]]
            support[(p, c)] = len(r)
            if len(r) >= 6:
                smp = vsheet[r]
                light = smp[:, 0] > 30
                if light.sum() >= 0.4 * len(smp):
                    smp, r = smp[light], r[light]
                colour[(p, c)] = dominant(smp)
    # The head part's skin is the cluster most of its seen vertices fall in; its other cluster (hair on
    # the scalp) borrows from the hair parts around it, never from the face.
    hrows = np.nonzero(part == head)[0]
    skin_c = int(np.argmax(np.bincount(vlabel[hrows][seen[hrows]], minlength=len(centres[head]))))
    for c in range(len(centres[head])):
        if c != skin_c:
            colour.pop((head, c), None)
    skin_tripo = centres[head][skin_c]
    skin_like = part == head
    resolved = np.array([(int(part[i]), int(vlabel[i])) in colour for i in range(n)]) & seen
    feat = np.c_[co * 100.0, vtex * 0.25]
    skin_sheet = colour[(head, skin_c)]
    resolved = np.array([(int(part[i]), int(vlabel[i])) in colour for i in range(n)]) & seen & ~skin_like
    # Pieces on the head (hair, hats) borrow only from pieces on the head: hair at the nape must not
    # take the collar's colour.
    on_head_v = d["on_head"].astype(bool)
    trees = {}
    for key, m in (("head", resolved & on_head_v), ("body", resolved & ~on_head_v)):
        idx = np.nonzero(m)[0]
        if len(idx):
            trees[key] = (cKDTree(feat[idx]), np.array([colour[(int(part[i]), int(vlabel[i]))] for i in idx]))
    if "head" not in trees:
        trees["head"] = trees["body"]
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
            got = [cc for cc in range(len(centres[p])) if (p, cc) in colour and (p, cc) in support and support[(p, cc)] >= 6]
            if got and p != head:
                # a part seen elsewhere from the front: its hidden cluster is the same cloth, in its own colour
                best = min(got, key=lambda cc: np.linalg.norm(centres[p][cc][1:] - centres[p][c][1:]))
                col = colour[(p, best)].copy()
                col[0] += 0.2 * (centres[p][c][0] - centres[p][best][0])
                colour[(p, c)] = col
                borrowed += 1
                continue
            q = feat[r] if len(r) <= 400 else feat[r][np.linspace(0, len(r) - 1, 400).astype(int)]
            tree, rcol = trees["head" if on_head_v[r].mean() > 0.5 else "body"]
            _, nb = tree.query(q, k=min(12, len(rcol)))
            colour[(p, c)] = np.median(rcol[np.atleast_2d(nb).ravel()], axis=0)
            borrowed += 1
    # Texel labels: the Tripo colour interpolated across each triangle, then its nearest cluster, so colour
    # borders run smoothly through triangles instead of stepping along their edges.
    lbl_img = np.full((H, W), 255, np.uint8)
    for p in np.unique(tri_part):
        cen = centres[p]
        ts = np.nonzero(tri_part == p)[0]
        if len(cen) == 1:
            cv2.fillPoly(lbl_img, list(fixed[ts]), 0, lineType=cv2.LINE_8, shift=4)
            continue
        for t in ts:
            got = raster(px[t], W)
            if got is None:
                continue
            xy, wts = got
            lbl_img[xy[:, 1], xy[:, 0]] = nearest(wts @ vtex[tri_v[t]], cen)
    lbl_med = cv2.medianBlur(lbl_img, 5)
    # Weak clusters (few vertices saw the sheet): the part's main colour, shifted by their lightness.
    for p in np.unique(part):
        cen = centres[p]
        if len(cen) < 2:
            continue
        tx = pmap == p
        counts = np.bincount(lbl_img[tx], minlength=len(cen))[:len(cen)]
        main = int(np.argmax(counts))
        for c in range(len(cen)):
            # Weak clusters, and clusters that only differ from the main one in lightness (hair strands,
            # folds, Tripo's painted grime): one material, the main colour nudged by a fifth of the gap.
            # pieces on the head (hats, hair) are one material each: a looser hue match
            hue_tol = 30 if d["on_head"][part == p].mean() > 0.5 else 16
            same = np.linalg.norm(cen[c][1:] - cen[main][1:]) < hue_tol and abs(cen[c][0] - cen[main][0]) < 35
            if p != head and c != main and (support.get((p, c), 0) < 30 or same) and (p, main) in colour:
                col = colour[(p, main)].copy()
                col[0] += 0.2 * (cen[c][0] - cen[main][0])
                colour[(p, c)] = col
    # Skin that crept onto hair and hats: in a part whose main colour is not skin, a skin-coloured cluster
    # is a registration slip (fringe strands under a brim sampling the forehead). It takes the main colour.
    for p in np.unique(part):
        cen = centres[p]
        if p == head or len(cen) < 2:
            continue
        counts = np.bincount(lbl_img[pmap == p], minlength=len(cen))[:len(cen)]
        main = int(np.argmax(counts))
        if (p, main) not in colour or np.linalg.norm(colour[(p, main)] - skin_sheet) < 14:
            continue
        for c in range(len(cen)):
            if c != main and (p, c) in colour and np.linalg.norm(colour[(p, c)] - skin_sheet) < 14:
                col = colour[(p, main)].copy()
                col[0] += 0.2 * (cen[c][0] - cen[main][0])
                colour[(p, c)] = col
    # Hair, hats and goggles (whole on the Head bone) are never skin: a skin-coloured cluster there takes
    # the part's own non-skin colour, else the median of the other head pieces' non-skin colours.
    on_head = d["on_head"].astype(bool)
    linings = []
    if len(d["render_face"]):
        # not the skin linings that hang down the front of the neck under the head part
        chin_py = d["render_face"][152][1]
        front = co[:, 1] < co[part == head, 1].mean()
        for p in np.unique(part[on_head]):
            rows = part == p
            if ((rpx[rows, 1] > chin_py + 0.4 * (chin_py - d["render_face"][10][1])) & front[rows]).any():
                on_head[rows] = False
                linings.append(p)
                # a skin-coloured lining (Tripo's skin under the head part): its skin clusters are skin
                for c in range(len(centres[p])):
                    if np.linalg.norm(centres[p][c] - skin_tripo) < 15:
                        colour[(p, c)] = skin_sheet
    def skinlike(col):
        # skin, or skin in shade (a cap band sampling the forehead under its brim): the same hue, darker
        return (np.linalg.norm(col - skin_sheet) < 22
                or (np.linalg.norm(col[1:] - skin_sheet[1:]) < 10 and col[0] - skin_sheet[0] > -60))

    hparts = [p for p in np.unique(part[on_head])]
    nonskin = [colour[(p, c)] for p in hparts for c in range(len(centres[p]))
               if (p, c) in colour and not skinlike(colour[(p, c)])]
    for p in hparts:
        own = [colour[(p, c)] for c in range(len(centres[p]))
               if (p, c) in colour and not skinlike(colour[(p, c)])]
        for c in range(len(centres[p])):
            if (p, c) in colour and skinlike(colour[(p, c)]):
                pool = own or nonskin
                if pool:
                    colour[(p, c)] = np.median(np.array(pool), axis=0)
    # Necklines: garment points in front, below the chin, lying on the head part or a skin lining, where
    # the sheet shows skin (a shirt edge Tripo raised above the collar) are skin.
    neck = np.zeros(n, bool)
    if len(d["render_face"]):
        skin_parts = [head] + linings
        dist = cKDTree(co[np.isin(part, skin_parts)]).query(co)[0]
        # (and where Tripo painted skin too: a scarf the sheet's registration slips onto the chin stays scarf)
        neck = (~np.isin(part, skin_parts) & seen & (np.linalg.norm(vsheet - skin_sheet, axis=1) < 20)
                & (np.linalg.norm(vtex - skin_tripo, axis=1) < 25)
                & (dist < 0.03) & (rpx[:, 1] > d["render_face"][152][1])
                & (co[:, 1] < co[part == head, 1].mean()))
        # grow over the edge's unseen side (same conditions bar the sheet): two rings along triangles
        near = ~np.isin(part, skin_parts) & (dist < 0.03) & (rpx[:, 1] > d["render_face"][152][1]) \
            & (co[:, 1] < co[part == head, 1].mean())
        for _ in range(2):
            touch = np.zeros(n, bool)
            touch[tri_v[neck[tri_v].any(1)].ravel()] = True
            neck |= touch & near
    # 4. flat colours, one per cluster
    for p in np.unique(part):
        tx = pmap == p
        if not tx.any():
            continue
        cen = centres[p]
        lbl = lbl_med[tx].astype(int)
        lbl[lbl >= len(cen)] = 0
        fill = np.zeros((int(tx.sum()), 3), np.float32)
        for c in range(len(cen)):
            col = colour.get((p, c))
            fill[lbl == c] = col if col is not None else np.median(vsheet[part == p], axis=0)
        out[tx] = fill
        stats[int(p)] = len(cen)
    rgb = to_rgb(out.reshape(-1, 3)).reshape(H, W, 3).astype(np.float32)
    # Per-vertex colours for the face (head part, eyes, brows, mouth) and the fixes below.
    vlab = np.array([colour.get((int(part[i]), int(vlabel[i])), vsheet[i]) for i in range(n)], np.float32)
    # Behind parted lips: head skin, so the drawn mouth on the lips reads closed.
    if mouth.any() or neck.any():
        vlab[mouth | neck] = colour[(head, skin_c)]
    # The head part's darker cluster is hair only on the scalp (above the forehead or on the back half);
    # elsewhere (neck, chest under an open collar) it is shaded skin.
    over = np.zeros(n, bool)
    if len(d["render_face"]):
        rf = d["render_face"]
        back = d["nrm"][:, 1] > 0.25  # facing backwards: the back of the head, not the ears
        hco = co[part == head]
        behind = co[:, 1] > hco[:, 1].mean()
        vcol = np.array([colour.get((int(part[i]), int(vlabel[i])), skin_sheet) for i in range(n)], np.float32)
        hairy = on_head & (np.linalg.norm(vcol - skin_sheet, axis=1) >= 22)
        # Long hair hides the nape: the scalp runs down the back as far as the hair behind the head hangs.
        low = co[hairy & behind, 2].min() if (hairy & behind).any() else np.inf
        scalp = (rpx[:, 1] < rf[10][1]) | (back & ((rpx[:, 1] < rf[152][1]) | (co[:, 2] > low)))
        hide = (part == head) & (vlabel != skin_c) & ~scalp
        vlab[hide] = colour[(head, skin_c)]
        # Skin-coloured pieces over the back of the skull (Tripo's scalp under short hair, a neck piece
        # rising behind the head) are scalp too; the ears at the sides are not.
        cx, half = hco[:, 0].mean(), np.ptp(hco[:, 0]) / 2
        over = ((part != head) & scalp & behind & (np.abs(co[:, 0] - cx) < 0.75 * half)
                & (np.linalg.norm(vcol - skin_sheet, axis=1) < 22) & (cKDTree(hco).query(co)[0] < 0.03))
        # One hair colour for the whole scalp: the commonest non-skin colour on the head pieces hugging
        # the back of the head (the nearest one would also pick up goggle straps and hat bands; Tripo paints
        # blond hair as near-skin, so the head part's own clusters cannot tell hair from skin there).
        hug = np.nonzero(hairy & behind & (cKDTree(hco).query(co)[0] < 0.03))[0]
        if not len(hug):
            hug = np.nonzero(hairy)[0]
        sc = np.nonzero(((part == head) & scalp) | over)[0]
        if len(hug) and len(sc):
            keys, counts = np.unique(np.c_[part[hug], vlabel[hug]], axis=0, return_counts=True)
            kp, kc = keys[np.argmax(counts)]
            vlab[sc] = colour[(int(kp), int(kc))]
        else:
            over[:] = False
    vrgb = to_rgb(vlab).astype(np.float32)
    # Mouth fillers and necklines are skin; the face set (head part, eyes, brows, mouth) is painted per
    # vertex, then the sheet's face through the warp, faded in from the oval.
    skin = to_rgb(np.array([colour[(head, skin_c)]], np.float32))[0].astype(np.float32)
    for t in np.nonzero(mouth[tri_v].any(1) | (neck[tri_v].sum(1) >= 2))[0]:
        got = raster(px[t], W)
        if got is not None:
            rgb[got[0][:, 1], got[0][:, 0]] = skin
    for t in np.nonzero((over[tri_v].sum(1) >= 2) & (part[tri_v[:, 0]] != head))[0]:
        got = raster(px[t], W)
        if got is not None:
            rgb[got[0][:, 1], got[0][:, 0]] = got[1] @ vrgb[tri_v[t]]
    face_set = d["face_set"].astype(bool)
    for t in np.nonzero(face_set[tri_v].all(1))[0]:
        got = raster(px[t], W)
        if got is None:
            continue
        xy, wts = got
        tv = tri_v[t]
        col = wts @ vrgb[tv]
        if face_v[tv].any():
            q = wts @ pp[tv]
            alpha = (wts @ face_w[tv])[:, None]
            src = sample(sheet, q[:, 0], q[:, 1]).astype(np.float32)
            if mc is not None:
                # Outside the eyes, brows and lips each texel also samples its mirror image across the sheet
                # face's midline and keeps whichever is nearer the flat skin: a nose shadow or cheekbone line
                # drawn on one side only goes, so the face reads the same from either side. The features
                # themselves keep their own pixels (a mirrored pupil would land on the other eye's white).
                dq = q - mc
                qm = mc + 2 * np.outer(dq @ mu, mu) - dq
                alt = sample(sheet, qm[:, 0], qm[:, 1]).astype(np.float32)
                swap = (np.linalg.norm(alt - skin, axis=1) < np.linalg.norm(src - skin, axis=1)) & ~features.contains_points(q)
                src = np.where(swap[:, None], alt, src)
            col = col * (1 - alpha) + src.astype(np.float32) * alpha
        rgb[xy[:, 1], xy[:, 0]] = col
    bleed(rgb, (pmap >= 0).astype(np.float32))
    img8 = np.clip(rgb, 0, 255).astype(np.uint8)
    cv2.imwrite(str(a.out), cv2.cvtColor(img8, cv2.COLOR_RGB2BGR))
    layout_sheet(img8, pmap >= 0, d["poly_sizes"], d["poly_uv"], json.loads(str(d["groups"][0])),
                 a.out.with_name(f"{a.hero}-uv-layout.png"))
    fv = np.nonzero(face_v)[0]
    info = {"atlas": [W, H], "parts": int(len(np.unique(part))), "clusters": int(sum(stats.values())),
            "clusters_from_sheet": int(len(colour) - borrowed), "clusters_borrowed": borrowed,
            "seen_vertices": int(seen.sum()), "vertices": int(n), "pose_points": len(ids),
            "mouth_vertices": int(mouth.sum()), "neckline_vertices": int(neck.sum()), "face_warp": bool(face_v.any()), "face_pairs": int((pair != np.arange(len(pair))).sum()) if face_v.any() else 0, "face_vertices": fv.tolist(), "face_weight": face_w[fv].round(3).tolist()}
    (a.npz.parent / f"{a.hero}-paint.json").write_text(json.dumps(info))
    dbg = {f"{p}:{c}": [to_rgb(np.array([col], np.float32))[0].tolist(), int(support.get((p, c), 0)),
                        to_rgb(np.array([centres[p][c]], np.float32))[0].tolist()] for (p, c), col in colour.items()}
    dbg["_skin"] = int(skin_c)
    (a.npz.parent / f"{a.hero}-colours.json").write_text(json.dumps(dbg))
    print("PAINT", a.hero, {k: v for k, v in info.items() if k not in ("face_vertices", "face_weight")})


if __name__ == "__main__":
    main()
