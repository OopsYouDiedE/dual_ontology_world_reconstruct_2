const fs = require('fs'), vm = require('vm'), assert = require('assert');
class Element {
  constructor(tag) { this.tag=tag; this.children=[]; this.dataset={}; this.textContent=''; this.className=''; this.open=false; }
  append(...items) { for (const item of items) { item.parent=this; this.children.push(item); } }
  remove() { if (this.parent) this.parent.children=this.parent.children.filter(x => x!==this); }
  replaceChildren(...items) { this.children=[]; this.append(...items); }
  querySelector(selector) { return this.children.find(x => selector === '[data-scene-evidence]' ? 'sceneEvidence' in x.dataset : selector.startsWith('.') ? x.className.split(' ').includes(selector.slice(1)) : x.tag===selector); }
}
const main = new Element('main'), body = new Element('body'); body.dataset.projectBase='../../';
const legacy=new Element('section');legacy.className='scene-survey';main.append(legacy);
const wake=new Element('article'),shaft=new Element('article');wake.dataset.testCard='wake';shaft.dataset.testCard='shaft';main.append(wake,shaft);
let script, refresh;
body.append = item => { if (item.tag === 'script') script=item; else Element.prototype.append.call(body,item); };
const document = {body, createElement: tag => new Element(tag), querySelector: selector => selector === 'main > .scene-survey' ? main.children.find(x=>x.className==='scene-survey') : null, querySelectorAll: selector => selector==='[data-test-card]'?[wake,shaft]:[]};
const window = {};
vm.runInNewContext(fs.readFileSync('tools/testing/scene-live.js','utf8'), {document, window, setInterval: fn => {refresh=fn;}, Date, Array, encodeURIComponent});
window.SCENE_SURVEY={id:'run',revision:'123456789012',state:'running',status_path:'artifacts/run/status.json',rows:[{id:'a',segment_id:'wake',room:'R1',phase:'inspect',state:'running',reason:'',images:[]},{id:'b',segment_id:'shaft',room:'R2',phase:'inspect',state:'failed',reason:'stall',images:[]}]};
script.onload();
assert.strictEqual(main.children.includes(legacy),false,'legacy standalone table is removed');
const details = wake.children[0].children[0]; details.open=true;
const rows = () => details.children[2].children[0].children[1].children;
assert.strictEqual(rows().length,1); assert.strictEqual(rows()[0].dataset.surveyCase,'a');
assert.strictEqual(shaft.children[0].children[0].children[2].children[0].children[1].children[0].dataset.surveyCase,'b');
const scroll = details.children[2]; scroll.scrollLeft=123; scroll.scrollTop=45;
refresh(); script.onload(); assert.strictEqual(details.children[2], scroll);
refresh(); window.SCENE_SURVEY={...window.SCENE_SURVEY,state:'blocked',rows:[{id:'a',segment_id:'wake',room:'R1',phase:'inspect',state:'blocked',reason:'gesture <wait>',evidence:'artifacts/run/a/report.json',images:[]}]}; script.onload();
assert.strictEqual(details.open,true); assert.strictEqual(details.children[2].scrollLeft,123); assert.strictEqual(details.children[2].scrollTop,45);
assert.strictEqual(rows()[0].children[4].textContent,'gesture <wait>');
assert.strictEqual(rows()[0].children[5].children[0].href,'../../artifacts/run/a/report.json');
assert.strictEqual(shaft.children.length,0,'stale segment evidence is removed');
console.log('PASS: scene details grouped by segment; updates preserve state and remove legacy table');
