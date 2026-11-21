// The CC0 Grab3D mesh is the authoritative rotor body. Keep source indices and
// orientation; enlarge the whole toy uniformly x88, with its tip at the pivot.
import { readFileSync } from 'node:fs';
export function sourceTop() {
  const b = readFileSync(new URL('./spinning-top.glb', import.meta.url));
  const length = b.readUInt32LE(12),
    j = JSON.parse(b.toString('utf8', 20, 20 + length));
  const prim = j.meshes[0].primitives[0],
    binary = 28 + length;
  function accessor(index, type, size, read) {
    const a = j.accessors[index],
      v = j.bufferViews[a.bufferView];
    if (a.componentType !== type || v.buffer !== 0 || a.sparse)
      throw Error('Unexpected spinning-top GLB accessor');
    const base = binary + (v.byteOffset || 0) + (a.byteOffset || 0),
      stride = v.byteStride || size;
    return Array.from({ length: a.count }, (_, i) => read(base + i * stride));
  }
  const v = accessor(prim.attributes.POSITION, 5126, 12, (o) =>
    [0, 4, 8].map((k) => 88 * b.readFloatLE(o + k)),
  );
  const indices = accessor(prim.indices, 5123, 2, (o) => b.readUInt16LE(o)),
    f = [];
  for (let i = 0; i < indices.length; i += 3) f.push(indices.slice(i, i + 3));
  return { v, f };
}
// Open three sectors in the original 44-sided turned body. Use the actual
// glTF ring vertices for the cut faces; preserve every triangle outside cuts.
export function galleryTop() {
  const mesh = sourceTop(),
    source = mesh.v,
    mm = 1000 / 88;
  const stops = [
    [0, -2.04],
    [20.5, -0.17],
    [35, -0.12],
    [47, 0.09],
    [55.074, 0.17],
    [60.88, 1],
    [79.86, 3.75],
    [94, 5.69],
  ];
  function h(y) {
    for (let i = 1; i < stops.length; i++) {
      const [b, B] = stops[i],
        [a, A] = stops[i - 1];
      if (y <= b) return A + ((B - A) * (y - a)) / (b - a);
    }
    return 5.69;
  }
  const v = source.map(([x, y, z]) => {
    const Y = y * mm,
      blend = Math.min(1, Math.max(0, (Y - 55.074) / 10));
    const k = ((9.18 / (42.225927 / 1000)) * (1 - blend) + 88 * blend) / 88;
    return [x * k, h(Y), z * k];
  });
  const sector = ([x, , z]) => ((((Math.atan2(z, x) * 44) / (2 * Math.PI)) % 44) + 44) % 44;
  const saw = [0, 15, 29],
    lo = 20.5,
    hi = 55.074;
  const f = mesh.f.filter((face) => {
    const p = face.map((i) => source[i]);
    const mid = p.reduce((q, r) => q.map((x, k) => x + r[k] / 3), [0, 0, 0]);
    return !(mid[1] * mm > lo && mid[1] * mm < hi && saw.includes(Math.floor(sector(mid))));
  });
  // Follow the original mesh edges, including the small undercut lathe grooves.
  // Sorting by height would connect across the undercuts and leave open slivers.
  const key = (p) => p.map((x) => Math.round(x * 1e5)).join(','),
    rep = new Map();
  const ids = v.map((p, i) => {
    const k = key(p);
    if (!rep.has(k)) rep.set(k, i);
    return rep.get(k);
  });
  const boundary = new Map();
  for (const face of f) {
    const q = face.map((i) => ids[i]);
    if (new Set(q).size < 3) continue;
    for (let i = 0; i < 3; i++) {
      const a = q[i],
        b = q[(i + 1) % 3],
        k = Math.min(a, b) + ':' + Math.max(a, b);
      if (boundary.has(k)) boundary.delete(k);
      else boundary.set(k, [a, b]);
    }
  }
  for (const s of saw) {
    const ends = [];
    for (const angle of [s, s + 1]) {
      const same = (i) => Math.round(sector(source[i])) % 44 === angle;
      const edges = [...boundary.values()].filter(([a, b]) => same(a) && same(b));
      const path = new Map(edges),
        to = new Set(edges.map((e) => e[1]));
      let start = edges.find(([a]) => !to.has(a))[0],
        end = start;
      const i = v.length,
        center = [0, 0, 0],
        verts = new Set(edges.flat());
      for (const k of verts) for (let d = 0; d < 3; d++) center[d] += v[k][d] / verts.size;
      v.push(center);
      for (const [a, b] of edges) f.push([i, b, a]);
      while (path.has(end)) end = path.get(end);
      f.push([i, start, end]);
      ends.push([start, end]);
    }
    const [[a, b], [c, d]] = ends;
    f.push([b, a, d], [b, d, c]);
  }
  return { v, f };
}
