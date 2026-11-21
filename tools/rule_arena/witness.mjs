// Organizer-only constructive verifier. Even its witness must earn optical receipts.
import { Game } from './game.mjs';
export function verify(seed) {
  const g = new Game(seed);
  let steps = 0;
  function act(c = 0) {
    g.observe();
    g.step(c);
    steps++;
    if (g.result === 'lost' || g.result === 'timeout') throw Error(`witness rejected at ${g.i}:${g.t}`);
  }
  while (g.result === 'running') {
    for (let sector = 0; sector < 3; sector++) {
      for (let k = 0; k < 260; k++) act();
      if (sector < 2) {
        act(1);
        act(1);
      }
    }
    const { ids, beat } = g.room.witness;
    ids.forEach((id, i) => {
      if (i) act(200 + i * 10 + id);
      act(100 + i * 10 + id);
    });
    while (g.t % 2400 !== beat * 20) act();
    act(4);
    if (!g.tracks) throw Error('missing witnessed departure');
    while (g.tracks && g.result === 'running') act();
  }
  if (steps > g.bound) throw Error('exceeded constructive bound');
  return steps;
}
