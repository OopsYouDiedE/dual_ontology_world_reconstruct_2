"""Closed-loop face fit inside the game's own render (Godot toon + ink), all heroes at once.

    python godot_loop.py --heroes detective,hale,quer,lucian --iters 10

Each round asks godot_fitloop.gd for one base frame plus one probe frame per parameter (every hero
probes the same parameter in the same frame), detects MediaPipe face landmarks on all images, builds a
finite-difference Jacobian per hero and takes a damped Gauss-Newton step. Parameters are deltas on top
of the Blender fit (FACE_PARAMS from face_params.py, plus camera yaw and pitch for the painting's head
turn). The best round is folded back into tools/cast/fit/<hero>.json (targets, history, head pose);
re-export the face rig and rebuild the GLBs afterwards.
"""
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

import numpy as np

FIT = Path(__file__).resolve().parent
ROOT = FIT.parents[2]
WORK = ROOT / ".runtime" / "facefit"
GODOT = ROOT / ".runtime" / "godot" / "4.7.2" / "Godot_v4.7.2-stable_mono_win64_console.exe"
sys.path.insert(0, str(FIT))
from detect import Detector, load_rgb  # noqa: E402
from face_params import FACE, FACE_LIMIT, FACE_PARAMS, FACE_W  # noqa: E402

POSE_DEG = 20.0
F = len(FACE_PARAMS)
K = F + 2


def similarity(src, dst):
    mu_s, mu_d = src.mean(0), dst.mean(0)
    a, b = src - mu_s, dst - mu_d
    u, sig, vt = np.linalg.svd(b.T @ a)
    d = np.sign(np.linalg.det(u @ vt))
    rot = u @ np.diag([1, d]) @ vt
    s = (sig[0] + d * sig[1]) / (a ** 2).sum()
    return lambda p: s * (rot @ (p - mu_s).T).T + mu_d


def frame_spec(v):
    w = {}
    for k in range(F):
        if v[k] > 1e-4:
            w[f"p{k}"] = float(v[k])
        elif v[k] < -1e-4:
            w[f"n{k}"] = float(-v[k])
    return {"w": w, "yaw": float(v[F] * POSE_DEG), "pitch": float(v[F + 1] * POSE_DEG)}


def residual(face, ref, weights, T=None):
    a = np.array([face[i][:2] for i in FACE])
    b = np.array([ref["face"][i][:2] for i in FACE])
    iod = np.linalg.norm(np.subtract(ref["face"][33][:2], ref["face"][263][:2]))
    T = T or similarity(a, b)
    return (np.sqrt(weights)[:, None] * (T(a) - b) / iod).ravel(), T


def nme(r, weights):
    return float(np.linalg.norm(r.reshape(-1, 2) / np.sqrt(weights)[:, None], axis=1).mean())


def render(heroes, frames, out):
    out.mkdir(parents=True, exist_ok=True)
    job = {"heroes": heroes, "size": 640, "out": out.as_posix(), "frames": frames}
    path = out / "job.json"
    path.write_text(json.dumps(job))
    r = subprocess.run([str(GODOT), "--path", str(ROOT), "--script", "res://tools/cast/fit/godot_fitloop.gd",
                        "--", f"--job={path.as_posix()}"], capture_output=True, text=True)
    if "FITLOOP_DONE" not in r.stdout:
        raise RuntimeError(r.stdout[-2000:] + r.stderr[-2000:])


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--heroes", default="detective,hale,quer,lucian")
    p.add_argument("--iters", type=int, default=10)
    p.add_argument("--step", type=float, default=0.15)
    p.add_argument("--ridge", type=float, default=0.05)
    a = p.parse_args()
    heroes = a.heroes.split(",")
    det = Detector()
    refs = {h: json.loads((WORK / "ref" / f"{h}.json").read_text()) for h in heroes}
    weights = np.array([FACE_W.get(i, 1.0) for i in FACE])
    lo = np.r_[[0.0 if not neg else -FACE_LIMIT for _, neg in FACE_PARAMS], -1.25, -1.25]
    hi = np.r_[FACE_LIMIT * np.ones(F), 1.25, 1.25]
    reg = np.r_[np.ones(F), 0.0, 0.0] * a.ridge
    v = {h: np.zeros(K) for h in heroes}
    hist = {h: [] for h in heroes}
    tried = {h: [] for h in heroes}
    out = WORK / "gloop"
    for it in range(a.iters + 1):
        probes = {h: [v[h].copy()] for h in heroes}
        if it < a.iters:
            for k in range(K):
                for h in heroes:
                    q = v[h].copy()
                    q[k] += a.step if q[k] < hi[k] - a.step else -a.step
                    probes[h].append(q)
        n = len(probes[heroes[0]])
        render(heroes, [{h: frame_spec(probes[h][f]) for h in heroes} for f in range(n)], out)
        for h in heroes:
            dets = [det.run(load_rgb(out / f"{h}-{f}.png")) for f in range(n)]
            if not dets[0]["face"]:
                print("NO_FACE", h, it, flush=True)
                continue
            r0, T = residual(dets[0]["face"], refs[h], weights)
            hist[h].append(round(nme(r0, weights), 4))
            tried[h].append(v[h].copy())
            if it == a.iters:
                continue
            J = np.zeros((len(r0), K))
            for k in range(K):
                if dets[k + 1]["face"]:
                    rk, _ = residual(dets[k + 1]["face"], refs[h], weights, T)
                    J[:, k] = (rk - r0) / (probes[h][k + 1][k] - v[h][k])
            A = J.T @ J + np.diag(reg ** 2) + 1e-6 * np.eye(K)
            step = np.linalg.solve(A, -(J.T @ r0) - reg ** 2 * v[h])
            step *= min(1.0, 0.3 / max(1e-9, np.abs(step).max()))
            v[h] = np.clip(v[h] + step, lo, hi)
        print("GODOT_LOOP", it, {h: hist[h][-1] if hist[h] else None for h in heroes}, flush=True)
    for h in heroes:
        best = int(np.argmin(hist[h]))
        d = tried[h][best]
        path = FIT / f"{h}.json"
        fit = json.loads(path.read_text())
        targets = fit["targets"]
        for (pos, neg), value in zip(FACE_PARAMS, d[:F]):
            for t in (pos if value > 0 else neg):
                if abs(value) > 1e-3:
                    targets[t] = round(float(targets.get(t, 0.0) + abs(value)), 4)
        fit["godot_face_loop"] = {"nme": hist[h], "best": best,
                                  "head_pose_deg": [round(float(d[F] * POSE_DEG), 2), round(float(d[F + 1] * POSE_DEG), 2)]}
        path.write_text(json.dumps(fit, indent=1) + "\n")
        print("GODOT_FIT", h, hist[h][0], "->", hist[h][best])


if __name__ == "__main__":
    os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
    main()
