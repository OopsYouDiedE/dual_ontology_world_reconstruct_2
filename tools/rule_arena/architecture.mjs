import fs from 'node:fs';
const plans = JSON.parse(fs.readFileSync(new URL('./blockouts.json', import.meta.url)));
const box = (kind, at, size, extra = {}) => ({ kind, at, size, lit: true, ...extra });
// Split the same axis-aligned ArchBuilder segments around their real openings.
function wall(a, b, h, holes, z) {
  const len = Math.hypot(b[0] - a[0], b[1] - a[1]),
    dx = (b[0] - a[0]) / len,
    dz = (b[1] - a[1]) / len,
    out = [];
  function piece(l, r, y0, y1) {
    if (r - l < 0.0001 || y1 - y0 < 0.0001) return;
    const m = (l + r) / 2;
    out.push(
      box(
        'wall',
        [a[0] + dx * m, (y0 + y1) / 2, z + a[1] + dz * m],
        [Math.abs(dx) * (r - l) + Math.abs(dz) * 0.24, y1 - y0, Math.abs(dz) * (r - l) + Math.abs(dx) * 0.24],
      ),
    );
  }
  let last = 0;
  for (const [c, w, top] of holes) {
    piece(last, c - w / 2, 0, h);
    piece(c - w / 2, c + w / 2, top, h);
    last = c + w / 2;
  }
  piece(last, len, 0, h);
  return out;
}
export function annex(name, depth, k) {
  const p = plans[name],
    z = -depth - p.size[1] / 2 - 0.5,
    x = p.size[0] / 2,
    d = p.size[1] / 2;
  const walls = [
    [[-x, d], [-1.275, d], 0.78, []],
    [[1.275, d], [x, d], 0.78, []],
    [[-x, -d], [x, -d], p.height, p.terminal ? [] : [[x + p.exit, 2.55, 2.52]]],
    [[-x, d], [-x, -d], p.height, []],
    [[x, -d], [x, d], p.height, []],
    ...p.walls,
  ];
  const boxes = [
    box('floor', [0, -0.11, z], [x * 2, 0.22, d * 2]),
    box('apron', [0, -0.12, -depth - 0.25], [2.55, 0.24, 0.5]),
    ...walls.flatMap((w) => wall(...w, z)),
    ...p.fixtures.map(([label, at, size, shape]) =>
      box('fixture', [at[0], at[1], at[2] + z], size, { label, shape }),
    ),
  ];
  if (!p.terminal) boxes.push(box('apron', [p.exit, -0.12, z - d - 1], [3.5, 0.24, 2]));
  return { boxes, route: p.routes[k % p.routes.length].map(([x, v]) => [x, z + v]), z };
}
export const TRANSIT = 200;
export const starts = [
  [0, 0],
  [-1.4, 1.8],
  [1.4, 1.8],
];
export function track(q, id, i) {
  const p = q.pads[id],
    path = [[0, 0], [0, -q.depth], ...q.annex.route],
    lens = path.slice(1).map((v, j) => Math.hypot(v[0] - path[j][0], v[1] - path[j][1])),
    total = lens.reduce((a, b) => a + b);
  let at = 0;
  return [
    [0, starts[i]],
    [24, [p.at[0] * 0.72, p.at[2] * 0.72]],
    [42 + i * 4, path[0]],
    ...lens.map((len, j) => [42 + i * 4 + Math.round(((150 - i * 4) * (at += len)) / total), path[j + 1]]),
  ];
}
export function position(keys, t) {
  let i = 1;
  while (i < keys.length && keys[i][0] < t) i++;
  if (i === keys.length) return keys.at(-1)[1];
  const [s, a] = keys[i - 1],
    [e, b] = keys[i],
    k = (t - s) / (e - s || 1);
  return a.map((v, j) => v + (b[j] - v) * k);
}
