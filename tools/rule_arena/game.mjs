import { amendment, ast, BEAT, handbook, LIMIT, mod, phase, remaining, scan, VERSION } from './physics.mjs';
import { annex, starts, track, position, TRANSIT } from './architecture.mjs';
const ORDER = [
  'intake',
  'returns',
  'exchange',
  'wash',
  'lift',
  'airlock',
  'shutter',
  'darkroom',
  'relay',
  'meridian',
];
function rng(seed) {
  let a = seed >>> 0;
  return (n) => {
    a = (a + 0x6d2b79f5) >>> 0;
    let b = Math.imul(a ^ (a >>> 15), 1 | a);
    b ^= b + Math.imul(b ^ (b >>> 7), 61 | b);
    return ((b ^ (b >>> 14)) >>> 0) % n;
  };
}
function shuffle(a, r) {
  for (let i = a.length - 1; i > 0; i--) {
    const j = r(i + 1);
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}
function itinerary(r) {
  // Narrow domains (pressure / transfer / optical wings), all-different collapse.
  let domains = [[0], [1, 3], [2], [1, 3], [4, 5], [4, 5], [6], [7, 8], [7, 8], [9]];
  const route = Array(10);
  while (domains.some((d) => d.length)) {
    const i = domains
      .map((d) => d.length || 99)
      .indexOf(Math.min(...domains.filter((d) => d.length).map((d) => d.length)));
    const k = domains[i][r(domains[i].length)];
    route[i] = ORDER[k];
    domains = domains.map((d) => d.filter((v) => v !== k));
    domains[i] = [];
  }
  return route;
}
const rect = (kind, at, size, extra = {}) => ({ kind, at, size, lit: true, ...extra });
function room(r, name, index) {
  const n = 1 + (index >= 2) + (index >= 6),
    count = n + 2,
    anchor = r(120),
    reserved = shuffle([...Array(count).keys()], r).slice(0, n);
  const angles = shuffle([-120, -90, -60, -30, 0, 30, 60, 90, 120], r).slice(0, count);
  const banks = shuffle([0, 1, 2, 3, 4], r),
    span = 7 + r(3),
    depth = 7 + r(2);
  const pads = angles.map((angle, id) => {
    const period = [8, 10, 12][r(3)],
      width = 3 + r(period - 5),
      owner = reserved.indexOf(id),
      dist = 3 + r(2);
    const offset = owner < 0 ? r(period) : mod(r(width - 2) - anchor, period);
    const sockets = owner === 0 ? 7 : (1 + r(7)) | (owner >= 0 ? 1 << owner : 0);
    const seals = owner === 0 ? 7 : [2, 6, 9].includes(index) ? 0 : r(8) & sockets & 6;
    return {
      id,
      period,
      width,
      offset,
      bank: owner < 0 ? r(5) : banks[owner],
      arm: owner === 0 ? 0 : r(7) - 3,
      seals,
      sockets,
      at: [
        Math.round(1000 * dist * Math.sin((angle * Math.PI) / 180)) / 1000,
        1,
        Math.round(-1000 * dist * Math.cos((angle * Math.PI) / 180)) / 1000,
      ],
    };
  });
  const moment = reserved.reduce((s, id, i) => s + (i + 1) * pads[id].arm, 0),
    band = 1 + r(3);
  const gearPeriod = [6, 8, 10, 12][r(4)],
    gearOffset = mod(-anchor, gearPeriod);
  const gear = {
    period: gearPeriod,
    offset: gearOffset,
    travel: index < 2 ? 0 : 1 + r(3),
    mode: [
      'fixed',
      'return',
      'differential',
      'pump',
      'lift',
      'interlock',
      'shutter',
      'exposure',
      'relay',
      'meridian',
    ][ORDER.indexOf(name)],
  };
  const rule = ['all', ['le', 'peak', 1], ['le', 'torque', moment + band], ['ge', 'torque', moment - band]];
  if (index >= 4) rule.push(['ge', 'clearance', 0]);
  if (index >= 6) rule.push(['eq', 'contact', reserved.reduce((a, id) => a ^ (1 << pads[id].bank), 0)]);
  const shell = [
    rect('floor', [0, -0.1, 0], [2 * span, 0.2, 2 * depth]),
    rect('wall', [0, 1.75, -depth], [2 * span, 3.5, 0.2]),
    rect('wall', [0, 0.42, depth], [2 * span, 0.84, 0.2]),
    ...[-1, 1].map((s) => rect('wall', [s * span, 1.75, 0], [0.2, 3.5, 2 * depth])),
  ];
  return {
    name,
    n,
    pads,
    rule,
    gear,
    shell,
    span,
    depth,
    annex: annex(name, depth, r(2)),
    witness: { beat: anchor, ids: reserved },
  };
}
export function generate(seed) {
  const r = rng(seed);
  return itinerary(r).map((name, i) => room(r, name, i));
}
function legalLoad(room, ids, t) {
  const banks = [0, 0, 0, 0, 0];
  let torque = 0;
  ids.forEach((id, i) => {
    const p = room.pads[id];
    banks[p.bank]++;
    torque += (i + 1) * p.arm;
  });
  const k = phase(room.gear, t),
    bias = k === 0 ? 0 : ((k % 3) - 1) * room.gear.travel;
  const clearance = Math.floor(room.gear.period / 2) - k;
  const contact = banks.reduce((a, b, i) => a ^ (b % 2 << i), 0);
  return (
    ids.length === 1 ||
    ast(room.rule, { peak: Math.max(...banks), torque: torque + bias, clearance, contact })
  );
}
export function certificate(rooms) {
  // Optical coverage: every rack is on its own 30 degree bearing; all periods divide 120.
  // Each rack is observable open AND closed during a 12-beat dwell (one dark beat).
  for (const room of rooms) {
    const { ids, beat } = room.witness,
      t = beat * BEAT;
    if (
      new Set(ids).size !== room.n ||
      !legalLoad(room, ids, t) ||
      !ids.every((id, i) => {
        const p = room.pads[id];
        return ast(i === 0 ? handbook(i) : amendment(i, id), { ...p, hold: remaining(p, t) });
      })
    )
      throw Error('invalid construction witness');
  }
  // 3 scan bearings x 13 beats + 1 superperiod + 1 beat for orders + 10 transit beats.
  return rooms.length * (42 + 120 + 2 + 10) * BEAT;
}
export class Game {
  constructor(seed) {
    this.seed = seed >>> 0;
    this.rooms = generate(seed);
    this.bound = certificate(this.rooms);
    this.t = 0;
    this.i = 0;
    this.result = 'running';
    this.random = rng(this.seed ^ 0xaf74cd);
    this.people = [];
    this.enter();
  }
  get room() {
    return this.rooms[this.i];
  }
  enter() {
    this.yaw = 0;
    this.depart = -1;
    this.tracks = null;
    this.seen = new Map();
    this.lastScan = null;
    this.scanTick = -1;
    while (this.people.length < this.room.n) {
      const i = this.people.length;
      this.people.push({ manual: handbook(i), panic: 0, sanity: 100 });
    }
    for (const a of this.people) {
      a.rules = structuredClone(a.manual);
      a.id = -1;
      a.forced = false;
    }
  }
  position(i) {
    return this.tracks ? position(this.tracks[i], this.t - this.depart) : starts[i];
  }
  boxes() {
    const q = this.room;
    let shell = q.shell;
    if (this.depart >= 0) {
      const z = -q.depth,
        w = q.span - 1.275;
      shell = [
        ...q.shell.filter((b) => b.at[2] !== z),
        ...[-1, 1].map((s) => rect('wall', [s * (1.275 + w / 2), 1.75, z], [w, 3.5, 0.2])),
        ...q.annex.boxes,
      ];
    }
    return [
      ...shell,
      ...this.people.slice(1).map((a, j) => {
        const [x, z] = this.position(j + 1);
        return rect('crew', [x, 0.86, z], [0.62, 1.72, 0.62], { role: j + 1, ...a });
      }),
      rect('governor', [0, 1, 4], [1.3, 2, 1], { ...q.gear, limit: q.rule, phase: phase(q.gear, this.t) }),
      ...q.pads.map((p) => {
        const h = phase(p, this.t) < p.width ? 2 : 1.2;
        return rect('carriage', [p.at[0], h / 2, p.at[2]], [1, h, 1], {
          ...p,
          at: [p.at[0], h / 2, p.at[2]],
          lit: phase(p, this.t) !== p.period - 1,
          stroke: phase(p, this.t) < p.width ? 'extended' : 'retracted',
          hold: remaining(p, this.t),
          phase: phase(p, this.t),
          assigned: this.people.flatMap((a, i) => (a.id === p.id ? [i] : [])),
        });
      }),
    ];
  }
  observe() {
    let rays = null;
    if (this.t % BEAT === 0) {
      if (this.scanTick !== this.t) {
        const [x, z] = this.position(0);
        this.lastScan = scan(this.boxes(), this.yaw, [x, 1.45, z]);
        this.scanTick = this.t;
        for (const h of this.lastScan)
          if (h?.kind === 'carriage') {
            let s = this.seen.get(h.id) || 0;
            this.seen.set(h.id, s | (h.stroke === 'extended' ? 1 : 2));
          }
      }
      rays = this.lastScan;
    }
    return {
      t: this.t,
      stage: this.i + 1,
      yaw: this.yaw,
      ride: this.depart >= 0,
      manuals: this.people.map((a) => a.manual),
      rays,
    };
  }
  step(action = 0) {
    if (this.result !== 'running') return;
    // Coaches see one packet before every tick, including replay adjudication.
    if (this.t % BEAT === 0 && this.scanTick !== this.t) this.observe();
    if (this.depart < 0) this.command(Number.isSafeInteger(action) ? action : 0);
    this.t++;
    if (this.depart >= 0 && this.t - this.depart >= TRANSIT && this.result === 'running') {
      if (this.i === 9) this.result = 'camp';
      else {
        this.i++;
        this.enter();
      }
    }
    if (this.t >= LIMIT && this.result === 'running') this.result = 'timeout';
    if (this.t % BEAT === 0 && this.result === 'running') this.psych();
  }
  psych() {
    for (let i = 0; i < this.people.length; i++) {
      const a = this.people[i];
      if (!a.panic) continue;
      a.sanity = Math.max(0, a.sanity - Math.ceil(a.panic / 14));
      if (this.random(100) < a.panic) {
        a.rules = structuredClone(a.manual);
        a.forced = false;
        a.id = -1;
      }
      if (a.sanity <= 55 && this.random(100) < a.panic) {
        this.people[(i + 1) % this.people.length].id = -1;
        a.rules = ['all', structuredClone(a.manual), ['ge', 'hold', 100]];
      }
      if (!a.sanity) {
        this.result = 'lost';
        this.reason = 'sanity';
      }
    }
  }
  command(code) {
    if (code === 1 || code === 2) {
      this.yaw = mod(this.yaw + (code === 1 ? 60 : -60), 360);
      return;
    }
    if (code === 3 && this.t % BEAT === 0) {
      for (const a of this.people) {
        a.panic = Math.max(0, a.panic - 5);
      }
      return;
    }
    if (code === 4) {
      this.cross();
      return;
    }
    const verb = Math.floor(code / 100),
      i = Math.floor((code % 100) / 10),
      id = code % 10,
      p = this.room.pads[id],
      a = this.people[i];
    if (!a || !p || !this.seen.has(id)) return;
    if (verb === 2 && i > 0 && this.seen.get(id) === 3 && p.sockets & (1 << i)) {
      a.rules = ['any', structuredClone(a.manual), amendment(i, id)];
      a.forced = false;
    } else if (verb === 3 && i > 0) {
      a.id = id;
      a.forced = true;
      a.panic = Math.min(100, a.panic + 42);
    }
    // Reservation is reversible. The temporal clause is checked at release.
    else if (verb === 1 && ast(a.rules, { ...p, hold: Infinity })) {
      a.id = id;
      a.forced = false;
    }
  }
  cross() {
    const q = this.room,
      ids = this.people.map((a) => a.id);
    if (ids.includes(-1)) return;
    const holds = ids.map((id) => remaining(q.pads[id], this.t));
    if (!this.people.every((a, i) => a.forced || ast(a.rules, { ...q.pads[ids[i]], hold: holds[i] }))) return;
    // Grey-box adjudication: incompatible shoe, crushed before lock-in, or a coupled overload.
    if (!legalLoad(q, ids, this.t)) {
      this.result = 'lost';
      this.reason = 'shared load';
    } else if (ids.some((id, i) => !(q.pads[id].sockets & (1 << i)) || holds[i] < 20)) {
      this.result = 'lost';
      this.reason = 'shoe or lock-in';
    } else {
      this.depart = this.t;
      this.tracks = ids.map((id, i) => track(q, id, i));
    }
  }
}
export function replay(seed, events, end) {
  const g = new Game(seed);
  let k = 0;
  while (g.t < end && g.result === 'running') {
    const e = events[k];
    g.step(e?.[0] === g.t ? events[k++][1] : 0);
  }
  return g;
}
export { VERSION };
