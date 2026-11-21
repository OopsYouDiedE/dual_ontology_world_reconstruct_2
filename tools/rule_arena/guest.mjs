import { getQuickJS } from 'quickjs-emscripten';
import { performance } from 'node:perf_hooks';
export class Guest {
  static async create(src) {
    const Q = await getQuickJS(),
      g = new Guest();
    g.vm = Q.newContext();
    g.vm.runtime.setMemoryLimit(16 * 1024 * 1024);
    g.vm.runtime.setMaxStackSize(256 * 1024);
    g.vm.runtime.setInterruptHandler(() => performance.now() >= g.until && (g.interrupted = true));
    g.until = performance.now() + 100;
    try {
      const h = g.vm.unwrapResult(
        g.vm.evalCode('globalThis.Date=undefined;Math.random=undefined;\n' + src + '\n;decide'),
      );
      g.fn = h;
      return g;
    } catch (e) {
      g.close();
      throw e;
    }
  }
  call(obs, ms) {
    this.interrupted = false;
    const v = this.vm;
    const arg = v.newString(obs);
    this.until = performance.now() + ms;
    // Pass only guest-owned data. Never convert a guest object/exception into a host object.
    const out = v.callFunction(this.parseCall, v.undefined, this.fn, arg);
    arg.dispose();
    if (out.error) {
      out.error.dispose();
      return 0;
    }
    const h = out.value,
      num = v.typeof(h) === 'number' ? v.getNumber(h) : 0;
    h.dispose();
    return num;
  }
  init() {
    this.until = performance.now() + 100;
    this.parseCall = this.vm.unwrapResult(
      this.vm.evalCode('(function(parse){return (f,s)=>f(parse(s))})(JSON.parse)'),
    );
  }
  close() {
    this.parseCall?.dispose();
    this.fn?.dispose();
    this.vm.dispose();
  }
}
