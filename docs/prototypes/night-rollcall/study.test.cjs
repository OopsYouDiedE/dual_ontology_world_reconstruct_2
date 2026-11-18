const t = require('node:test');
const assert = require('node:assert/strict');
const { blank, advance } = require('./study.js');
const run = (state, ...actions) => actions.reduce(advance, state);
const bell = () => run(blank(), 'notice', 'wait');

t('the routine introduces the notice before the second bell', () => {
  const start = blank();
  assert.equal(run(start, 'wait', 'attest', 'copy', 'tube'), start);
  assert.equal(bell().phase, 'echo');
});

t('corroboration works in any order and repeats do not inflate the record', () => {
  const start = bell();
  for (const order of [['witness', 'tube', 'chalk'], ['chalk', 'witness', 'tube'], ['tube', 'chalk', 'witness']]) {
    const partial = run(start, order[0], order[0], 'attest');
    assert.equal(partial.phase, 'echo');
    assert.equal(partial.findings.length, 1);
    const ready = run(partial, 'notice', order[1], 'attest', order[2]);
    assert.equal(ready.phase, 'echo');
    assert.equal(advance(ready, 'attest').phase, 'held');
  }
  assert.deepEqual(start.findings, []);
});

t('copying and deferring produce distinct reports, and restart clears the shift', () => {
  for (const [action, phase] of [['copy', 'registered'], ['defer', 'pending']]) {
    const final = run(bell(), 'tube', action);
    assert.equal(final.phase, phase);
    assert.equal(run(final, 'witness', 'wait', 'attest'), final);
    assert.deepEqual(advance(final, 'reset'), blank());
  }
});
