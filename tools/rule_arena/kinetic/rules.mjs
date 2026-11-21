export const SHEETS = {
  3: [
    [
      ['bell.clear', 'Keep half an arm beyond neighboring low bells.', ['gt', 'bellGuard', 0.18]],
      ['hands', 'Hold the green plate; leave the yellow latch to gloved hands.', ['not', 'work']],
      ['one.body', 'Leave half a step between you.', ['gt', 'separation', 0.57]],
    ],
    [
      ['bell.wide', 'Give a pair of low bells an extra half-step.', ['gt', 'bellGuard', 0.28]],
      [
        'seal',
        'Keep your hands off a latch beneath the corolla.',
        ['or', ['not', 'work'], ['not', 'marked']],
      ],
      ['crowd', 'Make room for a shoulder before obeying an order.', ['gt', 'separation', 0.6]],
    ],
  ],
  6: [
    [
      ['head', 'Under the rotor, leave a palm above your cap.', ['gt', 'headroom', 1.93]],
      ['hands', 'Only gloved hands may push the blue trolley.', ['not', 'work']],
      ['rail', 'Stay clear of your companion’s footprints.', ['gt', 'separation', 0.57]],
    ],
    [
      ['rim', 'Under the rim, keep two fingers above your cap.', ['gt', 'headroom', 1.83]],
      [
        'seal',
        'Push a trolley inside the rim only with your captain watching from beyond the gate.',
        ['or', ['not', 'work'], ['not', 'marked'], 'lookout'],
      ],
      ['space', 'Leave your companion a shoulder of room at the gate.', ['gt', 'separation', 0.6]],
    ],
  ],
};
// Last clause describes a sufficient, phase-independent refuge, shared by both roles.
for (const stage of [3, 6])
  for (const sheet of SHEETS[stage])
    sheet.push([
      'alone.refuge',
      stage === 3
        ? 'Alone, stay beyond nine metres from the flower.'
        : 'Alone, stay in the corners, beyond 9.8 metres from the tip.',
      ['or', ['not', 'alone'], ['gt', 'radius', stage === 3 ? 9 : 9.8]],
    ]);
export function evalAST(e, f) {
  if (typeof e === 'string') return f[e];
  if (typeof e === 'number') return e;
  let [op, ...v] = e;
  switch (op) {
    case 'not':
      return !evalAST(v[0], f);
    case 'or':
      return v.some((a) => evalAST(a, f));
    case 'and':
      return v.every((a) => evalAST(a, f));
    case 'gt':
      return evalAST(v[0], f) > v[1];
    case 'eq':
      return evalAST(v[0], f) === v[1];
    default:
      throw Error(op);
  }
}
export const replacement = (node, site, threshold) => [
  'or',
  structuredClone(node),
  ['and', ['eq', 'site', site], ['gt', 'workClearance', threshold]],
];
export const PROOF_BASE = 100000,
  WINDOW = 1024;
// A proof names a rule, two readings, an inference law and a claimed clearance band.
export const STRIDE = 4194304,
  CLAIMS = [1.88, 1.9, 1.96, 2.08];
export const encode = (node, a, b, law, band) =>
  PROOF_BASE + (law + 2 * band) * STRIDE + node * WINDOW * WINDOW + a * WINDOW + b;
export const decode = (n) => {
  let raw = n - PROOF_BASE,
    tag = Math.floor(raw / STRIDE),
    k = raw % STRIDE;
  return [
    Math.floor(k / WINDOW ** 2),
    Math.floor(k / WINDOW) % WINDOW,
    k % WINDOW,
    tag % 2,
    Math.floor(tag / 2),
  ];
};
