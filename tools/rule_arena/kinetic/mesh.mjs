// World-space transform: orthonormal basis columns and origin, identical to Godot Transform3D.
export const TAU = 2 * Math.PI,
  add = (a, b) => a.map((v, i) => v + b[i]),
  sub = (a, b) => a.map((v, i) => v - b[i]),
  mul = (a, k) => a.map((v) => v * k),
  dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2],
  cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]],
  norm = (a) => mul(a, 1 / (Math.hypot(...a) || 1));
export const I = (x = 0, y = 0, z = 0) => [1, 0, 0, 0, 1, 0, 0, 0, 1, x, y, z];
export const ry = (a) => [Math.cos(a), 0, -Math.sin(a), 0, 1, 0, Math.sin(a), 0, Math.cos(a), 0, 0, 0];
export const rx = (a) => [1, 0, 0, 0, Math.cos(a), Math.sin(a), 0, -Math.sin(a), Math.cos(a), 0, 0, 0];
export const rz = (a) => [Math.cos(a), Math.sin(a), 0, -Math.sin(a), Math.cos(a), 0, 0, 0, 1, 0, 0, 0];
export const vec = (m, a) => [0, 1, 2].map((i) => m[i] * a[0] + m[3 + i] * a[1] + m[6 + i] * a[2]);
export const pos = (m, a) => add(vec(m, a), m.slice(9));
export const compose = (m, n) => [
  ...vec(m, n.slice(0, 3)),
  ...vec(m, n.slice(3, 6)),
  ...vec(m, n.slice(6, 9)),
  ...pos(m, n.slice(9)),
];
export const chain = (m, ...rest) => rest.reduce(compose, m);
const inv = (m, p) => [0, 3, 6].map((i) => m[i] * p[0] + m[i + 1] * p[1] + m[i + 2] * p[2]);
function mesh() {
  return { v: [], f: [] };
}
function quad(m, a, b, c, d) {
  let i = m.v.length;
  m.v.push(a, b, c, d);
  m.f.push([i, i + 1, i + 2], [i, i + 2, i + 3]);
}
export function box(x, y, z) {
  let m = mesh(),
    p = [];
  for (let i = 0; i < 8; i++)
    p.push([(i & 1 ? 0.5 : -0.5) * x, (i & 2 ? 0.5 : -0.5) * y, (i & 4 ? 0.5 : -0.5) * z]);
  for (const ids of [
    [0, 4, 6, 2],
    [1, 3, 7, 5],
    [0, 1, 5, 4],
    [2, 6, 7, 3],
    [0, 2, 3, 1],
    [4, 5, 7, 6],
  ])
    quad(m, ...ids.map((i) => p[i]));
  return m;
}
export function lathe(profile, n = 24) {
  let m = mesh();
  const P = (i, [r, y]) => [r * Math.cos((i * TAU) / n), y, r * Math.sin((i * TAU) / n)];
  for (let i = 0; i < n; i++)
    for (let j = 1; j < profile.length; j++)
      quad(m, P(i, profile[j - 1]), P(i, profile[j]), P(i + 1, profile[j]), P(i + 1, profile[j - 1]));
  return m;
}
export function tube(points, r, n = 8) {
  let m = mesh(),
    rings = points.map((p, i) => {
      let t = norm(sub(points[Math.min(i + 1, points.length - 1)], points[Math.max(0, i - 1)])),
        a = norm(cross(t, Math.abs(t[2]) < 0.95 ? [0, 0, 1] : [0, 1, 0])),
        b = cross(t, a);
      return Array.from({ length: n }, (_, k) =>
        add(p, add(mul(a, r * Math.cos((TAU * k) / n)), mul(b, r * Math.sin((TAU * k) / n)))),
      );
    });
  for (let i = 1; i < rings.length; i++)
    for (let k = 0; k < n; k++)
      quad(m, rings[i - 1][k], rings[i][k], rings[i][(k + 1) % n], rings[i - 1][(k + 1) % n]);
  return m;
}
// Local AABB hierarchy over the SAME triangles supplied to the viewer.
export function indexMesh(m) {
  let ts = m.f.map((f) => {
    let [a, b, c] = f.map((i) => m.v[i]);
    return {
      a,
      e: sub(b, a),
      f: sub(c, a),
      lo: a.map((v, i) => Math.min(v, b[i], c[i])),
      hi: a.map((v, i) => Math.max(v, b[i], c[i])),
    };
  });
  function split(ts) {
    let lo = [Infinity, Infinity, Infinity],
      hi = lo.map(() => -Infinity);
    for (let t of ts)
      for (let i = 0; i < 3; i++) {
        lo[i] = Math.min(lo[i], t.lo[i]);
        hi[i] = Math.max(hi[i], t.hi[i]);
      }
    let node = { lo, hi };
    if (ts.length <= 12) node.ts = ts;
    else {
      let w = sub(hi, lo),
        k = w.indexOf(Math.max(...w));
      ts.sort((a, b) => a.lo[k] + a.hi[k] - b.lo[k] - b.hi[k]);
      let i = ts.length >> 1;
      node.l = split(ts.slice(0, i));
      node.r = split(ts.slice(i));
    }
    return node;
  }
  return split(ts);
}
export function intersect(node, m, origin, dir, limit = 100) {
  let o = inv(m, sub(origin, m.slice(9))),
    d = inv(m, dir),
    best = limit;
  function visit(n) {
    let lo = 0.0001,
      hi = best;
    for (let i = 0; i < 3; i++) {
      if (Math.abs(d[i]) < 1e-9) {
        if (o[i] < n.lo[i] || o[i] > n.hi[i]) return;
      } else {
        let a = (n.lo[i] - o[i]) / d[i],
          b = (n.hi[i] - o[i]) / d[i];
        lo = Math.max(lo, Math.min(a, b));
        hi = Math.min(hi, Math.max(a, b));
        if (lo > hi) return;
      }
    }
    if (!n.ts) {
      visit(n.l);
      visit(n.r);
      return;
    }
    for (let t of n.ts) {
      let p = cross(d, t.f),
        det = dot(t.e, p);
      if (Math.abs(det) < 1e-9) continue;
      let s = sub(o, t.a),
        u = dot(s, p) / det;
      if (u < 0 || u > 1) continue;
      let q = cross(s, t.e),
        v = dot(d, q) / det;
      if (v < 0 || u + v > 1) continue;
      let h = dot(t.f, q) / det;
      if (h > 0.0001 && h < best) best = h;
    }
  }
  visit(node);
  return best === limit ? null : best;
}
