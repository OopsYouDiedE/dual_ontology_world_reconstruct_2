// Pilot tour policy. Uses the published fixed exhibition floorplan and observed counterexamples;
// never receives a seed, hazard flag, proof receipt ledger, or a map of the current mechanism.
let plateX = -2.4,
  seen = {},
  age = 0,
  started = false,
  proved = false,
  period,
  phaseAt,
  phaseTick,
  script = [],
  index = 0,
  remain = 0;
const target = (x, z) => 1000 + (Math.round(x * 10) + 90) * 181 + Math.round(z * 10) + 90;
const proof = (a, b, flower) =>
  100000 + (flower ? 0 : 3 * 4194304) + 1024 * 1024 + a.ticket * 1024 + b.ticket;
function decide(o) {
  let isFlower = o.stage === 3;
  if (o.rays) {
    for (const v of o.rays) {
      if (!v) continue;
      if (v.hand) plateX = v.hand * 2.4;
      if (v.id === 'disk') {
        phaseAt = Math.atan2(v.pose[5], -v.pose[3]);
        phaseTick = o.t;
        period = v.period;
      }
      if (proved || !(isFlower ? v.kind === 'bell' && [2, 3].includes(v.k) : v.id === 'disk')) continue;
      const bound = isFlower
        ? v.bottom
        : v.at[1] -
          (v.pose[3] * (5.05 - v.at[0]) + v.pose[5] * (4.97 - v.at[2]) + v.axialHeight + 0.18) / v.pose[4] -
          1.2 * Math.tan(0.175);
      let arr = seen[v.id] || (seen[v.id] = []);
      let u = arr.find(
        (w) =>
          w.t < v.t &&
          v.t - w.t <= 650 &&
          (isFlower
            ? Math.abs(w.bottom - v.bottom) > 0.05
            : Math.abs(w.pose[1] - v.pose[1]) +
                Math.abs(w.pose[4] - v.pose[4]) +
                Math.abs(w.pose[7] - v.pose[7]) >
              0.015),
      );
      arr.push(v);
      while (arr.length && arr[0].t < v.t - 640) arr.shift();
      if (u && bound > (isFlower ? 1.88 : 1.9)) {
        proved = true;
        return proof(u, v, isFlower);
      }
    }
  }
  if (!proved) {
    if (isFlower && o.t > 420) {
      let targetZ = Math.floor(o.t / 400) % 2 ? 7.43 : 6.55;
      if (Math.abs(o.feet[1] - targetZ) > 0.045) return o.feet[1] < targetZ ? 3 : 1;
    }
    return 0;
  }
  if (!started) {
    if (!isFlower) {
      let phase =
        (((phaseAt + (2 * Math.PI * (o.t - phaseTick)) / period) % (2 * Math.PI)) + 2 * Math.PI) %
        (2 * Math.PI);
      if (phase < 4.45 || phase > 4.52) return 0;
    }
    started = true;
    // A single companion instruction names one position; both bodies still traverse every centimetre.
    const go = (x, z) => [target(x, z), 1],
      hold = (n) => [0, n],
      walk = (x, z) => [x, z, 'feet'];
    script = isFlower
      ? [
          go(0.0, 3.5),
          walk(plateX, 6.55),
          walk(plateX, 4.75),
          [15, 410],
          go(4.2, 3.98),
          hold(65),
          go(4.2, -4.9),
          walk(-4.2, 4.75),
          walk(-4.2, -4.9),
          go(0.5, -5.6),
          walk(-0.45, -5.6),
          hold(20),
          go(0.53, -8.48),
          walk(-0.45, -8.48),
          hold(65),
        ]
      : [
          go(5.05, 5.68),
          hold(40),
          go(5.52, 5.61),
          [18, 13],
          go(6.04, 5.61),
          [18, 13],
          go(6.56, 5.61),
          [18, 13],
          go(7.02, 5.61),
          [18, 13],
          go(6.05, 5.75),
          hold(25),
          go(6.05, 3.45),
          walk(6.04, 8.1),
          walk(6.04, 6.38),
          hold(4),
          go(8.42, 3.4),
          walk(6.04, 3.13),
          walk(7.68, 3.13),
          hold(28),
        ];
  }
  while (index < script.length) {
    let [a, b, mode] = script[index];
    if (mode === 'feet') {
      let [x, z] = o.feet;
      if (Math.abs(a - x) > 0.045) return a > x ? 2 : 4;
      if (Math.abs(b - z) > 0.045) return b > z ? 3 : 1;
      index++;
      continue;
    }
    if (++remain >= b) {
      remain = 0;
      index++;
    }
    return a;
  }
  return 0;
}
