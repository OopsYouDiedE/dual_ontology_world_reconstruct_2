// Exercise file:// scene updates with an already open report DOM.
const fs = require('fs'), vm = require('vm'), assert = require('assert');
class Element {
  constructor(tag) { this.tag=tag; this.children=[]; this.dataset={}; this.textContent=''; this.className=''; }
  append(...items) { for (const item of items) { item.parent=this; this.children.push(item); } }
  remove() { if (this.parent) this.parent.children=this.parent.children.filter(x => x!==this); }
  insertBefore(item) { item.parent=this; this.children.unshift(item); }
  replaceChildren(...items) { this.children=[]; this.append(...items); }
}
const main = new Element('main'), body = new Element('body'); body.dataset.projectBase='../../';
let script, refresh;
body.append = item => { if (item.tag === 'script') script=item; else Element.prototype.append.call(body,item); };
const document = {body, createElement: tag => new Element(tag), querySelector: selector => selector === 'main' ? main : main.children.find(x => x.className.includes('scene-survey'))};
const window = {};
vm.runInNewContext(fs.readFileSync('tools/testing/scene-live.js','utf8'), {document, window, setInterval: fn => {refresh=fn;}, Date, Array, encodeURIComponent});
assert.ok(script.src.startsWith('scene-survey.js?t='));
window.SCENE_SURVEY={id:'run',revision:'123456789012',state:'running',status_path:'artifacts/run/status.json',rows:[{id:'a',room:'R1',phase:'inspect',state:'running',reason:'',images:[]}]};
script.onload();
assert.strictEqual(main.children.length,1);
const rows = () => main.children[0].children[2].children[0].children[1].children;
assert.strictEqual(rows()[0].children[3].textContent,'进行中');
refresh();
window.SCENE_SURVEY={...window.SCENE_SURVEY,state:'blocked',rows:[{id:'a',room:'R1',phase:'inspect',state:'blocked',reason:'gesture <wait>',scores:{fluidity:6,text_density:null},reasons:{fluidity:'spike > 33.3ms',text_density:'missing <proof>'},evidence:'artifacts/run/a/report.json',images:['artifacts/run/a/img.png']}]};
script.onload();
assert.strictEqual(main.children.length,1);
assert.strictEqual(rows()[0].children[3].textContent,'受阻');
assert.strictEqual(rows()[0].children[4].textContent,'gesture <wait>');
assert.strictEqual(rows()[0].children[5].children[0].textContent,'6/10');
assert.strictEqual(rows()[0].children[5].children[1].textContent,'spike > 33.3ms');
assert.strictEqual(rows()[0].children[6].children[0].textContent,'未测');
assert.strictEqual(rows()[0].children[6].children[1].textContent,'missing <proof>');
assert.strictEqual(rows()[0].children[12].children[0].href,'../../artifacts/run/a/report.json');
console.log('PASS: file:// scene status refresh, stall details, safe DOM, no duplicate table');
