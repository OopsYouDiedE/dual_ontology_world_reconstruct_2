"""Static template for the self-contained route replay."""

PAGE = r'''<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<title>远征 · 路线审计</title>
<style>
:root{color-scheme:dark;background:#111923;color:#e5edf8;font:15px system-ui,sans-serif}*{box-sizing:border-box}[hidden]{display:none!important}body{margin:0 auto;padding:20px;max-width:1650px}h1,h2,p{margin:0 0 10px}h1{font-size:1.65rem}h2{font-size:1.13rem}small,.muted{color:#aabdd2}button,select,input{font:inherit}button,select{background:#223448;color:inherit;border:1px solid #607790;border-radius:5px;padding:5px 8px}button{cursor:pointer}button:hover,button[aria-current=true]{background:#38536f}button:focus-visible,select:focus-visible,input:focus-visible{outline:2px solid #fff}fieldset,section,details{border:1px solid #34465a;border-radius:8px;margin:10px 0;padding:12px;min-width:0}summary{cursor:pointer}.controls{display:flex;align-items:center;flex-wrap:wrap;gap:8px 14px}.controls input[type=range]{flex:1;min-width:120px}.workspace{display:grid;grid-template-columns:minmax(0,1.75fr) minmax(0,1fr);gap:12px}svg{width:100%;height:clamp(320px,61vh,800px);display:block;background:#101721;border:1px solid #34465a;border-radius:5px;touch-action:none}#timeline{max-height:clamp(330px,59vh,790px);overflow:auto;overflow-anchor:none}.event{width:100%;text-align:left;display:block;margin:4px 0;padding:7px 9px;overflow-wrap:anywhere}.event.future{border-style:dashed}.event span{display:block}.event .value{white-space:pre-wrap}.event .tag{font-size:.81rem;color:#b7cadf}.event[data-phase=Confirmed] .tag{color:#81e4bc}.event[data-phase=Intent] .tag{color:#ffd78e}.event[data-phase=Dialogue] .tag{color:#f3b4ee}.marker{cursor:pointer}.marker:focus{outline:none}.marker:focus circle,.marker:hover circle{stroke:#fff;stroke-width:3}#stack button{margin:3px}#stack{max-height:140px;overflow:auto}table{border-collapse:collapse;width:100%;margin-top:8px}td,th{padding:5px 8px;text-align:left;border-bottom:1px solid #34465a;overflow-wrap:anywhere;vertical-align:top}th{color:#b7cadf}.table-wrap{overflow:auto}.route-key{white-space:nowrap}#selection{overflow-wrap:anywhere}output{font-variant-numeric:tabular-nums;min-width:12ch}@media(max-width:900px){.workspace{grid-template-columns:1fr}}
</style>
<body>
<header><h1>远征 · 路线审计</h1><p class="muted">共享 X/Z 俯视图（−Z 朝上）。亮线为已走路线，淡线为后续路线；Hale 使用虚线与菱形标记。</p></header>
<fieldset id="runs" class="controls"><legend>地图路线</legend></fieldset>
<fieldset id="categories" class="controls"><legend>地图事件类别</legend></fieldset>
<details><summary>比较运行参数与结果</summary><div class="table-wrap" id="parameters"></div></details>
<section class="controls" aria-label="回放控制"><button id="play" type="button">播放</button><label for="tick">回放帧</label><input type="range" id="tick" min="0" value="0" step="1"><output for="tick" id="time"></output><label for="floor">高度层</label><select id="floor"></select></section>
<main class="workspace">
<section><h2>碰撞地图与路线</h2><p id="geometry-note" class="muted"></p>
<div class="controls"><button id="zoom-in" type="button" aria-label="放大">+</button><button id="zoom-out" type="button" aria-label="缩小">−</button><button id="reset" type="button">适配地图</button><small>拖动地图平移。选择编号标记可查看该处事件。</small></div>
<svg id="map" viewBox="0 0 800 560" aria-label="X/Z 俯视地图"><g id="collision"></g><g id="paths"></g><g id="markers"></g><g id="actors" pointer-events="none"></g></svg>
<div id="stack" class="controls" aria-label="所选位置的事件" hidden></div><p id="selection" role="status" class="muted"></p></section>
<section><h2>完整事件日志</h2><p class="muted">按帧排序，保留所有路线和类别。意图是尝试，确认是已发生的结果。选择一条记录可跳转到对应位置与帧。</p><div id="timeline" aria-label="已记录事件" tabindex="0"></div></section>
</main>
<script type="application/json" id="route-data">__ROUTE_PAYLOAD__</script>
<script>
'use strict';
const $ = id => document.getElementById(id);
const {runs, geometry} = JSON.parse($('route-data').textContent);
const colors = ['#52d8ef','#ffc067','#aab2ff','#a8e987','#fd99be','#f69d89'];
const ink = i => colors[i % colors.length];
const svgNS = 'http://www.w3.org/2000/svg';
function svg(tag, attrs, parent) {
  const el = document.createElementNS(svgNS, tag);
  for (const [key,val] of Object.entries(attrs)) el.setAttribute(key,val);
  parent.append(el); return el;
}
function dom(tag, text, parent) {
  const el = document.createElement(tag); el.textContent = text; parent.append(el); return el;
}
const name = i => `${i+1} · ${runs[i].label}`;
const valueText = val => typeof val === 'string' ? val : JSON.stringify(val ?? null);
const hasCompleted = runs.some(r => r.metadata.outcome === 'completed');
const enabled = runs.map(r => !hasCompleted || r.metadata.outcome === 'completed');
const categoryOf = e => e.kind === 'decision' ? 'Decision' : e.phase;
const categories = {Confirmed:'已确认',Intent:'意图',Decision:'逐次决策',Dialogue:'对话',Observed:'观察'};
const sources = {'Audit feet':'审计坐标','Legacy value.feet':'旧版事件坐标','Path sample':'路径实测点',
  'Interpolated path (estimate)':'路径插值（估算）','No position recorded':'无坐标记录'};
const visibleCategories = new Set(['Confirmed','Intent']);
const runChecks = [];
const phaseText = e => categories[categoryOf(e)];
const sourceText = e => sources[e.source] ?? e.source;
const rows = runs.flatMap((r,i) => r.events.map(e => ({...e,run:i}))).sort((a,b) => a.tick-b.tick);
rows.forEach((e,i) => e.number = i+1);
const maxTick = runs.reduce((n,r) => Math.max(n,r.end),0);
const tick = $('tick'); tick.max = maxTick;
const map = $('map');
let selected = null, current = 0, floor = null, playing = null, drag = null;
let bounds = [Infinity,Infinity,-Infinity,-Infinity];
const levels = new Set();
const band = y => Math.floor((y+1)/2);
function extent(x,z) {
  bounds = [Math.min(bounds[0],x),Math.min(bounds[1],z),Math.max(bounds[2],x),Math.max(bounds[3],z)];
}
function include(x,y,z) { extent(x,z); levels.add(band(y)); }
for (const r of runs) for (const path of [r.path,r.hale]) for (const [,x,y,z] of path) include(x,y,z);
for (const e of rows) if (e.point) include(...e.point);
for (const [,lo,hi,polygon] of geometry ?? []) {
  for (const [x,z] of polygon) extent(x,z);
  levels.add(band(lo)); levels.add(band(hi));
}
if (!Number.isFinite(bounds[0])) bounds = [-1,-1,1,1];
const scale = Math.min(730/Math.max(bounds[2]-bounds[0],1),490/Math.max(bounds[3]-bounds[1],1));
const X = x => 400 + (x-(bounds[0]+bounds[2])/2)*scale;
const Z = z => 280 + (z-(bounds[1]+bounds[3])/2)*scale;
const fmt = n => Number(n.toFixed(2));
const inside = y => floor === null || band(y) === floor;
const [fx, fz, fw, fh] = [0,0,800,560];
let view = [fx,fz,fw,fh];
function updateView(){ map.setAttribute('viewBox',view.join(' ')); }
function zoom(factor){
  const [x,y,w,h]=view;
  if (w*factor < 20 || w*factor > 3200) return;
  view=[x+w*(1-factor)/2,y+h*(1-factor)/2,w*factor,h*factor]; updateView();
}
$('zoom-in').onclick=()=>zoom(.75);
$('zoom-out').onclick=()=>zoom(4/3);
$('reset').onclick=()=>{ view=[fx,fz,fw,fh]; updateView(); };
map.onpointerdown=e=>{
  if(e.button!==0 || e.target.closest('.marker')) return;
  const inverse = map.getScreenCTM().inverse();
  drag={x:e.clientX,y:e.clientY,view:[...view],sx:inverse.a,sy:inverse.d}; map.setPointerCapture(e.pointerId);
};
map.onpointermove=e=>{ if(drag){view=[drag.view[0]-(e.clientX-drag.x)*drag.sx,drag.view[1]-(e.clientY-drag.y)*drag.sy,...drag.view.slice(2)];updateView();} };
map.onpointerup=map.onpointercancel=map.onlostpointercapture=()=>{drag=null;};
const floorSelect = $('floor');
dom('option','全部高度层',floorSelect).value='all';
for (const level of [...levels].sort((a,b)=>a-b)) dom('option',`${level*2-1} to <${level*2+1} m`,floorSelect).value=level;
function setFloor(value){ floor=value; floorSelect.value=value===null?'all':value; drawGeometry(); drawMarkers(); }
floorSelect.onchange=()=>{ $('stack').hidden=true; setFloor(floorSelect.value==='all'?null:Number(floorSelect.value)); drawReplay(); };
$('geometry-note').textContent = geometry === null ? '当前仅显示路线；使用 --geometry 加载碰撞轮廓。' :
  '碰撞快照：灰色为结构，琥珀色为机关，蓝色虚线为触发区。动态机关显示采集时的位置。';
function drawGeometry(){
  const layer=$('collision'); layer.replaceChildren();
  const styles={static:['#324252','#627589',''],mechanism:['#493822','#d6a054',''],trigger:['none','#63a4c5','4 3']};
  // Batch SVG strokes while retaining triangle edges and degenerate (vertical) walls.
  const paths={static:[],mechanism:[],trigger:[]};
  for(const [style,lo,hi,polygon] of geometry ?? []){
    if(floor!==null && (hi<floor*2-1 || lo>=floor*2+1)) continue;
    const area=polygon.reduce((sum,[x,z],i)=>{const [u,v]=polygon[(i+1)%polygon.length];return sum+x*v-z*u;},0);
    const ordered=area<0?[...polygon].reverse():polygon;
    const points=ordered.map(([x,z])=>`${fmt(X(x))},${fmt(Z(z))}`);
    paths[style].push(`M${points.join('L')}${points.length===1?'l.04,0':'Z'}`);
  }
  for(const [style,parts] of Object.entries(paths)) if(parts.length){
    const [fill,stroke,dash]=styles[style];
    svg('path',{d:parts.join(''),fill,stroke,'stroke-width':.75,'stroke-dasharray':dash,'vector-effect':'non-scaling-stroke'},layer);
  }
}
function lerp(a,b,u){return a+(b-a)*u;}
function at(path,t){
  if(!path.length || t<path[0][0] || t>path.at(-1)[0]) return null;
  let l=0,h=path.length-1;
  while(l<h){const m=Math.ceil((l+h)/2); if(path[m][0]<=t) l=m; else h=m-1;}
  const a=path[l],b=path[l+1];
  return !b || a[0]===t ? a.slice(1) : a.slice(1).map((v,i)=>lerp(v,b[i+1],(t-a[0])/(b[0]-a[0])));
}
function trail(path,until){
  const parts=[]; let previous=null;
  for(let i=1;i<path.length;i++){
    const [a,x,y,z]=path[i-1], [b,xx,yy,zz]=path[i];
    if(until<=a) break;
    let start=0,end=Math.min(1,(until-a)/(b-a));
    if(floor!==null){
      if(y===yy){if(!inside(y)){previous=null;continue;}}
      else{const u=(floor*2-1-y)/(yy-y),v=(floor*2+1-y)/(yy-y);
        start=Math.max(start,Math.min(u,v)); end=Math.min(end,Math.max(u,v));}
    }
    if(start>=end){previous=null;continue;}
    const pt=u=>`${fmt(X(lerp(x,xx,u)))},${fmt(Z(lerp(z,zz,u)))}`;
    const begin=pt(start), finish=pt(end);
    if(previous!==begin) parts.push('M'+begin);
    parts.push('L'+finish); previous=finish;
  }
  return parts.join('');
}
function drawReplay(){
  const paths=$('paths'),actors=$('actors'); paths.replaceChildren();actors.replaceChildren();
  runs.forEach((r,i)=>{
    if(!enabled[i])return;
    for (const [path,hale] of [[r.path,false],[r.hale,true]]){
      const attrs={fill:'none',stroke:ink(i),'stroke-linejoin':'round','stroke-linecap':'round','stroke-width':hale?1.7:2.5,'stroke-dasharray':hale?'5 4':'','vector-effect':'non-scaling-stroke'};
      svg('path',{...attrs,d:trail(path,Infinity),opacity:.32},paths);
      svg('path',{...attrs,d:trail(path,current)},paths);
      const p=at(path,current);
      if(p && inside(p[1])){
        const x=X(p[0]),z=Z(p[2]);
        const actor=hale ? svg('path',{d:`M${x},${z-6}l6,6l-6,6l-6,-6Z`,fill:'#101721',stroke:ink(i),'stroke-width':2},actors) :
          svg('circle',{cx:x,cy:z,r:5,fill:ink(i),stroke:'#101721','stroke-width':1.5},actors);
        svg('title',{},actor).textContent=`${name(i)} · ${hale?'Hale':'玩家'} · ${p.map(fmt).join(', ')} m`;
      }
    }
  });
  $('time').textContent=`${current} / ${maxTick}`;
  for(const e of rows)e.button.classList.toggle('future',e.tick>current);
}
function showStack(group){
  const stack=$('stack'); stack.replaceChildren();stack.hidden=group.length<2;
  if(group.length<2)return;
  dom('strong',`此处 ${group.length} 条事件：`,stack);
  for(const e of group){const button=dom('button',`#${e.number} · ${e.tick} · ${e.kind}`,stack);button.onclick=()=>seekEvent(e,true);}
}
function drawMarkers(){
  const layer=$('markers');layer.replaceChildren();
  const groups=[];
  for(const e of rows){
    if(!enabled[e.run] || !e.point || !inside(e.point[1]) || (!visibleCategories.has(categoryOf(e)) && e!==selected))continue;
    const x=X(e.point[0]),z=Z(e.point[2]);
    let group=groups.find(g=>Math.hypot(x-g.x,z-g.z)<22);
    if(!group){group={x,z,events:[]};groups.push(group);}
    group.events.push(e);
  }
  for(const {x,z,events} of groups){
    const active=events.includes(selected), first=active?selected:events[0];
    const title=events.length===1?`#${first.number} · ${first.tick} · ${first.kind}`:`附近有 ${events.length} 条事件`;
    const g=svg('g',{class:'marker',tabindex:0,role:'button','aria-label':title},layer);
    svg('title',{},g).textContent=title;
    svg('circle',{cx:x,cy:z,r:10,fill:active?'#f2f7ff':'#1a2837',stroke:ink(first.run),'stroke-width':1.6},g);
    svg('text',{x,y:z,'text-anchor':'middle','dominant-baseline':'central',fill:active?'#111923':'#f2f7ff','font-size':8,'pointer-events':'none'},g).textContent=events.length===1?first.number:`×${events.length}`;
    function activate(){
      if(events.length===1) seekEvent(first,true);
      else {showStack(events);$('stack').querySelector('button').focus();}
    }
    g.onclick=activate; g.onkeydown=e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();activate();}};
  }
  if(selected?.point && enabled[selected.run] && inside(selected.point[1])){
    const [x,,z]=selected.point;
    svg('path',{d:`M${X(x)-6},${Z(z)}h12M${X(x)},${Z(z)-6}v12`,stroke:'#ffc067','stroke-width':1.7,'pointer-events':'none'},layer);
  }
}
function stop(){ if(playing!==null)cancelAnimationFrame(playing);playing=null;$('play').textContent='播放'; }
function seek(t){current=Math.max(0,Math.min(maxTick,t));tick.value=current;drawReplay();}
function seekEvent(e,scroll){
  stop();
  if(selected) selected.button.removeAttribute('aria-current');
  selected=e;enabled[e.run]=true;runChecks[e.run].checked=true;e.button.setAttribute('aria-current','true');
  if(e.point && !inside(e.point[1])){ $('stack').hidden=true; setFloor(band(e.point[1])); }
  if(e.point){
    const x=X(e.point[0]),z=Z(e.point[2]);
    const [vx,vz,w,h]=view;
    if(x<vx || x>vx+w || z<vz || z>vz+h){view=[x-w/2,z-h/2,w,h];updateView();}
  }
  $('selection').textContent=`#${e.number} · tick ${e.tick} · ${phaseText(e)}：${valueText(e.value)} · ${sourceText(e)}${e.point?' ('+e.point.map(fmt).join(', ')+' m)':''}`;
  seek(e.tick); drawMarkers();
  if(scroll)e.button.scrollIntoView({block:'nearest'});
}
for(const e of rows){
  const button=dom('button','',$('timeline'));e.button=button;button.className='event';button.dataset.phase=e.phase;
  dom('span',`#${e.number} · tick ${e.tick} · ${name(e.run)} · ${phaseText(e)} / ${e.kind}`,button).className='tag';
  dom('span',valueText(e.value),button).className='value';
  dom('span',sourceText(e),button).className='muted';
  button.onclick=()=>{ $('stack').hidden=true;seekEvent(e,false); };
}
if(!rows.length)dom('p','暂无事件记录。',$('timeline'));
const table=dom('table','',$('parameters'));
const head=dom('tr','',dom('thead','',table));dom('th','参数',head);
const metadata=runs.map(r=>{
  const fields=new Map(Object.entries(r.metadata));fields.delete('policy_parameters');
  if(r.metadata.policy_parameters && typeof r.metadata.policy_parameters==='object'){
    for(const [k,v] of Object.entries(r.metadata.policy_parameters))fields.set(`policy.${k}`,v);
  }else if('policy_parameters' in r.metadata)fields.set('policy_parameters',r.metadata.policy_parameters);
  return fields;
});
runs.forEach((r,i)=>{
  dom('th',name(i),head);
  const label=dom('label','',$('runs'));label.className='route-key';label.style.color=ink(i);
  const check=dom('input','',label);check.type='checkbox';check.checked=enabled[i];runChecks.push(check);dom('span',name(i),label);
  check.onchange=()=>{
    enabled[i]=check.checked;$('stack').hidden=true;
    if(selected?.run===i && !check.checked){selected.button.removeAttribute('aria-current');selected=null;$('selection').textContent='';}
    drawMarkers();drawReplay();
  };
});
for(const [key,text] of Object.entries(categories)){
  const label=dom('label','',$('categories'));
  const check=dom('input','',label);check.type='checkbox';check.checked=visibleCategories.has(key);
  dom('span',text,label);
  check.onchange=()=>{
    if(check.checked)visibleCategories.add(key);else visibleCategories.delete(key);
    $('stack').hidden=true;drawMarkers();
  };
}
const body=dom('tbody','',table);
for(const k of new Set(metadata.flatMap(m=>[...m.keys()]))){
  const row=dom('tr','',body);dom('th',k,row).scope='row';
  for(const m of metadata)dom('td',m.has(k)?valueText(m.get(k)):'—',row);
}
tick.oninput=()=>{stop();seek(Number(tick.value));};
$('play').disabled=maxTick===0;
$('play').onclick=()=>{
  if(playing!==null){stop();return;}
  if(current===maxTick)seek(0);
  const start=performance.now(),from=current;
  const rate=Number(runs[0].metadata.physics_hz);
  const hz=Number.isFinite(rate) && rate>0 ? rate : 60;
  $('play').textContent='暂停';
  function frame(now){const next=Math.min(maxTick,from+Math.floor((now-start)*hz/1000));
    if(next!==current)seek(next);
    if(next>=maxTick)stop();else playing=requestAnimationFrame(frame);
  }
  playing=requestAnimationFrame(frame);
};
drawGeometry();drawMarkers();seek(0);
</script></body></html>'''
