import { workerData as d, parentPort } from 'node:worker_threads';
import { Guest } from './guest.mjs';
const ctrl = new Int32Array(d.control),
  bytes = new Uint8Array(d.data),
  decoder = new TextDecoder();
const g = await Guest.create(d.src);
g.init();
parentPort.postMessage('ready');
for (;;) {
  while (Atomics.load(ctrl, 0) === 0) Atomics.wait(ctrl, 0, 0);
  const state = Atomics.load(ctrl, 0);
  if (state === 3) break;
  if (state === 2) {
    Atomics.wait(ctrl, 0, 2);
    continue;
  }
  const val = g.call(decoder.decode(bytes.subarray(0, ctrl[1])), ctrl[2] / 1000);
  ctrl[3] = g.interrupted ? -1 : Number.isInteger(val) && val >= 0 && val <= d.maxAction ? val : 0;
  Atomics.store(ctrl, 0, 2);
  Atomics.notify(ctrl, 0);
}
g.close();
