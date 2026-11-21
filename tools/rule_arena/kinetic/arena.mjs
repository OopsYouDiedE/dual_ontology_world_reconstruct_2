import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash, randomBytes } from 'node:crypto';
import { Judge } from '../judge.mjs';
import { Game } from './game.mjs';
const here = path.dirname(fileURLToPath(import.meta.url)),
  args = process.argv.slice(2),
  arg = (k, f) => (args.includes(k) ? args[args.indexOf(k) + 1] : f),
  stage = Number(arg('--stage', 3)),
  seed = Number(arg('--seed', randomBytes(4).readUInt32LE()));
const hash = (b) => createHash('sha256').update(b).digest('hex'),
  inputs = [],
  recPath = arg('--out', path.resolve('.runtime/kinetic/run.json')),
  view = arg('--view', null),
  replaying = args[0] === 'replay';
let rec = replaying ? JSON.parse(fs.readFileSync(arg('--in', recPath))) : null;
if (rec && rec.v !== 'kinetic-2') throw Error('invalid pilot replay version');
let g = new Game(rec?.stage ?? stage, rec?.seed ?? seed),
  src = replaying ? '' : fs.readFileSync(arg('--bot', path.join(here, 'reference.js')), 'utf8'),
  j = replaying ? null : new Judge(src, 34000000);
function save(p, obj) {
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p + '.tmp', JSON.stringify(obj));
  fs.renameSync(p + '.tmp', p);
}
let rows = [],
  scans = [],
  cursor = 0,
  bytes,
  fd;
const spec = view ? g.studio.scene() : null;
const driven = g.studio.mov.filter((n) => !['frieze', 'wire'].includes(n.move)),
  rods = g.studio.mov.filter((n) => n.move === 'frieze');
if (view) {
  spec.moving = driven.map((n) => n.id);
  spec.frieze = rods.map((n) => [n.id, 'wire' + n.k + ':-1', 'wire' + n.k + ':1']);
  fs.mkdirSync(path.dirname(view), { recursive: true });
  bytes = Buffer.allocUnsafe(driven.length * 48 + rods.length * 4);
  fd = fs.openSync(view + '.motion', 'w');
}
function frame(o) {
  let offs = 0;
  for (let n of driven)
    for (let v of n.m) {
      bytes.writeFloatLE(v, offs);
      offs += 4;
    }
  for (let n of rods) {
    bytes.writeFloatLE(n.m[10], offs);
    offs += 4;
  }
  fs.writeSync(fd, bytes);
  rows.push([...g.crew[0], ...g.crew[1], g.yaw, g.cart, g.door, !!g.patched, g.onPlate(), g.mode]);
  if (o?.rays)
    scans.push({ at: o.feet.slice(), yaw: o.yaw, r: o.rays.map((r) => (r ? [r.kind, r.id, r.at] : null)) });
}
try {
  while (g.result === 'running' && (!rec || g.t < rec.ticks)) {
    let o = g.observe();
    if (view) frame(o);
    let code = j ? await j.decide(o) : rec.inputs[cursor]?.[0] === g.t ? rec.inputs[cursor++][1] : 0;
    if (j && code) inputs.push([g.t, code]);
    g.step(code);
  }
  if (view) frame();
} finally {
  if (j) await j.close();
  if (fd !== undefined) fs.closeSync(fd);
}
if (rec && (cursor !== rec.inputs.length || g.t !== rec.ticks || g.result !== rec.result))
  throw Error('replay diverged');
if (!rec) {
  rec = { v: 'kinetic-2', stage, seed, bot: hash(src), ticks: g.t, result: g.result, inputs };
  save(recPath, rec);
}
if (view)
  save(view, {
    stage: g.stage,
    seed: g.seed,
    ticks: g.t,
    result: g.result,
    spec,
    rows,
    scans,
    audit: g.audit,
  });
console.log(
  JSON.stringify({
    seed: g.seed,
    stage: g.stage,
    result: g.result,
    ticks: g.t,
    patches: g.audit.filter((a) => a.event === 'patch').length,
    watchdog: j?.violations ?? 0,
  }),
);
