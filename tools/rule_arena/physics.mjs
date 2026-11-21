// Public kinematics: metres, +X right, -Z forward, integer 1/60 s ticks.
export const BEAT = 20,
  LIMIT = 36000,
  VERSION = 1;
export const mod = (a, n) => ((a % n) + n) % n;
export const phase = (p, t) => mod(Math.floor(t / BEAT) + p.offset, p.period);
export const remaining = (p, t) => Math.max(0, (p.width - phase(p, t)) * BEAT - (t % BEAT));
export function ast(a, f) {
  const [op, x, y] = a;
  switch (op) {
    case 'all':
      return a.slice(1).every((k) => ast(k, f));
    case 'any':
      return a.slice(1).some((k) => ast(k, f));
    case 'bit':
      return !!(f[x] & (1 << y));
    case 'ge':
      return f[x] >= y;
    case 'eq':
      return f[x] === y;
    case 'le':
      return f[x] <= y;
    default:
      throw Error('unknown AST operator');
  }
}
export function handbook(i) {
  if (i === 0) return ['all', ['bit', 'seals', 0], ['ge', 'hold', 40]];
  if (i === 1) return ['all', ['bit', 'seals', 1], ['ge', 'arm', -1], ['ge', 'hold', 50]];
  return [
    'all',
    ['bit', 'seals', 2],
    ['any', ['all', ['le', 'arm', 1], ['ge', 'hold', 60]], ['ge', 'hold', 100]],
  ];
}
export const amendment = (i, id) => ['all', ['eq', 'id', id], ['bit', 'sockets', i], ['ge', 'hold', 40]];
export function intersect(origin, dir, box) {
  let near = 0,
    far = 12;
  for (let k = 0; k < 3; ++k) {
    const d = dir[k],
      lo = box.at[k] - box.size[k] / 2 - origin[k],
      hi = lo + box.size[k];
    if (Math.abs(d) < 1e-9) {
      if (lo > 0 || hi < 0) return null;
      continue;
    }
    const a = lo / d,
      b = hi / d;
    near = Math.max(near, Math.min(a, b));
    far = Math.min(far, Math.max(a, b));
    if (far < near) return null;
  }
  if (box.shape === 'drum') {
    // Godot review drums are upright 12-sided prisms (the bell tapers at the top).
    const r = box.size[0] / 2,
      apothem = Math.cos(Math.PI / 12),
      ratio = box.label === 'DAWN BELL' ? 0.64 : 1;
    const slope = (apothem * r * (ratio - 1)) / box.size[1],
      cap = (apothem * r * (ratio + 1)) / 2;
    for (let i = 0; i < 12; i++) {
      const a = ((i + 0.5) * Math.PI) / 6,
        x = Math.sin(a),
        z = Math.cos(a);
      const d = x * dir[0] + z * dir[2] - slope * dir[1];
      const gap =
        cap - x * (origin[0] - box.at[0]) - z * (origin[2] - box.at[2]) + slope * (origin[1] - box.at[1]);
      if (Math.abs(d) < 1e-9) {
        if (gap < 0) return null;
        continue;
      }
      if (d > 0) far = Math.min(far, gap / d);
      else near = Math.max(near, gap / d);
      if (far < near) return null;
    }
  }
  return near;
}
export function scan(boxes, yaw, origin = [0, 1.45, 0]) {
  const hits = [];
  for (const elevation of [-15, 0, 15])
    for (let j = -60; j <= 60; j += 15) {
      const a = ((yaw + j) * Math.PI) / 180,
        b = (elevation * Math.PI) / 180;
      const dir = [Math.sin(a) * Math.cos(b), Math.sin(b), -Math.cos(a) * Math.cos(b)];
      let nearest = null,
        dist = Infinity;
      for (const box of boxes) {
        const d = intersect(origin, dir, box);
        if (d !== null && d < dist) {
          nearest = box;
          dist = d;
        }
      }
      hits.push(
        !nearest || !nearest.lit ? null : { ...nearest, point: origin.map((v, k) => v + dist * dir[k]) },
      );
    }
  return hits;
}
