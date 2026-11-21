import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes, createHash } from 'node:crypto';
import { performance } from 'node:perf_hooks';
import { setTimeout as sleep } from 'node:timers/promises';
import { spawnSync } from 'node:child_process';
const here = path.dirname(fileURLToPath(import.meta.url)),
  [op, folder, requestedProfile] = process.argv.slice(2);
if (!folder) throw Error('match.mjs prepare|clock|score SESSION_DIR');
const dir = path.resolve(folder),
  pub = path.join(dir, 'author'),
  priv = path.join(dir, 'referee');
const hash = (x) => createHash('sha256').update(x).digest('hex');
const save = (f, x) => fs.writeFileSync(f, JSON.stringify(x, null, 2) + '\n', { flag: 'wx' });
const secret = path.join(priv, 'draw.json'),
  frozen = path.join(priv, 'submission.js'),
  stamp = path.join(priv, 'freeze.json');
const common = ['guest.mjs', 'worker.mjs', 'judge.mjs', 'package-lock.json', 'match.mjs'];
const pilotFiles = [
  'arena.mjs',
  'game.mjs',
  'studio.mjs',
  'mesh.mjs',
  'source-top.mjs',
  'spinning-top.glb',
  'Grab3D-LICENSE.txt',
  'rules.mjs',
  'reference.js',
  'starter.js',
  'PROTOCOL.md',
];
const manifest = (profile) =>
  Object.fromEntries(
    (profile === 'kinetic'
      ? [...common, ...pilotFiles.map((f) => 'kinetic/' + f)]
      : [
          'architecture.mjs',
          'blockouts.json',
          'physics.mjs',
          'game.mjs',
          'guest.mjs',
          'worker.mjs',
          'judge.mjs',
          'arena.mjs',
          'package-lock.json',
          'reference.js',
          'PROTOCOL.md',
          'starter.js',
          'match.mjs',
        ]
    ).map((f) => [f, hash(fs.readFileSync(path.join(here, f)))]),
  );
if (op === 'prepare') {
  const profile = requestedProfile ?? 'legacy';
  if (!['legacy', 'kinetic'].includes(profile)) throw Error('unknown profile');
  fs.mkdirSync(dir);
  fs.mkdirSync(pub);
  fs.mkdirSync(priv);
  const seeds = new Set();
  while (seeds.size < 32) seeds.add(randomBytes(4).readUInt32LE());
  save(secret, {
    salt: randomBytes(24).toString('hex'),
    seeds: [...seeds],
    profile,
    engine: manifest(profile),
    node: process.version,
  });
  for (const k of profile === 'kinetic'
    ? [
        'PROTOCOL.md',
        'studio.mjs',
        'mesh.mjs',
        'source-top.mjs',
        'spinning-top.glb',
        'Grab3D-LICENSE.txt',
        'rules.mjs',
        'starter.js',
      ]
    : ['PROTOCOL.md', 'physics.mjs', 'starter.js'])
    fs.copyFileSync(path.join(here, profile === 'kinetic' ? 'kinetic' : '.', k), path.join(pub, k));
  save(path.join(pub, 'commitment.json'), {
    sha256: hash(fs.readFileSync(secret)),
    seeds: 32,
    authorMinutes: 40,
  });
  console.log('Give the author ONLY the author directory in an isolated workspace. Start clock when ready.');
} else if (op === 'clock') {
  const start = performance.now();
  save(path.join(priv, 'started.json'), { utc: new Date().toISOString(), minutes: 40 });
  console.log(
    '40-minute author clock started. Write author/submission.js using atomic saves. Referee freezes at deadline.',
  );
  let accepted = null;
  const candidate = path.join(pub, 'submission.js');
  while (performance.now() - start < 2400000) {
    try {
      if (fs.statSync(candidate).size <= 131072) {
        const b = fs.readFileSync(candidate);
        if (b.length && b.length <= 131072 && performance.now() - start < 2400000) accepted = b;
      }
    } catch (e) {
      if (e.code !== 'ENOENT') throw e;
    }
    await sleep(100);
  }
  if (!accepted) throw Error('No submission received within 40 minutes');
  fs.writeFileSync(frozen, accepted, { flag: 'wx' });
  save(stamp, { utc: new Date().toISOString(), sha256: hash(accepted) });
  console.log('Submission frozen. Run score as referee.');
} else if (op === 'score') {
  const token = JSON.parse(fs.readFileSync(path.join(pub, 'commitment.json'))),
    draw = JSON.parse(fs.readFileSync(secret));
  if (
    hash(fs.readFileSync(secret)) !== token.sha256 ||
    JSON.stringify(manifest(draw.profile)) !== JSON.stringify(draw.engine) ||
    process.version !== draw.node
  )
    throw Error('draw, engine or runtime changed');
  if (hash(fs.readFileSync(frozen)) !== JSON.parse(fs.readFileSync(stamp)).sha256)
    throw Error('submission changed after deadline');
  const pilot = draw.profile === 'kinetic',
    runner = pilot ? path.join(here, 'kinetic') : here;
  const rows = [];
  for (const seed of draw.seeds)
    for (const who of ['reference', 'submission']) {
      const file = path.join(priv, `${who}-${seed}.json`),
        proc = spawnSync(
          process.execPath,
          [
            path.join(runner, 'arena.mjs'),
            'run',
            ...(pilot ? ['--stage', draw.seeds.indexOf(seed) % 2 ? '6' : '3'] : []),
            '--seed',
            String(seed),
            '--bot',
            who === 'reference' ? path.join(runner, 'reference.js') : frozen,
            '--out',
            file,
          ],
          { encoding: 'utf8' },
        );
      if (proc.status !== 0)
        throw Error(`infrastructure / invalid submission: ${String(proc.stderr).slice(-1200)}`);
      rows.push({ who, ...JSON.parse(proc.stdout) });
    }
  const wins = (who) => rows.filter((r) => r.who === who && r.result === (pilot ? 'exit' : 'camp')).length;
  save(path.join(priv, 'score.json'), {
    referenceWins: wins('reference'),
    submissionWins: wins('submission'),
    drawSize: draw.seeds.length,
    rows,
  });
  console.log(
    `Reference ${wins('reference')}/32; submission ${wins('submission')}/32. Audit failure causes and watchdog counts before making a difficulty claim.`,
  );
} else throw Error('expected prepare, clock or score');
