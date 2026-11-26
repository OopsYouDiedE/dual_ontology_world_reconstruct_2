"""Left/right partner of each of MediaPipe's 468 face landmarks, voted over several detected faces.

    python face_pairs.py <landmark json> [...] --out face_pairs.json

For each face the symmetry axis is fitted through the midline landmarks (forehead, nose ridge, philtrum,
lips, chin); every landmark is mirrored across it and matched to its nearest landmark. The partner kept
for each index is the one most faces agree on, and only mutual pairs survive.
"""
import argparse
import json
from collections import Counter
from pathlib import Path

import numpy as np
from scipy.spatial import cKDTree

MIDLINE = [10, 151, 9, 8, 168, 6, 197, 195, 5, 4, 1, 19, 94, 2, 164, 0, 11, 12, 13, 14, 15, 16, 17, 18,
           200, 199, 175, 152]


def mirrored(face):
    p = np.asarray(face, float)[:468, :2]
    mid = p[MIDLINE]
    c = mid.mean(0)
    u = np.linalg.svd(mid - c)[2][0]
    d = p - c
    return p, c + 2 * np.outer(d @ u, u) - d


def pairs_of(face):
    p, m = mirrored(face)
    return cKDTree(p).query(m)[1]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("faces", nargs="+", type=Path)
    ap.add_argument("--out", type=Path, required=True)
    a = ap.parse_args()
    votes = [Counter() for _ in range(468)]
    for f in a.faces:
        face = json.loads(f.read_text())["face"]
        for i, j in enumerate(pairs_of(face)):
            votes[i][int(j)] += 1
    best = [v.most_common(1)[0][0] for v in votes]
    pair = [b if best[b] == i else i for i, b in enumerate(best)]
    for i in MIDLINE:
        pair[i] = i
    # Drop pairs whose mirror images land far apart on the faces (median over faces > 3 % of face width).
    err = []
    for f in a.faces:
        p, m = mirrored(json.loads(f.read_text())["face"])
        err.append(np.linalg.norm(m - p[pair], axis=1) / np.ptp(p[:, 0]))
    err = np.median(err, axis=0)
    pair = [j if err[i] < 0.03 or i in MIDLINE else i for i, j in enumerate(pair)]
    pair = [j if pair[j] == i else i for i, j in enumerate(pair)]
    agree = sum(votes[i][pair[i]] for i in range(468)) / (468 * len(a.faces))
    a.out.write_text(json.dumps({"faces": len(a.faces), "agreement": round(agree, 3), "midline": MIDLINE,
                                 "pair": pair}) + "\n")
    print("PAIRS", len(a.faces), "faces, agreement", round(agree, 3), "self-paired", sum(p == i for i, p in enumerate(pair)))


if __name__ == "__main__":
    main()
