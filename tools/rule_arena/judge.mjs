import { Worker } from 'node:worker_threads';
import { performance } from 'node:perf_hooks';
import { once } from 'node:events';
export class Judge {
  constructor(src, maxAction = 399) {
    if (Buffer.byteLength(src) > 131072) throw Error('source exceeds 128 KiB');
    this.src = src;
    this.maxAction = maxAction;
    this.violations = 0;
    this.denied = 0;
    this.peak = 0;
  }
  async start() {
    const control = new SharedArrayBuffer(16),
      data = new SharedArrayBuffer(131072);
    this.c = new Int32Array(control);
    this.data = Buffer.from(data);
    this.w = new Worker(new URL('./worker.mjs', import.meta.url), {
      workerData: { src: this.src, maxAction: this.maxAction, control, data },
    });
    const timeout = AbortSignal.timeout(5000);
    try {
      await once(this.w, 'message', { signal: timeout });
    } catch (err) {
      await this.close();
      throw err;
    }
  }
  async close() {
    if (this.w) {
      const w = this.w;
      this.w = null;
      await w.terminate();
    }
  }
  async decide(obs) {
    if (obs.t % 20 === 0) {
      this.left = 100;
      if (!this.w) await this.start();
    }
    if (this.left <= 0) {
      this.denied++;
      return 0;
    }
    const cap = Math.min(20, this.left),
      c = this.c,
      body = JSON.stringify(obs),
      len = Buffer.byteLength(body);
    if (len > this.data.length) throw Error('judge packet too large');
    this.data.write(body);
    c[1] = len;
    c[2] = Math.ceil(cap * 1000);
    const start = performance.now();
    Atomics.store(c, 0, 1);
    Atomics.notify(c, 0);
    while (Atomics.load(c, 0) !== 2) {
      let left = cap - (performance.now() - start);
      if (left <= 0) break;
      Atomics.wait(c, 0, 1, left);
    }
    const elapsed = performance.now() - start;
    this.peak = Math.max(this.peak, elapsed);
    this.left -= elapsed;
    if (elapsed > cap || Atomics.load(c, 0) !== 2 || c[3] === -1) {
      this.left = 0;
      this.violations++;
      await this.close();
      return 0;
    }
    return c[3];
  }
}
