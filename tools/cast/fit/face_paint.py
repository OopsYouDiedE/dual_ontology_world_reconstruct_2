"""Paint each hero's face from its painting: landmark-warped projection into the body UV texture.

Runs inside Blender (build_heroes.py calls paint_face before the helper mask is applied, while the body
still has the hm08 topology that face_map.json refers to).

1. The 468 MediaPipe landmarks are placed on the fitted mesh (face_map.json) and paired with the same
   landmarks detected on the painting (reference/landmarks/<hero>.json).
2. A Delaunay mesh over the landmarks' front-view positions gives a piecewise-affine warp; every face
   vertex inside it gets a painting pixel.
3. Body UV triangles over the face are rasterised; each texel interpolates its painting pixel from the
   triangle's vertices and samples the painting. Alpha fades to the flat skin colour toward the face
   outline, so lines, brows, lid shadows and lips come from the painting and the rest stays flat.
4. Face normals are bent toward the viewer (`flatten`) so the toon light reads as the painting's broad
   lit plane, not as sculpted bone shadow.
"""
import json
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector
from mathutils.geometry import delaunay_2d_cdt

FIT = Path(__file__).resolve().parent
REF = FIT.parent / "reference"
OVAL = [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377, 152,
        148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109]


def srgb_to_linear(c):
    c = np.asarray(c, float)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def load_painting(path):
    img = bpy.data.images.load(str(path), check_existing=True)
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    # Blender pixel rows run bottom-up; flip to image rows (y down). Byte images give sRGB values.
    return px.reshape(h, w, 4)[::-1, :, :3].copy(), img


def bilinear(img, x, y):
    h, w = img.shape[:2]
    x = np.clip(x, 0, w - 1.001)
    y = np.clip(y, 0, h - 1.001)
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = (x - x0)[:, None], (y - y0)[:, None]
    return (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x0 + 1] * fx * (1 - fy)
            + img[y0 + 1, x0] * (1 - fx) * fy + img[y0 + 1, x0 + 1] * fx * fy)


def point_in_poly(pts, poly):
    """Even-odd test of many points against one polygon (both (N, 2))."""
    inside = np.zeros(len(pts), bool)
    x, y = pts[:, 0], pts[:, 1]
    for (x1, y1), (x2, y2) in zip(poly, np.roll(poly, -1, axis=0)):
        cond = (y1 > y) != (y2 > y)
        xi = (x2 - x1) * (y - y1) / (y2 - y1 + 1e-12) + x1
        inside ^= cond & (x < xi)
    return inside


def dist_to_poly(pts, poly):
    best = np.full(len(pts), np.inf)
    for a, b in zip(poly, np.roll(poly, -1, axis=0)):
        ab = b - a
        t = np.clip(((pts - a) @ ab) / (ab @ ab), 0, 1)
        best = np.minimum(best, np.linalg.norm(pts - (a + t[:, None] * ab), axis=1))
    return best


def warp(src_tri, dst_tri, pts):
    """Piecewise-affine map of pts (N, 2) through triangles src_tri -> dst_tri (T, 3, 2)."""
    out = np.full((len(pts), 2), np.nan)
    for s, d in zip(src_tri, dst_tri):
        m = np.array([[s[1, 0] - s[0, 0], s[2, 0] - s[0, 0]], [s[1, 1] - s[0, 1], s[2, 1] - s[0, 1]]])
        if abs(np.linalg.det(m)) < 1e-12:
            continue
        inv = np.linalg.inv(m)
        uv = (pts - s[0]) @ inv.T
        hit = (uv[:, 0] >= -1e-6) & (uv[:, 1] >= -1e-6) & (uv.sum(1) <= 1 + 1e-6) & np.isnan(out[:, 0])
        if hit.any():
            u = uv[hit]
            out[hit] = d[0] + u[:, :1] * (d[1] - d[0]) + u[:, 1:] * (d[2] - d[0])
    return out


_DARK = {}


def dark_set(ids):
    key = id(ids)
    if key not in _DARK:
        _DARK.clear()
        _DARK[key] = set(int(i) for i in ids)
    return _DARK[key]


def paint_face(body, hero, skin_rgb, out_png, res=2048, feather=0.14, flatten=0.45):
    """Write the painted skin texture to out_png and return a material using it (or None)."""
    ref_path = REF / "landmarks" / f"{hero}.json"
    if not ref_path.exists():
        return None
    ref = json.loads(ref_path.read_text())
    man = json.loads((REF / "manifest.json").read_text(encoding="utf-8"))[hero]
    fmap = json.loads((FIT / "face_map.json").read_text())["face"]
    painting, pimg = load_painting(REF / man["image"])
    mesh = body.data
    co = np.empty(len(mesh.vertices) * 3)
    mesh.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    ids = [i for i in range(468) if str(i) in fmap]
    lm3 = np.array([sum(co[v] * w for v, w in zip(*fmap[str(i)])) for i in ids])
    src = lm3[:, [0, 2]] * np.array([1.0, -1.0])           # front view, y down like the painting
    dst = np.array([ref["face"][i][:2] for i in ids])
    tri = delaunay_2d_cdt([Vector(p) for p in src], [], [], 0, 1e-9)
    faces = [f for f in tri[2] if len(f) == 3]
    orig = tri[3]
    idx = [[orig[k][0] if orig[k] else None for k in f] for f in faces]
    idx = [f for f in idx if None not in f]
    src_tri, dst_tri = src[np.array(idx)], dst[np.array(idx)]
    oval = src[[ids.index(i) for i in OVAL if i in ids]]
    width = np.ptp(oval[:, 0])
    vfront = co[:, [0, 2]] * np.array([1.0, -1.0])
    normals = np.empty(len(mesh.vertices) * 3)
    mesh.vertices.foreach_get("normal", normals)
    normals = normals.reshape(-1, 3)
    near = (np.abs(vfront[:, 0] - oval[:, 0].mean()) < width) & (vfront[:, 1] > oval[:, 1].min() - width * 0.2) \
        & (vfront[:, 1] < oval[:, 1].max() + width * 0.2)
    candidates = np.nonzero(near & (normals[:, 1] < -0.15))[0]
    inside = point_in_poly(vfront[candidates], oval)
    face_v = candidates[inside]
    alpha = np.zeros(len(co))
    alpha[face_v] = np.clip(dist_to_poly(vfront[face_v], oval) / (feather * width), 0, 1) ** 1.5
    # Paintings put fringe, hat-brim shadow and side hair over the forehead and temples: fade the projection
    # out above the brows (y is down), so only flat skin carries up to the hairline.
    brow_y = src[[ids.index(i) for i in (70, 105, 107, 336, 334, 300) if i in ids], 1].mean()
    top = np.clip((vfront[face_v, 1] - (brow_y - 0.20 * width)) / (0.12 * width), 0, 1)
    alpha[face_v] *= top
    target = np.full((len(co), 2), np.nan)
    target[face_v] = warp(src_tri, dst_tri, vfront[face_v])
    alpha[np.isnan(target[:, 0])] = 0.0
    # Hair hanging inside the face outline (side locks, braids) is far darker than skin: near the outline,
    # drop vertices whose painting colour is hair-dark, with one ring of smoothing.
    ok = face_v[~np.isnan(target[face_v, 0])]
    lum = bilinear(painting, target[ok, 0], target[ok, 1]) @ np.array([0.2126, 0.7152, 0.0722])
    skin_lum = float(np.asarray(skin_rgb) @ np.array([0.2126, 0.7152, 0.0722]))
    edge = dist_to_poly(vfront[ok], oval) < 0.22 * width
    dark = ok[edge & (lum < 0.45 * skin_lum)]
    alpha[dark] = 0.0
    nbr = np.zeros(len(co), bool)
    for e in mesh.edges:
        a_, b_ = e.vertices
        if a_ in dark_set(dark) or b_ in dark_set(dark):
            nbr[a_] = nbr[b_] = True
    alpha[nbr] *= 0.4
    # Rasterise UV triangles that touch the face.
    uv_layer = mesh.uv_layers.active.data
    # Byte images hold display (sRGB) values in .pixels, like the painting read above: no conversion.
    image = np.tile(np.r_[np.asarray(skin_rgb, float), 1.0], (res, res, 1)).astype(np.float32)
    has = alpha > 0
    for p in mesh.polygons:
        vs = list(p.vertices)
        if not has[vs].any():
            continue
        loops = list(p.loop_indices)
        for a, b, c in [(0, k, k + 1) for k in range(1, len(vs) - 1)]:
            tv = [vs[a], vs[b], vs[c]]
            tuv = np.array([uv_layer[loops[a]].uv, uv_layer[loops[b]].uv, uv_layer[loops[c]].uv]) * res
            lo = np.floor(tuv.min(0)).astype(int)
            hi = np.ceil(tuv.max(0)).astype(int)
            xs, ys = np.meshgrid(np.arange(lo[0], hi[0] + 1), np.arange(lo[1], hi[1] + 1))
            pts = np.stack([xs.ravel() + 0.5, ys.ravel() + 0.5], 1)
            m = np.array([tuv[1] - tuv[0], tuv[2] - tuv[0]]).T
            if abs(np.linalg.det(m)) < 1e-9:
                continue
            bc = (pts - tuv[0]) @ np.linalg.inv(m).T
            w = np.c_[1 - bc.sum(1), bc]
            ok = (w >= -0.02).all(1)
            if not ok.any():
                continue
            w = w[ok]
            px = (pts[ok] - 0.5).astype(int)
            px = np.clip(px, 0, res - 1)
            tgt = np.nan_to_num(target[tv])
            al = (w * alpha[tv]).sum(1)
            pp = w @ tgt
            col = bilinear(painting, pp[:, 0], pp[:, 1])
            cur = image[px[:, 1], px[:, 0], :3]
            image[px[:, 1], px[:, 0], :3] = cur * (1 - al[:, None]) + col * al[:, None]
    out = bpy.data.images.new(f"{hero}_skin", res, res)
    out.pixels.foreach_set(image.ravel())
    out.filepath_raw = str(out_png)
    out.file_format = "PNG"
    out_png.parent.mkdir(parents=True, exist_ok=True)
    out.save()
    out.pack()
    bpy.data.images.remove(pimg)
    # Normals: lean the face toward the viewer by `flatten`, faded with the same alpha. Stored as a point
    # attribute so it survives the later mask/face deletions; apply_flat_normals writes it at the end.
    if flatten > 0:
        k = (alpha * flatten)[:, None]
        n = normals * (1 - k) + np.array([0.0, -1.0, 0.0]) * k
        n /= np.linalg.norm(n, axis=1, keepdims=True)
        n[alpha <= 0] = 0.0
        attr = mesh.attributes.new("paint_normal", "FLOAT_VECTOR", "POINT")
        attr.data.foreach_set("vector", n.astype(np.float32).ravel())
    mat = bpy.data.materials.new("SkinPainted")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = out
    shader = nodes["Principled BSDF"]
    mat.node_tree.links.new(tex.outputs["Color"], shader.inputs["Base Color"])
    shader.inputs["Roughness"].default_value = 0.7
    return mat


def apply_flat_normals(body):
    """Use the stored bent normals as custom normals on the final body mesh."""
    mesh = body.data
    attr = mesh.attributes.get("paint_normal")
    if attr is None:
        return 0
    n = np.empty(len(mesh.vertices) * 3, np.float32)
    attr.data.foreach_get("vector", n)
    n = n.reshape(-1, 3)
    own = np.empty(len(mesh.vertices) * 3, np.float32)
    mesh.vertices.foreach_get("normal", own)
    own = own.reshape(-1, 3)
    use = np.linalg.norm(n, axis=1) > 0.5
    out = np.where(use[:, None], n, own)
    mesh.normals_split_custom_set_from_vertices([tuple(v) for v in out])
    mesh.attributes.remove(mesh.attributes["paint_normal"])
    return int(use.sum())
