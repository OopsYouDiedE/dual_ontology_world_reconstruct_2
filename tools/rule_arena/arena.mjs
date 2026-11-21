import { randomBytes, createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Game, VERSION } from './game.mjs';
import { Judge } from './judge.mjs';
const here = path.dirname(fileURLToPath(import.meta.url)),
  root = path.resolve(here, '../..');
const [op = 'run', ...args] = process.argv.slice(2);
const arg = (k) => {
  const i = args.indexOf('--' + k);
  return i < 0 ? null : args[i + 1];
};
function save(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file + '.tmp', JSON.stringify(data));
  fs.renameSync(file + '.tmp', file);
}
const digest = (buf) => createHash('sha256').update(buf).digest('hex');
function tape(rec) {
  if (rec.v !== VERSION) throw Error('wrong replay version');
  const g = new Game(rec.seed);
  let at = 0,
    frames = [],
    last = '',
    rooms = [],
    scans = [];
  while (g.t < rec.end && g.result === 'running') {
    const event = rec.inputs[at];
    if (event && event[0] < g.t) throw Error('unsorted replay');
    if (g.t % 20 === 0) {
      const packet = g.observe();
      scans.push(
        packet.rays.map((h) =>
          !h
            ? '·'
            : h.kind === 'carriage'
              ? `C${h.id}${h.stroke === 'extended' ? '+' : '-'}`
              : h.kind === 'crew'
                ? `P${h.role}`
                : { governor: 'G', floor: 'F', wall: 'W', apron: 'F', fixture: 'M' }[h.kind],
        ),
      );
    }
    const q = g.room;
    if (!rooms[g.i])
      rooms.push({
        name: q.name,
        begin: g.t,
        pads: q.pads,
        gear: q.gear,
        span: q.span,
        depth: q.depth,
        boxes: q.shell,
      });
    if (g.tracks && !rooms[g.i].tracks) rooms[g.i].tracks = g.tracks;
    const s = [g.i, g.yaw, g.depart, g.people.map((p) => [p.id, p.panic, p.sanity])],
      key = JSON.stringify(s);
    if (key !== last) {
      frames.push([g.t, ...s]);
      last = key;
    }
    g.step(event?.[0] === g.t ? rec.inputs[at++][1] : 0);
  }
  if (at !== rec.inputs.length || g.result !== rec.result || g.t !== rec.end) throw Error('replay diverged');
  return { rooms, frames, scans, end: g.t, result: g.result, seed: g.seed };
}
if (op === 'run') {
  const raw = arg('seed'),
    seed = raw === null ? randomBytes(4).readUInt32LE() : Number(raw);
  if (!Number.isInteger(seed) || seed < 0 || seed > 0xffffffff) throw Error('seed must be uint32');
  const bot = fs.readFileSync(arg('bot') || path.join(here, 'reference.js'), 'utf8'),
    g = new Game(seed),
    j = new Judge(bot),
    inputs = [];
  try {
    while (g.result === 'running') {
      const code = await j.decide(g.observe());
      if (code) inputs.push([g.t, code]);
      g.step(code);
    }
  } finally {
    await j.close();
  }
  const rec = { v: VERSION, seed, bot: digest(bot), end: g.t, result: g.result, inputs };
  const file = arg('out') || path.join(root, '.runtime', 'rule-arena', `${seed}.json`);
  save(file, rec);
  if (arg('view')) save(arg('view'), tape(rec));
  console.log(
    JSON.stringify({
      seed,
      result: g.result,
      stage: g.i + 1,
      cause: g.reason || g.result,
      ticks: g.t,
      bytes: fs.statSync(file).size,
      watchdog: j.violations,
      exhausted: j.denied,
      sha256: digest(fs.readFileSync(file)),
    }),
  );
} else if (op === 'replay') {
  const data = tape(JSON.parse(fs.readFileSync(arg('in'), 'utf8')));
  if (arg('view')) save(arg('view'), data);
  console.log(JSON.stringify({ result: data.result, ticks: data.end }));
} else throw Error('expected run or replay');
