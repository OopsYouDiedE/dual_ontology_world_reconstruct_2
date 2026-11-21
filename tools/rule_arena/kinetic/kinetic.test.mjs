import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { Game } from './game.mjs';
import { evalAST, decode, encode, PROOF_BASE } from './rules.mjs';
import { galleryTop, sourceTop } from './source-top.mjs';
import { pos, vec } from './mesh.mjs';
const src = readFileSync(new URL('./reference.js', import.meta.url), 'utf8');

test('upstream GLB is pinned; adapted rotor has closed cuts, a real light slot and an opaque rim', () => {
  const bytes = readFileSync(new URL('./spinning-top.glb', import.meta.url));
  assert.equal(
    createHash('sha256').update(bytes).digest('hex'),
    '87085a236d353542569799e253e84dc4528e3c94f1a4fc5ec8c1152421627a84',
  );
  assert.equal(sourceTop().f.length, 9128);
  const mesh = galleryTop(),
    edges = new Map(),
    key = mesh.v.map((p) => p.map((x) => Math.round(x * 1e5)).join(','));
  for (const face of mesh.f) {
    const q = face.map((i) => key[i]);
    if (new Set(q).size < 3) continue;
    for (let i = 0; i < 3; i++) {
      const k = [q[i], q[(i + 1) % 3]].sort().join(';');
      edges.set(k, 1 + (edges.get(k) || 0));
    }
  }
  assert.ok([...edges.values()].every((n) => n === 2));
  const g = new Game(6, 42),
    st = g.studio,
    m = st.rot;
  function ray(sector) {
    let a = (sector * Math.PI * 2) / 44;
    return st.hit(
      pos(m, [7 * Math.cos(a), -2, 7 * Math.sin(a)]),
      vec(m, [0, 1, 0]),
      5,
      (n) => n.id === 'disk',
    );
  }
  for (const k of [0, 15, 29]) {
    assert.equal(ray(k + 0.5), null);
    assert.equal(ray(k + 1.5).n.g, 'turned-top');
  }
  assert.ok(Math.abs(st.trees['turned-top'].hi[0] - 9.18) < 0.001);
});

test('changing bell heights drives the physical exit shutter after the interlock is released', () => {
  const g = new Game(3, 42);
  g.crew[1] = [0, 3.5];
  g.work(false);
  assert.equal(g.latch, false);
  assert.ok(g.studio.trees.canopy.hi[0] > 7.5);
  g.latch = true;
  let open = 0,
    closed = 0;
  for (let t = 0; t < g.studio.period * 2; t++) {
    g.step(0);
    if (t < g.studio.period) continue;
    if (g.block([0, -6.6], null)) closed++;
    else open++;
  }
  assert.ok(open >= 20 && closed >= 20);
  assert.equal(g.result, 'running');
});

test('trolley occupies the only aperture and an unsupported order still obeys physical contact', () => {
  const g = new Game(6, 42);
  for (let x = 5.54; x < 6.47; x += 0.08) assert.equal(g.block([x, 4.94], null), true);
  assert.equal(g.block([6, 4.4], null), true);
  g.step(16);
  assert.equal(g.cart, 0);
  assert.equal(g.panic, 40);
  g.cart = 2;
  g.studio.update(g.t, 0, 2);
  assert.equal(g.block([6, 4.94], null), false);
});

for (const stage of [3, 6]) {
  test(`room ${stage}: local scan, evidence rejection, counterexample and instant re-evaluation`, () => {
    const g = new Game(stage, 42),
      pick = vm.runInNewContext(src + ';decide');
    let checked = false;
    let initial = g.observe();
    assert.equal(initial.rays.length, 27);
    assert.ok(initial.rays.includes(null));
    assert.deepEqual(Object.keys(initial).sort(), ['feet', 'manuals', 'rays', 'stage', 't', 'yaw']);
    for (let n = 0; n < 2200 && g.result === 'running'; n++) {
      let o = g.observe();
      if (n % 20) assert.equal(o.rays, null);
      let act = pick(o);
      assert.notEqual(act, 16);
      if (act >= PROOF_BASE) {
        let [node, a, b, law, band] = decode(act),
          saved = JSON.stringify(g.manuals);
        for (let invalid of [
          encode(node, b, b, law, band),
          encode(0, a, b, law, band),
          encode(node, a, b, law ^ 1, band),
          encode(node, b, a, law, band),
        ])
          assert.equal(g.prove(invalid), false);
        assert.equal(saved, JSON.stringify(g.manuals));
        checked = true;
      }
      const old = g.crew.map((p) => p.slice());
      g.step(act);
      g.crew.forEach((p, i) => assert.ok(Math.hypot(p[0] - old[i][0], p[1] - old[i][1]) <= 0.080001));
    }
    assert.ok(checked);
    assert.equal(g.result, 'exit');
    assert.equal(g.panic, 0);
    const p = g.audit.find((e) => e.event === 'patch');
    assert.equal(evalAST(p.before, p.countermodel), false);
    assert.equal(evalAST(p.after, p.countermodel), true);
    for (const facts of [{ site: 'aisle' }, { workClearance: p.claim }])
      assert.equal(evalAST(p.after, { ...p.countermodel, ...facts }), false);
  });
  test(`room ${stage}: real geometry can injure a stationary body`, () => {
    const g = new Game(stage, 42);
    let found = false;
    for (let t = 0; t < g.studio.period && !found; t++) {
      g.studio.update(t + 1, 0, 0);
      let q =
        stage === 3
          ? [0, 1, 2, 3, 4, 5, 6, 7, 8, 9].map((i) => {
              let a = g.studio.bells[i],
                b = g.studio.bells[(i + 1) % 10];
              return [(a[0] + b[0]) / 2, (a[2] + b[2]) / 2];
            })
          : [
              [0, 0],
              [2, 0],
              [-2, 0],
            ];
      for (let p of q)
        if (stage === 3 ? g.pinch(p) <= 0 : g.clearance(p) < 1.64) {
          g.crew[0] = p;
          g.t = t;
          g.step(0);
          assert.equal(g.result, stage === 3 ? 'pinched' : 'struck');
          found = true;
          break;
        }
    }
    assert.ok(found);
  });
  test(`room ${stage}: both single-person handbooks keep the solitary start in the all-phase refuge`, () => {
    for (const role of [0, 1]) {
      const g = new Game(stage, 42, role);
      for (let i = 0; i < g.studio.period + 5; i++) {
        g.step(i % 80 < 45 ? 1 : 2);
        assert.ok(Math.hypot(...g.crew[0]) > (stage === 3 ? 9 : 9.8));
        assert.equal(g.result, 'running');
      }
    }
  });
  test(`room ${stage}: every generated geometry/rule class has a constructive walking witness`, () => {
    for (let seed = 32; seed < 64; seed++) {
      let g = new Game(stage, seed),
        f = vm.runInNewContext(src + ';decide');
      while (g.result === 'running' && g.t < 2000) g.step(f(g.observe()));
      assert.equal(g.result, 'exit', `seed ${seed}, tick ${g.t}`);
      assert.equal(g.panic, 0);
    }
  });
}
