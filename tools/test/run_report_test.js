// Exercise the actual file:// refresh script with an observable DOM adapter.
const fs = require('fs'), vm = require('vm'), assert = require('assert');
class Element {
  constructor(tag, text = '') { this.tag = tag; this.textContent = text; this.children = []; this.dataset = {}; }
  append(...nodes) { for (const node of nodes) { node.parent = this; this.children.push(node); } }
  remove() { if (this.parent) this.parent.children = this.parent.children.filter(node => node !== this); }
  replaceWith(node) { node.parent = this.parent; this.parent.children[this.parent.children.indexOf(this)] = node; }
  querySelector(selector) {
    if (selector === '[data-result-body]') return this.children.find(node => 'resultBody' in node.dataset);
    if (selector === ':scope > p') return this.children.find(node => node.tag === 'p');
    if (selector === '[data-test-id]') return this.idCell;
    return null;
  }
  querySelectorAll() { return this.cells || []; }
}
const categories = ['fluidity','text_density','action_sfx_integrity','audio_loudness','blind_narrative_match','aesthetic_similarity','narrative_flow'];
const card = new Element('article'); card.dataset = {testCard:'wake',testAt:'',testId:''};
const initial = new Element('div'); initial.dataset.resultBody = ''; card.append(new Element('p','尚未测试'), initial);
const row = new Element('tr'); row.dataset.testSegment = 'wake'; row.idCell = new Element('td');
row.cells = categories.map(category => { const el = new Element('td'); el.dataset.batchScore = category; return el; });
let pendingScript, refresh;
const body = new Element('body'); body.dataset.projectBase = '../../';
body.append = script => { pendingScript = script; };
const document = {body, createElement: tag => new Element(tag), getElementById: () => null,
  querySelectorAll: selector => selector === '[data-test-card]' ? [card] : selector === '[data-test-segment]' ? [row] : []};
const window = {MAINLINE_PROGRESS: {events: []}};
vm.runInNewContext(fs.readFileSync('tools/testing/run-report.js', 'utf8'), {document, window, setInterval: fn => {refresh = fn;}, Date, Map, Object, Number, encodeURIComponent});
function publish(id, at, values, evidence = ['artifacts/evidence.json']) {
  window.MAINLINE_PROGRESS.events.push({event_id:id, segment_id:'wake', at, revision:'abcdef123456', evidence,
    test_result:{test_id:id,scores:Object.fromEntries(categories.map((key,i)=>[key,values[i]])),reasons:Object.fromEntries(categories.map(key=>[key,'Observation <script>']))}});
  pendingScript.onload();
}
publish('first','2026-11-17T01:00:00Z',[8,9,8,9,8,9,8]);
assert.strictEqual(row.idCell.textContent,'first');
assert.strictEqual(card.querySelector('[data-result-body]').children[2].children.length,7);
assert.strictEqual(card.querySelector('[data-result-body]').children[3].tag,'details');
refresh(); publish('second','2026-11-17T02:00:00Z',[6,null,8,9,8,9,8]);
assert.strictEqual(row.cells[1].textContent,'评分缺项');
assert.strictEqual(row.cells[0].textContent,'6/10');
assert.strictEqual(card.querySelector('[data-result-body]').children[1].textContent,'不合格');
refresh(); publish('stale','2026-11-17T00:00:00Z',[10,10,10,10,10,10,10]);
assert.strictEqual(row.idCell.textContent,'second');
refresh(); publish('third','2026-11-17T02:00:00Z',[8,8,8,8,8,8,8],[]);
assert.strictEqual(row.idCell.textContent,'third');
assert.strictEqual(card.querySelector('[data-result-body]').children[1].textContent,'已测 · 评分不全');
console.log('PASS: seven-field refresh, missing score, stale batch, same-second batch, evidence retention');
