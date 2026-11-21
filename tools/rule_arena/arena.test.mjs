import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { Game, certificate, generate, replay } from './game.mjs';
import { scan, ast, handbook, remaining } from './physics.mjs';
import { Judge } from './judge.mjs';
const source = fs.readFileSync(new URL('./reference.js', import.meta.url), 'utf8');
test('construction proof; every stamp implies solo safety, common witness and bounded horizon', () => {
  for (let seed = 0; seed < 1024; seed++) {
    const rooms = generate(seed);
    assert.equal(new Set(rooms.map((r) => r.name)).size, 10);
    assert.ok(certificate(rooms) < 36000);
    for (const room of rooms) {
      assert.equal(room.pads.filter((p) => p.seals === 7).length, 1);
      for (const p of room.pads)
        for (let i = 0; i < 3; i++)
          for (let k = 0; k < p.period; k++) {
            const hold = remaining(p, k * 20);
            if (ast(handbook(i), { ...p, hold })) assert.ok(p.sockets & (1 << i) && hold >= 20);
          }
    }
  }
});
test('nearest dark surface blocks all information behind it; closed FOV and scan cadence', () => {
  const box = (z, lit) => ({ kind: 'test', at: [0, 1.45, z], size: [1, 1, 1], lit });
  assert.equal(scan([box(-2, false), box(-3, true)], 0)[13], null);
  assert.deepEqual(scan([box(-3, true)], 0)[13].point, [0, 1.45, -2.5]);
  for (const a of [-60, 60]) {
    const v = (a * Math.PI) / 180;
    const rays = scan([{ ...box(0, true), at: [3 * Math.sin(v), 1.45, -3 * Math.cos(v)] }], 0);
    assert.ok(rays[a < 0 ? 9 : 17]);
  }
  const g = new Game(89);
  assert.equal(g.observe().rays.length, 27);
  g.step();
  assert.equal(g.observe().rays, null);
});
test('observed evidence is local; reservations and argument cost; group collision and sanity loss', () => {
  const g = new Game(99);
  g.i = 6;
  g.enter();
  const q = g.room,
    { ids } = q.witness;
  const beat = Array.from({ length: 120 }, (_, i) => i).find((k) => remaining(q.pads[ids[0]], k * 20) >= 60);
  const other = ids[1];
  g.command(210 + other);
  assert.deepEqual(g.people[1].rules, handbook(1));
  g.seen.set(other, 1);
  g.command(210 + other);
  assert.deepEqual(g.people[1].rules, handbook(1));
  g.seen.set(other, 3);
  g.command(210 + other);
  assert.equal(g.people[1].rules[0], 'any');
  assert.equal(g.people[1].panic, 0);
  g.command(310 + other);
  assert.equal(g.people[1].panic, 42);
  assert.equal(g.people[1].forced, true);
  for (let i = 0; i < 100; i++) g.psych();
  assert.equal(g.result, 'lost');
  const h = new Game(99);
  h.i = 6;
  h.enter();
  h.t = beat * 20;
  h.people.forEach((a) => (a.id = ids[0]));
  h.cross();
  assert.equal(h.result, 'lost');
});
test('blind reference, exact replay and seed diversity; never sends the judge world or seed', () => {
  const ends = [];
  for (let seed = 0; seed < 32; seed++) {
    // Accelerated logic suite; ONLY the separately timed CLI is an official match.
    const f = vm.runInNewContext(source + ';decide', {});
    const g = new Game(seed),
      inputs = [];
    while (g.result === 'running') {
      const o = g.observe();
      assert.equal(o.seed, undefined);
      const a = f(o);
      if (a) inputs.push([g.t, a]);
      g.step(a);
    }
    assert.equal(g.result, 'camp', `seed ${seed}`);
    ends.push(g.t);
    assert.ok(g.t <= g.bound);
    const h = replay(seed, inputs, g.t);
    assert.equal(h.result, 'camp');
    assert.deepEqual(h.people, g.people);
  }
  assert.ok(new Set(ends).size > 10);
});
test('hard deadline, lockout, fixed cycle reset and guest isolation', async () => {
  const j = new Judge(
    `function decide(o){if(typeof process!=='undefined'||typeof require!=='undefined'||typeof Date!=='undefined')return 9;if(o.t===0)while(true){};return 1;}`,
  );
  try {
    assert.equal(await j.decide({ t: 0 }), 0);
    for (let t = 1; t < 20; t++) assert.equal(await j.decide({ t }), 0);
    assert.equal(await j.decide({ t: 20 }), 1);
    assert.equal(j.violations, 1);
    j.left = 0;
    assert.equal(await j.decide({ t: 21 }), 0);
  } finally {
    await j.close();
  }
});
test('deadline exact last tick and idle timeout', () => {
  const g = new Game(7);
  g.t = 35999;
  g.step();
  assert.equal(g.result, 'timeout');
  const h = new Game(7);
  h.i = 9;
  h.enter();
  h.t = 35999;
  h.depart = 35800;
  h.step();
  assert.equal(h.result, 'camp');
});
import { verify } from './witness.mjs';
test('certificate can actually be played, earning every receipt on the public scan lattice', () => {
  for (const s of [0, 1, 19, 47, 122, 913, 2147483648, 4294967295]) assert.ok(verify(s) <= 34800);
});
