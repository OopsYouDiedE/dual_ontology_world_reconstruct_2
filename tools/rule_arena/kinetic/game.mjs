import { Studio } from './studio.mjs';
import { I, TAU, norm, add, mul, sub } from './mesh.mjs';
import { SHEETS, evalAST, replacement, decode, PROOF_BASE, WINDOW, CLAIMS } from './rules.mjs';
const SPEED = 0.08,
  HEAD = 1.64,
  EPS = 0.00001,
  clamp = (v, a, b) => Math.min(b, Math.max(a, v)),
  dist = (p, q) => Math.hypot(p[0] - q[0], p[1] - q[1]);
const DIR = [
  [0, 0],
  [0, -1],
  [1, 0],
  [0, 1],
  [-1, 0],
];
function segment(p, a, b) {
  let x = b[0] - a[0],
    z = b[2] - a[2],
    u = clamp(((p[0] - a[0]) * x + (p[1] - a[2]) * z) / (x * x + z * z || 1), 0, 1);
  return dist(p, [a[0] + u * x, a[2] + u * z]);
}
export class Game {
  constructor(stage = 3, seed = 42, soloRole = null) {
    if (![3, 6].includes(stage)) throw Error('pilot stages are 3 or 6');
    this.stage = stage;
    this.seed = seed >>> 0;
    this.studio = new Studio(stage, seed);
    this.t = 0;
    this.crew =
      stage === 3
        ? [
            [0, 6.55],
            [1.5, 6.55],
          ]
        : [
            [5.8, 8.1],
            [7.0, 8.35],
          ];
    this.reach = stage === 3 ? 0.59 : 0.94;
    this.localRule = stage === 3 ? ['eq', 'plateCount', 1] : ['eq', 'inTravel', 0];
    if (this.seed & 4)
      this.localRule = [
        'and',
        this.localRule,
        stage === 3 ? ['not', 'doorwayOccupied'] : ['eq', 'atHandle', 1],
      ];
    this.soloRole = soloRole;
    if (soloRole !== null) {
      if (![0, 1].includes(soloRole)) throw Error('invalid role');
      this.crew = [stage === 3 ? [8, 8.15] : [5.8, 8.1]];
    }
    this.yaw = 0;
    this.cart = 0;
    this.focus = 0;
    this.door = 0;
    this.latch = false;
    this.manuals = structuredClone(SHEETS[stage]);
    if (this.seed & 2) {
      const clause = this.manuals[1][2];
      clause[1] = 'Leave an extra step when passing at the narrow wall.';
      clause[2] = ['or', ['gt', 'separation', 0.76], ['and', ['not', 'narrow'], ['gt', 'separation', 0.6]]];
    }
    this.original = structuredClone(this.manuals);
    this.mode = 0;
    this.target = null;
    this.last = '';
    this.receipts = new Map();
    this.audit = [];
    this.result = 'running';
    this.scanAt = -1;
    this.panic = 0;
    this.sanity = 100;
    this.rand = (seed ^ 123459) >>> 0;
    this.force = 0;
  }
  nextRand() {
    this.rand = (Math.imul(this.rand, 1664525) + 1013904223) >>> 0;
    return this.rand / 4294967296;
  }
  get site() {
    return this.stage === 3 ? 'lever' : 'cart';
  }
  get station() {
    return this.stage === 3 ? [0, 2.96] : [5.05 + this.cart, 4.97];
  }
  block(p, other) {
    if (Math.max(Math.abs(p[0]), Math.abs(p[1])) > 8.65 || (other && dist(p, other) < 0.58)) return true;
    for (let n of this.studio.nodes) {
      if (!n.solid) continue;
      if (n.id === 'door' && this.door > 0.66) continue;
      let [x, , z] = n.m.slice(9),
        { lo, hi } = this.studio.trees[n.g];
      if (
        p[0] > x + lo[0] - 0.23 &&
        p[0] < x + hi[0] + 0.23 &&
        p[1] > z + lo[2] - 0.23 &&
        p[1] < z + hi[2] + 0.23
      )
        return true;
    }
    return false;
  }
  // Feet, crown and a four-point shoulder footprint use the actual mesh. The conservative guard includes
  // one step of motion and a shoulder margin. Pinch exists only between neighbouring physical bells.
  clearance(p) {
    let best = 12;
    for (let [dx, dz] of [
      [0, 0],
      [0.22, 0],
      [-0.22, 0],
      [0, 0.22],
      [0, -0.22],
    ]) {
      let h = this.studio.hit([p[0] + dx, 0.01, p[1] + dz], [0, 1, 0], 12, (n) => n.id === 'disk');
      if (h) best = Math.min(best, h.at[1]);
    }
    return best;
  }
  pinch(p) {
    let guard = 10;
    const bs = this.studio.bells;
    for (let row of [0, 10])
      for (let j = 0; j < 10; j++) {
        let a = bs[row + j],
          b = bs[row + ((j + 1) % 10)];
        let lo = Math.max(this.studio.bottom[row + j], this.studio.bottom[row + ((j + 1) % 10)]) - 1.5,
          offset = segment(p, a, b) - 0.3;
        guard = Math.min(guard, Math.max(lo, offset));
      }
    return guard;
  }
  facts(i, p, work = false) {
    let bellGuard = this.stage === 3 ? this.pinch(p) : 10,
      headroom = this.stage === 6 ? this.clearance(p) : 12;
    return {
      narrow: Math.abs(p[1] - (this.stage === 3 ? -6.6 : 4.4)) < 0.55,
      lookout: this.crew[0][1] < 4.02,
      alone: this.crew.length === 1,
      radius: Math.hypot(...p),
      bellGuard,
      headroom,
      work,
      site: dist(p, this.station) < this.reach ? this.site : 'aisle',
      marked: this.stage === 3 ? Math.hypot(...this.station) < 3.4 : Math.hypot(...this.station) < 8.9,
      workClearance:
        this.stage === 3
          ? Math.max(...[2, 3].map((k) => this.studio.bottom[k]))
          : work
            ? Math.min(headroom, this.clearance(this.station))
            : headroom,
      separation: this.crew[1 - i] ? dist(p, this.crew[1 - i]) : 99,
    };
  }
  ok(i, p, work = false) {
    let f = this.facts(i, p, work);
    return this.manuals[this.soloRole ?? i].every((r) => evalAST(r[2], f));
  }
  get near() {
    return dist(this.crew[1], this.station) < this.reach;
  }
  scan() {
    if (this.scanAt === this.t) return this.rays;
    this.scanAt = this.t;
    let [x, z] = this.crew[0],
      rays = [];
    const st = this.studio;
    for (let el of [-15, 0, 15])
      for (let az = -60; az <= 60; az += 15) {
        let a = ((az + this.yaw) * Math.PI) / 180,
          b = (el * Math.PI) / 180,
          o = [x, 1.45, z],
          d = [Math.sin(a) * Math.cos(b), Math.sin(b), -Math.cos(a) * Math.cos(b)],
          h = st.hit(o, d),
          other = this.crew[1],
          crew = st.trees['crew'];
        if (!crew) {
          st.shape('crew', awaitlessBox(0.5, 1.64, 0.5));
          crew = st.trees.crew;
        }
        let ch = other ? rayMesh(crew, I(other[0], 0.82, other[1]), o, d, h?.distance ?? 12) : null;
        if (ch !== null) {
          let at = add(o, mul(d, ch));
          rays.push(
            st.lit(at)
              ? {
                  id: 'mate',
                  kind: 'crew',
                  at,
                  size: [0.5, 1.64, 0.5],
                  center: [other[0], 0.82, other[1]],
                  rules: this.manuals[1],
                  panic: this.panic,
                  sanity: this.sanity,
                  order: this.mode,
                }
              : null,
          );
          continue;
        }
        if (!h || !st.lit(h.at, h.n)) {
          rays.push(null);
          continue;
        }
        let n = h.n,
          m = n.m,
          tree = st.trees[n.g],
          ticket = ((this.t / 20) * 27 + rays.length) % WINDOW;
        let r = {
          ticket,
          t: this.t,
          id: n.id,
          kind: n.kind,
          at: h.at,
          pose: m.slice(),
          size: sub(tree.hi, tree.lo),
          geometry: n.g,
        };
        if (n.k !== undefined) r.index = n.k;
        if (
          ['bell', 'cord', 'arm', 'flywheel', 'spindle', 'inlay', 'suspended rod', 'suspension'].includes(
            n.kind,
          )
        ) {
          r.period = st.period;
          r.hand = st.hand;
        }
        if (n.kind === 'bell') {
          r.k = n.k;
          r.bottom = st.bottom[n.k];
          r.pulse = n.pulse;
        }
        if (['toggle lever', 'pressure plate', 'shutter trolley'].includes(n.kind))
          r.interlock = this.localRule;
        if (n.kind === 'toggle lever') r.latched = this.latch;
        if (n.kind === 'pressure plate') r.loaded = this.onPlate();
        if (n.id === 'cart') r.travel = this.cart;
        if (n.id === 'lampSlide') r.travel = this.focus;
        if (n.kind === 'flywheel') {
          r.axialHeight = [0, 1, 2].reduce((sum, i) => sum + (r.at[i] - m[9 + i]) * m[3 + i], 0);
          r.tiltMax = 0.175;
          r.spinRatio = st.spinRatio;
        }
        if (n.kind === 'shutter') {
          r.open = this.door;
          r.linkedBells = [17, 18];
          r.latched = this.latch;
        }
        this.receipts.set(ticket, r);
        rays.push(r);
      }
    return (this.rays = rays);
  }
  observe() {
    return {
      t: this.t,
      stage: this.stage,
      feet: this.crew[0],
      yaw: this.yaw,
      manuals: this.original,
      rays: this.t % 20 === 0 ? this.scan() : null,
    };
  }
  prove(n) {
    let [node, a, b, law, band] = decode(n),
      u = this.receipts.get(a),
      v = this.receipts.get(b);
    if (
      law !== (this.stage === 3 ? 0 : 1) ||
      band >= CLAIMS.length ||
      node !== 1 ||
      !u ||
      !v ||
      u.t >= v.t ||
      this.t - u.t > 680 ||
      v.t - u.t < 20 ||
      u.id !== v.id ||
      this.patched
    )
      return false;
    // Construct an actual counterexample: two measurements of THIS part, resolved motion,
    // and a lower bound for the tool footprint deep enough to contradict the absolute prohibition.
    let bound = 0,
      site = this.station;
    if (this.stage === 3) {
      if (v.kind !== 'bell' || ![2, 3].includes(v.k) || Math.abs(u.bottom - v.bottom) < 0.045) return false;
      bound = v.bottom;
    } else {
      if (
        v.id !== 'disk' ||
        Math.abs(u.pose[1] - v.pose[1]) + Math.abs(u.pose[4] - v.pose[4]) + Math.abs(u.pose[7] - v.pose[7]) <
          0.012
      )
        return false;
      let [nx, ny, nz] = v.pose.slice(3, 6);
      bound =
        v.at[1] -
        (nx * (site[0] - v.at[0]) + nz * (site[1] - v.at[2])) / ny -
        (v.axialHeight + 0.18) / ny -
        1.2 * Math.tan(0.175);
    }
    let threshold = CLAIMS[band];
    if (threshold < (this.stage === 3 ? 1.88 : 1.9) || bound <= threshold) return false;
    let rule = this.manuals[1][node],
      before = rule[2],
      after = replacement(before, this.site, threshold);
    const countermodel = {
      lookout: this.crew[0][1] < 4.02,
      work: true,
      marked: Math.hypot(...site) < (this.stage === 3 ? 3.4 : 8.9),
      site: this.site,
      workClearance: bound,
    };
    if (evalAST(before, countermodel) || !evalAST(after, countermodel)) return false;
    rule[2] = after;
    this.patched = true;
    this.audit.push({
      t: this.t,
      event: 'patch',
      rule: rule[0],
      site: this.site,
      receipts: [u, v],
      inference: law === 0 ? 'adjacent-high' : 'plane-envelope',
      claim: threshold,
      countermodel,
      bound,
      before,
      after: rule[2],
    });
    return true;
  }
  onPlate() {
    return this.crew.some((p) => Math.abs(p[0] - this.studio.plateX) < 0.7 && Math.abs(p[1] - 4.75) < 0.7);
  }
  work(forced) {
    if (!this.near || (!forced && !this.ok(1, this.crew[1], true))) return;
    if (this.stage === 3 ? this.pinch(this.station) <= 0 : this.clearance(this.station) < HEAD) {
      this.result = this.stage === 3 ? 'pinched' : 'struck';
      return;
    }
    if (this.stage === 3) {
      if (
        evalAST(this.localRule, {
          plateCount: this.crew.filter(
            (p) => Math.abs(p[0] - this.studio.plateX) < 0.7 && Math.abs(p[1] - 4.75) < 0.7,
          ).length,
          doorwayOccupied: this.crew.some((p) => Math.abs(p[0]) < 1.25 && Math.abs(p[1] + 6.6) < 0.55),
        }) &&
        !this.latch
      ) {
        this.latch = true;
        this.audit.push({ t: this.t, event: 'lever' });
      }
    } else {
      let next = Math.min(2, this.cart + 0.04);
      const inTravel = this.crew.filter(
          ([x, z]) => Math.abs(x - (6 + next)) < 0.77 + 0.22 && Math.abs(z - 4.94) < 0.36 + 0.22,
        ).length,
        atHandle = this.crew.filter((p) => dist(p, this.station) < this.reach).length;
      if (!evalAST(this.localRule, { inTravel, atHandle })) return;
      this.cart = next;
    }
  }
  step(code = 0) {
    if (this.result !== 'running') return;
    if (this.t % 20 === 0) this.scan();
    if (this.crew.length > 1 && code >= PROOF_BASE) this.prove(code);
    if (code === 8 || code === 9) {
      const lamp = this.studio.lamp;
      if (dist(this.crew[0], [lamp[0], lamp[2]]) < 1.4)
        this.focus = clamp(this.focus + (code === 8 ? -0.04 : 0.04), -1.25, 1.25);
    }
    if (code === 5 || code === 6) this.yaw = (this.yaw + (code === 5 ? 15 : 345)) % 360;
    if (code >= 10 && code <= 14) {
      this.mode = code - 10;
      this.target = null;
    }
    if (code >= 1000 && code < 33761) {
      let k = code - 1000;
      this.target = [(Math.floor(k / 181) - 90) / 10, ((k % 181) - 90) / 10];
      this.mode = 0;
    }
    if (this.crew.length > 1 && code === 16) {
      this.force = 20;
      this.panic = Math.min(100, this.panic + 40);
    }
    if (code === 17 && this.t % 20 === 0) this.panic = Math.max(0, this.panic - 6);
    for (let i = 0; i < this.crew.length; i++) {
      let a = i ? this.mode : code;
      let delta;
      if (i && this.target) {
        let off = sub(this.target, this.crew[i]),
          d = Math.hypot(...off);
        if (d < 0.001) continue;
        delta = mul(off, Math.min(SPEED, d) / d);
      } else {
        if (a < 1 || a > 4) continue;
        delta = mul(DIR[a], SPEED);
      }
      if (!i && this.stumble) {
        this.stumble = false;
        continue;
      }
      let p = add(this.crew[i], delta);
      if (!this.block(p, this.crew[1 - i]) && ((!i && this.soloRole === null) || this.force || this.ok(i, p)))
        this.crew[i] = p;
    }
    if (this.crew.length > 1 && (code === (this.stage === 3 ? 15 : 18) || this.force))
      this.work(this.force > 0);
    if (this.force) this.force--;
    if (this.latch) {
      const lift = Math.min(this.studio.bottom[17], this.studio.bottom[18]);
      const target = clamp((lift - 1.65) / 0.84, 0, 1),
        inDoor = this.crew.some(([x, z]) => Math.abs(x) < 1.23 && Math.abs(z + 6.6) < 0.58);
      const next = this.door + clamp(target - this.door, -0.025, 0.025);
      this.door = inDoor ? Math.max(this.door, next) : next;
    }
    this.t++;
    this.studio.update(this.t, this.door, this.cart, this.onPlate(), this.focus, this.latch);
    if (this.t % 20 === 0 && this.panic) {
      this.sanity -= Math.ceil(this.panic / 14);
      if (this.nextRand() * 100 < this.panic) {
        this.mode = 0;
        this.target = null;
        this.force = 0;
        this.manuals[1] = structuredClone(this.original[1]);
        this.patched = false;
      }
      if (this.sanity <= 55 && this.nextRand() * 100 < this.panic) {
        this.manuals[1][2][2] = ['gt', 'separation', 1.3];
        this.stumble = true;
      }
    }
    for (let p of this.crew) {
      if (this.stage === 3 ? this.pinch(p) <= 0 : this.clearance(p) < HEAD) {
        this.result = this.stage === 3 ? 'pinched' : 'struck';
        break;
      }
    }
    if (this.sanity <= 0) this.result = 'forgotten';
    if (
      this.result === 'running' &&
      this.crew.every((p) =>
        this.stage === 3
          ? Math.abs(p[0]) <= 1.45 && Math.abs(p[1] + 8.48) <= 0.12
          : Math.abs(p[0] - 8.1) < 0.85 && Math.abs(p[1] - 3.15) < 0.7,
      )
    )
      this.result = 'exit';
    if (this.t >= 36000 && this.result === 'running') this.result = 'timeout';
  }
}
import { box as awaitlessBox, intersect as rayMesh } from './mesh.mjs';
