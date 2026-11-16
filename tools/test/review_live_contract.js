/* Test append-only page updates without opening or controlling a browser. */
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
class Element {
  constructor(tag) { this.tag = tag; this.children = []; this.dataset = {}; this.textContent = ''; }
  append(...nodes) { this.children.push(...nodes); }
  remove() {}
}
const list = new Element('ol'), empty = new Element('p'), body = new Element('body');
body.dataset.projectBase = '../../';
const document = {
  body,
  getElementById(id) { return {'progress-events': list, 'progress-empty': empty}[id] || null; },
  querySelectorAll() { return []; },
  createElement(tag) { return new Element(tag); }
};
const first = {event_id:'one',kind:'change',at:'2026-11-16 12:00:00',summary:'<script>unsafe</script>',result:'changed',work_id:'same-work',segment_id:'wake',revision:'12345678',evidence:['artifacts/带 空格.png']};
const context = {document, window:{MAINLINE_PROGRESS:{events:[first]}}, setInterval(fn) { this.refresh = fn; }, Date, encodeURIComponent};
vm.createContext(context);
vm.runInContext(fs.readFileSync(path.resolve(__dirname, '../testing/review.js'), 'utf8'), context);
assert.equal(list.children.length, 1);
assert.equal(list.children[0].children[0].textContent, first.at + ' · 修改 · ' + first.summary);
assert.equal(list.children[0].children[2].children[0].href, '../../artifacts/%E5%B8%A6%20%E7%A9%BA%E6%A0%BC.png');
const original = list.children[0];
const script = body.children.at(-1);
script.onload();
assert.equal(list.children.length, 1, 'same event must not duplicate');
context.window.MAINLINE_PROGRESS.events.push({...first,event_id:'two',kind:'check',summary:'checked'});
script.onload();
assert.equal(list.children.length, 2);
context.window.MAINLINE_PROGRESS.events.push({...first,event_id:'three',kind:'complete',summary:'done',related_event_ids:['one','two']});
script.onload();
assert.equal(list.children.length, 3);
assert.equal(list.children[0], original, 'original event node must be retained');
assert.equal(list.children[2].className, 'complete');
assert.equal(list.children[2].children.at(-1).textContent, '确认事件：one、two');
assert.equal(empty.hidden, true);
console.log(JSON.stringify({passed:true,checks:8,scope:'append-only live progress, escaping, evidence URL, completion association'}));
