// Submission. No imports, clocks, seed, judge helpers or world reference.
let level, racks, scheduled, queue, deadline, first, gauge;
function test(a, f) {
  switch (a[0]) {
    case 'all':
      return a.slice(1).every((v) => test(v, f));
    case 'any':
      return a.slice(1).some((v) => test(v, f));
    case 'eq':
      return f[a[1]] === a[2];
    case 'ge':
      return f[a[1]] >= a[2];
    case 'le':
      return f[a[1]] <= a[2];
    case 'bit':
      return !!(f[a[1]] & (1 << a[2]));
  }
}
function decide(o) {
  if (o.stage !== level) {
    level = o.stage;
    racks = {};
    scheduled = -1;
    queue = [];
    first = Math.ceil(o.t / 20) * 20;
    gauge = null;
  }
  if (o.ride) return 0;
  if (o.rays) {
    for (const p of o.rays) {
      if (p?.kind === 'governor') gauge = p;
      if (p?.kind !== 'carriage') continue;
      racks[p.id] = { ...p, proof: (racks[p.id]?.proof || 0) | (p.stroke === 'extended' ? 1 : 2) };
    }
  }
  if (queue.length) return queue.shift();
  if (o.t === scheduled) {
    scheduled = -1;
    return 4;
  }
  if (scheduled > o.t) return 0;
  if (o.rays) {
    const next = o.t + 20,
      pads = Object.values(racks),
      n = o.manuals.length;
    function visit(list, used, torque) {
      const i = list.length;
      if (i === n) {
        if (n === 1) return list;
        if (!gauge) return null;
        const k = (next / 20 + gauge.offset) % gauge.period,
          bias = k ? ((k % 3) - 1) * gauge.travel : 0;
        const contact = used.reduce((a, id) => a ^ (1 << id), 0);
        return test(gauge.limit, {
          peak: 1,
          torque: torque + bias,
          clearance: Math.floor(gauge.period / 2) - k,
          contact,
        })
          ? list
          : null;
      }
      for (const p of pads) {
        if (used.includes(p.bank)) continue;
        const f = { ...p, hold: Math.max(0, p.width - ((next / 20 + p.offset) % p.period)) * 20 };
        if (!test(o.manuals[i], f) && !(i > 0 && p.proof === 3 && p.sockets & (1 << i) && f.hold >= 40))
          continue;
        const found = visit([...list, p], [...used, p.bank], torque + (i + 1) * p.arm);
        if (found) return found;
      }
      return null;
    }
    const plan = visit([], [], 0);
    if (plan) {
      plan.forEach((p, i) => {
        if (i > 0 && p.proof === 3) queue.push(200 + i * 10 + p.id);
        queue.push(100 + i * 10 + p.id);
      });
      scheduled = next;
      return queue.shift();
    }
  }
  // Cover the whole circle even when lamps and sampled turns are phase locked.
  const elapsed = o.t - first;
  if (
    elapsed >= 0 &&
    (elapsed % 780 === 259 ||
      elapsed % 780 === 260 ||
      elapsed % 780 === 519 ||
      elapsed % 780 === 520 ||
      elapsed % 780 === 779 ||
      elapsed % 780 === 0)
  )
    return 1;
  return 0;
}
