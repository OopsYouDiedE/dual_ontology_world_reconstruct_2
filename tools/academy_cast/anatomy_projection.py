"""Fit only front-plane landmarks to a supplied lineup, preserving the modeled depth.

Reference and mesh masks use the same normalized crown-to-sole coordinates.
An ordered per-row warp aligns torso, leg and arm intervals where they can be
matched unambiguously. This is not a 3D projection onto a scanned surface.
"""
import cv2
import numpy as np
from scipy.ndimage import gaussian_filter1d

HEIGHT, HALF = 400, 155


def reference_mask(image, p):
    left, top, right, bottom = p.crop
    rgb = np.asarray(image)[top:bottom, left:right].copy()
    yy, xx = np.mgrid[top:bottom, left:right]
    r, g, b = rgb.astype(float).transpose(2, 0, 1)
    warm = r-b
    m = np.full(r.shape, cv2.GC_PR_BGD, dtype=np.uint8)
    m[warm > 9] = cv2.GC_PR_FGD
    m[(warm > 26) & (r > 80)] = cv2.GC_FGD
    # Seed the mostly neutral garment inside the known torso. The reference's
    # grey background is an independent color class, never a mesh objective.
    center = abs(xx-p.center)
    inner = ((yy > p.waist+6) & (yy < p.crotch-6) & (center < (p.hip_x-p.center)*.66))
    m[inner] = cv2.GC_FGD
    m[:2] = m[-2:] = cv2.GC_BGD
    m[:, :2] = m[:, -2:] = cv2.GC_BGD
    m[(yy < p.crown-2) | (yy > p.foot+1)] = cv2.GC_BGD
    cv2.setRNGSeed(19)
    cv2.grabCut(rgb, m, None, np.zeros((1,65)), np.zeros((1,65)), 4, cv2.GC_INIT_WITH_MASK)
    mask = m % 2
    n, labels, counts, _ = cv2.connectedComponentsWithStats(mask, 8)
    if n < 2:
        raise ValueError('Reference mask contains no figure')
    mask = (labels == 1+np.argmax(counts[1:, cv2.CC_STAT_AREA])).astype(np.uint8)
    cnt, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    cv2.drawContours(mask, cnt, -1, 1, cv2.FILLED)
    f = HEIGHT/(p.foot-p.crown)
    mat = np.array([[f,0,HALF+(left-p.center)*f],[0,f,(top-p.crown)*f]], np.float32)
    return cv2.warpAffine(mask, mat, (2*HALF+1,HEIGHT+1), flags=cv2.INTER_NEAREST)


def mesh_mask(verts, faces):
    from tripo_surface import tris
    uv = np.round(np.c_[verts[:,0]*HEIGHT+HALF,(1-verts[:,2])*HEIGHT]*16).astype(np.int32)
    mask = np.zeros((HEIGHT+1, 2*HALF+1), dtype=np.uint8)
    for t in tris(faces):
        cv2.fillConvexPoly(mask, uv[t], 1, shift=4)
    return mask


def intervals(half):
    edges = np.flatnonzero(np.diff(np.r_[0, half, 0]))
    out = []
    for a,b in edges.reshape(-1,2):
        if out and a-out[-1][1] <= 3:
            out[-1][1] = b
        else:
            out.append([a,b])
    return [p for p in out if p[1]-p[0] >= 3]


def front_warp(source, target, amount=.83):
    grid = np.arange(HALF+1)
    fields = []
    for side in (-1,1):
        start = (source[:,HALF::-1] if side < 0 else source[:,HALF:])
        goal = (target[:,HALF::-1] if side < 0 else target[:,HALF:])
        val = np.zeros((HEIGHT+1, HALF+1)); good = np.zeros((HEIGHT+1,1));
        for i,(a,b) in enumerate(zip(start,goal)):
            sa, sb = intervals(a), intervals(b)
            if len(sa) == len(sb) and 0 < len(sa) <= 2:
                aa = np.r_[0, np.asarray(sa).ravel(), HALF]
                bb = np.r_[0, np.asarray(sb).ravel(), HALF]
                # A real midline stays fixed when either silhouette crosses it.
                keep = (aa>0)&(aa<HALF)&(bb>0)&(bb<HALF)
                aa,bb = np.r_[0,aa[keep],HALF],np.r_[0,bb[keep],HALF]
                bb=aa+np.clip(bb-aa,-15,15)
                # Preserve strictly ordered control points at tight gaps.
                da,db=np.diff(aa),np.diff(bb)
                if np.any(db < .30*da):
                    blend=min(1.,float(np.min(.70*da[db<da]/(da[db<da]-db[db<da]))))
                    bb=aa+blend*(bb-aa)
                val[i] = np.interp(grid,aa,bb)-grid
                good[i] = 1
        # Low-frequency correction only: avoid copying contour steps,
        # fingers, or JPEG edges into the side of the limb.
        conf = gaussian_filter1d(good, 6.5, axis=0)
        blur = gaussian_filter1d(val, 6.5, axis=0)/np.maximum(conf,.62)
        blur = gaussian_filter1d(blur, 2.5, axis=1, mode='nearest')
        blur[:,0] = blur[:,-1] = 0
        blur *= np.clip(np.arange(HALF+1)/8,0,1)[None,:]
        fields.append(amount * blur)
    return fields


def apply_warp(v, fields):
    out = v.copy()
    rows = np.clip((1-v[:,2])*HEIGHT,0,HEIGHT); ri = np.minimum(rows.astype(int), HEIGHT-1)
    xs = np.clip(abs(v[:,0])*HEIGHT,0,HALF); ci = np.minimum(xs.astype(int), HALF-1)
    rz,rx = rows-ri,xs-ci
    for idx,f in enumerate(fields):
        move = (1-rz)*((1-rx)*f[ri,ci]+rx*f[ri,ci+1])+rz*((1-rx)*f[ri+1,ci]+rx*f[ri+1,ci+1])
        sel = (v[:,0]<0) if idx==0 else (v[:,0]>=0)
        # Fade near the top and bottom only; avoid sole/vertex raster edge bias.
        wt = np.clip(np.minimum(rows,HEIGHT-rows)/6,0,1)
        out[sel,0] += (-1 if idx==0 else 1) * move[sel]*wt[sel]/HEIGHT
    return out


def iou(a, b):
    return float(np.count_nonzero(a&b)/np.count_nonzero(a|b))


def overlay(reference, model):
    """Green: shared, gold: missing geometry, blue: excess geometry."""
    from PIL import Image
    rgb = np.zeros((*reference.shape,3), dtype=np.uint8);rgb[:]=[34,41,50]
    rgb[(reference&model)>0]=[116,170,146]
    rgb[(reference&~model)>0]=[235,168,75]
    rgb[(~reference&model)>0]=[104,162,230]
    return Image.fromarray(rgb)
