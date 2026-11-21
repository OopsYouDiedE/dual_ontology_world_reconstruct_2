import { galleryTop } from './source-top.mjs';
import {
  TAU,
  add,
  sub,
  dot,
  norm,
  mul,
  I,
  rx,
  ry,
  rz,
  chain,
  pos,
  box,
  lathe,
  tube,
  indexMesh,
  intersect,
} from './mesh.mjs';
export const rooms = [3, 6],
  R = 9.18;
// Thirty-two fully enumerable generation classes in the review build.
export const variant = (seed) => 32 + ((seed >>> 0) % 32);
const bellProfile = [
  [0, -0.22],
  [0.13, -0.19],
  [0.23, -0.09],
  [0.255, 0.02],
  [0.213, 0.14],
  [0.12, 0.2],
  [0.055, 0.205],
  [0.045, 0.27],
  [0, 0.27],
];
// Minimum world Y over the vertices of the actual 20-sided lathe, including pendulum pitch.
function bellBottom(m) {
  const a = Math.atan2(m[7], m[1]) + Math.PI,
    k = (Math.round((a * 20) / TAU) * TAU) / 20,
    radial = m[1] * Math.cos(k) + m[7] * Math.sin(k);
  return m[10] + Math.min(...bellProfile.map(([r, y]) => r * radial + y * m[4]));
}
const cyl = (r, h, n) =>
  lathe(
    [
      [0, -h / 2],
      [r, -h / 2],
      [r, h / 2],
      [0, h / 2],
    ],
    n,
  );
const C = {
  stone: '4e5c66',
  floor: '485458',
  rim: 'b59359',
  porcelain: 'eee7d5',
  ink: '1d2529',
  red: 'c31d30',
  bronze: 'c79348',
  rail: '78848a',
  green: '5dafa1',
  blue: '406e88',
  ochre: 'e29b49',
};
export class Studio {
  constructor(stage, seed) {
    seed = variant(seed);
    this.stage = stage;
    this.seed = seed >>> 0;
    this.meshes = {};
    this.trees = {};
    this.nodes = [];
    this.mov = [];
    this.phase = ((seed % 41) * TAU) / 41;
    this.period = stage === 3 ? 320 + 20 * (seed % 4) : 600 + 40 * (seed % 5);
    this.hand = seed & 1 ? 1 : -1;
    this.plateX = this.hand * 2.4;
    this.spinRatio = 2 + (this.seed % 3);
    const put = (id, kind, g, color, m, bits = {}) => {
      let node = { id, kind, g, color: C[color] ?? color, m, ...bits };
      this.nodes.push(node);
      if (bits.move) this.mov.push(node);
      return node;
    };
    this.put = put;
    const shape = (key, g) => {
      if (!this.meshes[key]) {
        this.meshes[key] = g;
        this.trees[key] = indexMesh(g);
      }
      return key;
    };
    this.shape = shape;
    const brick = (id, kind, x, y, z, w, h, d, color, bits = {}) =>
      put(id, kind, shape(`${w},${h},${d}`, box(w, h, d)), color, I(x, y, z), bits);
    this.brick = brick;
    brick('slab', 'floor', 0, -0.12, 0, 18, 0.24, 18, 'floor');
    for (const x of [-9, 9]) brick('side' + x, 'wall', x, 0.45, 0, 0.2, 0.9, 18, 'stone', { solid: true });
    for (const z of [-9, 9]) brick('end' + z, 'wall', 0, 0.45, z, 18, 0.9, 0.2, 'stone', { solid: true });
    brick(
      'north',
      'exit',
      stage === 3 ? 0 : 8.1,
      0.015,
      stage === 3 ? -8.48 : 3.15,
      stage === 3 ? 3 : 1.7,
      0.03,
      stage === 3 ? 0.32 : 1.4,
      'green',
    );
    if (stage === 3) {
      const arms = 20;
      let rib = [
        [0, 0],
        [0.77, 0],
      ];
      for (let k = 0; k < 18; k++)
        rib.push(
          [0.74, k * 0.134],
          [0.84, k * 0.134 + 0.036],
          [0.84, k * 0.134 + 0.077],
          [0.74, k * 0.134 + 0.125],
        );
      rib.push([0, 2.42]);
      put('plinth', 'plinth', shape('flute', lathe(rib, 40)), 'porcelain', I(), { solid: true });
      put('case', 'gearbox', shape('case', cyl(1.0, 0.78, 40)), 'ink', I(0, 2.72, 0), { solid: true });
      put(
        'cable',
        'cable',
        shape(
          'lead',
          tube(
            [
              [0.8, 2.65, 0.45],
              [1.01, 2.3, 0.44],
              [1.05, 0.6, 0.48],
              [1.13, 0.08, 0.52],
              [1.68, 0.043, 0.7],
              [2.25, 0.043, 0.43],
            ],
            0.042,
          ),
        ),
        'ink',
        I(),
      );
      let armPoints = [];
      for (let k = 0; k <= 20; k++) {
        let u = k / 20;
        armPoints.push([
          2.08 * u,
          0.97 * Math.sin(Math.PI * u * 1.42) + 0.18 * u,
          0.44 * Math.sin(Math.PI * u * 1.5),
        ]);
      }
      const canopy = armPoints.map(([x, y, z], i) => [
        x * 3.63,
        y + 0.4 * Math.sin((Math.PI * i) / 20),
        z * 1.28,
      ]);
      this.tips = [armPoints.at(-1), canopy.at(-1)];
      shape('canopy', tube(canopy, 0.135, 12));
      shape('arm', tube(armPoints, 0.087, 10));
      shape('cord', cyl(0.031, 0.85, 9));
      shape('bell', lathe(bellProfile, 20));
      shape('mouth', cyl(0.14, 0.021, 14));
      for (let k = 0; k < arms; k++) {
        for (const [tag, g, color] of [
          ['arm', 'arm', 'porcelain'],
          ['cord', 'cord', 'red'],
          ['bell', 'bell', 'bronze'],
          ['seam', 'mouth', 'ink'],
        ])
          put(tag + k, tag, k >= 10 && tag === 'arm' ? 'canopy' : g, color, I(), { move: tag, k });
      }
      brick('plate', 'pressure plate', this.plateX, 0.046, 4.75, 1.4, 0.092, 1.4, 'green', { move: 'plate' });
      brick('leverbase', 'pedestal', 0, 0.48, 2.96, 0.36, 0.96, 0.38, 'ink', { solid: true });
      put(
        'lever',
        'toggle lever',
        shape(
          'switch',
          tube(
            [
              [0, 0, 0],
              [0, 0.29, 0.24],
              [0.27, 0.29, 0.24],
            ],
            0.086,
          ),
        ),
        'ochre',
        I(0, 0.98, 2.96),
        { move: 'lever' },
      );
      for (let s of [-1, 1])
        brick('jamb' + s, 'wall', s * 5, 0.57, -6.6, 8, 1.14, 0.32, 'stone', { solid: true });
      brick('door', 'shutter', 0, 1.23, -6.6, 2, 2.46, 0.3, 'rim', { move: 'door', solid: true });
    } else {
      put('disk', 'flywheel', shape('turned-top', galleryTop()), 'rim', I(), { move: 'disk' });
      // The cart runs against the face of this transverse wall; only the 1.4 m gap is passable.
      brick('guideL', 'wall', -1.85, 0.5, 4.4, 14.3, 1, 0.28, 'stone', { solid: true });
      brick('guideR', 'wall', 7.85, 0.5, 4.4, 2.3, 1, 0.28, 'stone', { solid: true });
      brick('cart', 'shutter trolley', 6, 0.64, 4.94, 1.54, 1.28, 0.72, 'blue', {
        move: 'cart',
        solid: true,
      });
      for (let k = 0; k < 4; k++)
        put('wheel' + k, 'caster', shape('caster', cyl(0.18, 0.13, 14)), 'ink', I(), { move: 'caster', k });
    }
    brick('lampSlide', 'inspection lamp', 0, 0, 0, 0.38, 0.12, 0.3, 'ochre', { move: 'lampSlide' });
    // Suspended rod study after Elias Crespin; scaled gallery frieze, not a claimed facsimile of the Louvre work.
    shape('rod', cyl(0.018, 1.5, 8));
    shape('wire', cyl(0.011, 1, 5));
    for (let k = 0; k < 128; k++) {
      put('rod' + k, 'suspended rod', 'rod', 'rail', I(), { move: 'frieze', k });
      for (let s of [-1, 1])
        put('wire' + k + ':' + s, 'suspension', 'wire', 'rail', I(), { move: 'wire', k, s });
    }
    brick('beam', 'gantry', 0, 5.5, -8.2, 17.95, 0.16, 1.65, 'ink');
    this.update(0, 0, 0);
  }
  update(t, door, cart, loaded = false, focus = 0, latched = false) {
    this.t = t;
    this.lamp = this.stage === 3 ? [focus, 2.1, 5.3] : [6.1 + focus, 1, 7.3];
    let a = (TAU * t) / this.period + this.phase;
    let flower = [],
      frame = chain(ry(a), rz(0.16 + 0.014 * Math.sin(a * 2)), I(0, 2.04, 0)),
      rot = chain(frame, ry(this.hand * a * this.spinRatio));
    let lag = [];
    if (this.stage === 3)
      for (let k = 0; k < 20; k++) {
        let row = k >= 10 ? 1 : 0,
          i = k % 10,
          b = (i * TAU) / 10,
          p = this.hand * a + i * 0.49 + row * 1.4;
        let root = chain(ry(-b), I(row ? 0.54 : 0.87, 3.08 + row * 0.46, 0), rx(p)),
          localTip = this.tips[row],
          tip = pos(root, localTip);
        // Linear forced pendulum: harmonic response to periodic lateral pivot acceleration;
        // damped steady state, projected on the local transverse plane, independent of framerate.
        let omega = (TAU * 60) / this.period,
          natural = 9.81 / 0.85,
          damp = 0.8 * omega,
          gain = (omega * omega) / (0.85 * Math.hypot(natural - omega * omega, damp));
        let swing =
          gain *
          (localTip[1] * Math.sin(p - Math.atan2(damp, natural - omega * omega)) +
            localTip[2] * Math.cos(p - Math.atan2(damp, natural - omega * omega)));
        let cord = chain(I(...tip), ry(-b), rx(swing)),
          bell = chain(cord, I(0, -0.85, 0));
        flower.push({
          arm: root,
          cord: chain(cord, I(0, -0.425, 0)),
          bell,
          seam: chain(bell, I(0, -0.192, 0)),
          pulse: bell[10] < 3.08 + row * 0.46 - Math.hypot(localTip[1], localTip[2]) - 0.85 + 0.09,
        });
      }
    this.bottom = flower.map((v) => bellBottom(v.bell));
    this.bells = flower.map((v) => v.bell.slice(9));
    this.rot = rot;
    for (let n of this.mov) {
      let m;
      switch (n.move) {
        case 'lampSlide':
          m = I(this.lamp[0], this.lamp[1] - 0.095, this.lamp[2]);
          break;
        case 'arm':
        case 'cord':
        case 'bell':
        case 'seam':
          m = flower[n.k][n.move];
          break;
        case 'door':
          m = I(0, 1.23 + door * 2.7, -6.6);
          break;
        case 'plate':
          m = I(this.plateX, loaded ? 0.006 : 0.046, 4.75);
          break;
        case 'lever':
          m = chain(I(0, 0.98, 2.96), rx(latched ? 0.92 : 0));
          break;
        case 'disk':
          m = rot;
          break;
        case 'cart':
          m = I(6 + cart, 0.64, 4.94);
          break;
        case 'caster':
          m = chain(
            I(6 + cart + (n.k & 1 ? 0.57 : -0.57), 0.19, 4.94 + (n.k & 2 ? 0.37 : -0.37)),
            rx(Math.PI / 2),
          );
          break;
        case 'frieze':
        case 'wire': {
          let y = 3.63 + 0.57 * Math.sin(a + n.k * 0.061),
            x = (n.k - 63.5) * 0.139;
          if (n.move === 'frieze') m = chain(I(x, y, -8.2), rx(Math.PI / 2));
          else {
            m = I(x, (5.42 + y) / 2, -8.2 + n.s * 0.66);
            m[4] = 5.42 - y;
          }
          break;
        }
      }
      n.m = m;
      n.pulse = n.kind === 'bell' ? flower[n.k].pulse : undefined;
    }
  }
  hit(o, d, range = 12, filter = null) {
    let picked = null;
    for (let n of this.nodes) {
      if (filter && !filter(n)) continue;
      let m = n.m;
      if (n.move === 'wire') {
        // Finite vertical nylon thread; ray-transform accounts for its nonuniform length.
        let L = m[4];
        let q = I(...m.slice(9)),
          oo = [o[0], m[10] + (o[1] - m[10]) / L, o[2]],
          dd = [d[0], d[1] / L, d[2]];
        let h = intersect(this.trees[n.g], q, oo, dd, range);
        if (h !== null) {
          range = h;
          picked = n;
        }
        continue;
      }
      let h = intersect(this.trees[n.g], m, o, d, range);
      if (h !== null) {
        range = h;
        picked = n;
      }
    }
    return picked ? { n: picked, at: add(o, mul(d, range)), distance: range } : null;
  }
  lit(at, n) {
    let clear = (dir, dist) => !this.hit(add(at, mul(dir, 0.003)), dir, dist);
    if (clear([0, 1, 0], 20)) return true;
    let lamp = this.lamp,
      delta = sub(lamp, at),
      l = Math.hypot(...delta);
    return l < 5.8 && clear(norm(delta), l);
  }
  scene() {
    return {
      meshes: this.meshes,
      nodes: this.nodes.map(({ id, g, color, m, move, kind }) => ({ id, g, color, m, move: !!move, kind })),
      moving: this.mov.map((n) => n.id),
    };
  }
}
