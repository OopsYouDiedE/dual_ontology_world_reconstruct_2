'use strict';

// The scenario is intentionally independent of Godot, canon, and persistent state.
const blank = () => ({ phase: 'routine', findings: [], selected: 'arrival' });
const clues = {
  witness: ['Lin’s headcount', '“I counted sixteen before the bell and sixteen after. I stayed by the stairs. Nobody passed me.”'],
  tube: ['The brass speaking tube', 'You tap two beats at the brass mouth. The same two beats return through the ceiling, from beyond the closed door.'],
  chalk: ['The two chalk marks', 'The tally has one mark for each response. The last two marks sit beneath the same name.'],
};
const endings = {
  held: ['Count held at sixteen', 'Lin signs beside you. The extra response stays in the margin, separate from the headcount. At the far end, the extra corridor disappears and the latch clicks shut.', 'EXCEPTION FILED'],
  registered: ['Seventeen entered', 'The register closes on a total of seventeen. The seventh door keeps its light. The morning duty list now includes a place setting with a number and no name.', 'REGISTER ACCEPTED'],
  pending: ['Return to the desk at dawn', 'With the line left blank, the register is held open. Lin agrees to stay and take first watch. The morning shift will have to count again.', 'REGISTER HELD OPEN'],
};
function advance(state, action) {
  if (action === 'reset') return blank();
  if (state.phase === 'routine' && action === 'notice') return { ...state, selected: 'notice' };
  if (state.phase === 'routine' && state.selected === 'notice' && action === 'wait') return { ...state, phase: 'echo', selected: 'register' };
  if (state.phase !== 'echo') return state;
  if (action === 'notice') return { ...state, selected: 'notice' };
  if (Object.hasOwn(clues, action)) return { ...state, findings: [...new Set([...state.findings, action])], selected: action };
  if (action === 'attest' && state.findings.length === Object.keys(clues).length) return { ...state, phase: 'held' };
  if (action === 'copy') return { ...state, phase: 'registered' };
  if (action === 'defer') return { ...state, phase: 'pending' };
  return state;
}

if (typeof module !== 'undefined') module.exports = { blank, advance };
if (typeof document !== 'undefined') mount();

function mount() {
  let state = blank();
  let enabled = false, audio;
  let voices = [];
  const el = id => document.getElementById(id);
  const button = (action, text, extra = '') => `<button type="button" data-action="${action}" ${extra}>${text}</button>`;
  const notice = `<p>After the second bell, enter the number present.</p><p>If the number of responses differs from the headcount, a witness may attest the headcount. Note what caused the difference.</p>`;
  const head = (tag, title) => `<p class="tag">${tag}</p><h2>${title}</h2>`;

  const listen = () => {
    if (!audio) audio = new AudioContext();
    return audio.resume();
  };
  function sweep() {
    for (const voice of voices) { try { voice.stop(); } catch {} }
    voices = [];
  }
  function strike(time, pitch, volume, decay, pan, partials) {
    const panner = audio.createStereoPanner();
    panner.pan.value = pan;
    panner.connect(audio.destination);
    let remaining = partials.length;
    for (const [ratio, strength] of partials) {
      const oscillator = audio.createOscillator(), gain = audio.createGain();
      oscillator.frequency.value = pitch * ratio;
      gain.gain.setValueAtTime(.0001, time);
      gain.gain.exponentialRampToValueAtTime(volume * strength, time + .011);
      gain.gain.exponentialRampToValueAtTime(.0001, time + decay);
      oscillator.connect(gain).connect(panner);
      oscillator.start(time); oscillator.stop(time + decay + .025);
      voices.push(oscillator);
      oscillator.onended = () => {
        voices = voices.filter(voice => voice !== oscillator);
        oscillator.disconnect(); gain.disconnect();
        if (--remaining === 0) panner.disconnect();
      };
    }
  }
  function cue(action) {
    if (!enabled || !audio || audio.state !== 'running') return;
    sweep();
    const t = audio.currentTime + .04;
    const bell = [[1,.8],[1.49,.26],[2.36,.18],[4.11,.07]];
    const brass = [[1,.7],[1.81,.33],[3.38,.18]];
    if (action === 'wait') {
      strike(t, 211, .17, 1.25, -.2, bell);
      strike(t + .61, 211, .19, 1.65, .04, bell);
    }
    if (action === 'tube') {
      for (const delta of [0, .24]) strike(t + delta, 403, .14, .18, -.44, brass);
      for (const delta of [0, .24]) strike(t + .58 + delta, 312, .10, .40, .42, brass);
    }
    if (action === 'attest') strike(t, 172, .10, .65, 0, bell);
  }
  function render() {
    const { phase, selected, findings } = state;
    const final = endings[phase];
    el('view').dataset.look = phase;
    el('time').textContent = phase === 'routine' ? '21:59' : '22:00';
    el('look').textContent = final?.[2] || (phase === 'routine' ? 'BEFORE THE BELL' : 'AFTER THE SECOND BELL');
    el('scene-note').textContent = ['echo', 'registered'].includes(phase) ? 'The far door remains open' : 'Mullioned windows · west wing';
    el('corridor-desc').textContent = ['echo', 'registered'].includes(phase)
      ? 'Lin stands by the stair. Pale silhouettes repeat in the glass. The corridor continues through an open door.'
      : 'Lin stands by the stair. The second-floor corridor ends at a closed door. Oak doors face mullioned windows.';
    for (const spot of el('hotspots').querySelectorAll('button')) {
      const item = spot.dataset.action;
      spot.hidden = Boolean(final) || (phase === 'routine' && item !== 'notice');
      spot.classList.toggle('seen', findings.includes(item));
      spot.setAttribute('aria-pressed', String(selected === item && !final));
    }
    let paper = '', actions = '';
    if (phase === 'routine') {
      paper = selected === 'notice' ? head('POSTED IN THE WEST WING', 'Night duty notice') + notice
        : head('DUTY DESK / WEST WING', 'The night shift') + `<p>The washbasin is still warm. Lin is stationed at the stairs. Across the hall, a brass tube runs into the ceiling.</p><hr><p class="dispatch">The rules for night duty are posted on the wall.</p>`;
      actions = selected === 'notice' ? button('wait', 'Wait for the second bell', 'class="primary"') : '';
    } else if (phase === 'echo') {
      paper = head('DORMITORY REGISTER', selected === 'notice' ? 'Night duty notice' : clues[selected]?.[0] || 'One extra response');
      paper += selected === 'notice' ? notice : clues[selected] ? `<p class="dispatch">${clues[selected][1]}</p>` : `<p>The register gives the same name twice. Both responses have been counted.</p>`;
      paper += `<hr><div class="register"><span>Responses in the register</span><strong>17</strong><span>Headcount at the stairs</span><strong>${findings.includes('witness') ? '16' : '—'}</strong></div>`;
      if (findings.length) paper += `<ul class="findings">${findings.map(key => `<li>${clues[key][0]}</li>`).join('')}</ul>`;
      const ready = findings.length === Object.keys(clues).length;
      actions = button('attest', 'Attest sixteen with Lin', ready ? 'class="primary"' : 'disabled aria-describedby="attest-hint"') +
        (ready ? '' : '<p class="hint" id="attest-hint">Get Lin’s count and verify the extra response.</p>') +
        button('copy', 'Enter seventeen as recorded') + button('defer', 'Leave the line blank');
    } else {
      paper = head('DUTY REPORT / 22:00', final[0]) + `<p>${final[1]}</p>`;
      actions = button('reset', 'Play again', 'class="primary"');
    }
    el('sheet').innerHTML = paper;
    el('actions').innerHTML = actions;
  }
  document.addEventListener('click', event => {
    const target = event.target.closest('button');
    if (!target) return;
    if (target.id === 'sound') {
      const previous = enabled;
      enabled = !enabled;
      target.textContent = enabled ? 'Sound on' : 'Sound off';
      target.setAttribute('aria-pressed', String(enabled));
      if (enabled) void Promise.resolve().then(() => enabled && listen()).catch(() => {
        if (!enabled) return;
        enabled = false; target.textContent = 'Sound unavailable'; target.setAttribute('aria-pressed', 'false');
      });
      if (previous) sweep();
      return;
    }
    const action = target.dataset.action || (target.id === 'reset' && 'reset');
    if (!action) return;
    const next = advance(state, action);
    if (next === state) return;
    const keyboard = event.detail === 0;
    if (action === 'reset') sweep(); else cue(action);
    state = next;
    render();
    if (keyboard && (target.hidden || !target.isConnected)) {
      const focus = action === 'wait' ? '[data-action="witness"]'
        : state.phase === 'routine' ? '[data-action="notice"]' : '#actions button';
      document.querySelector(focus)?.focus();
    }
  });
  draw(el('corridor'));
  render();
}

function draw(svg) {
  const vp = [583, 259];
  const near = [[13,-72],[1064,-72],[1064,644],[13,644]];
  const ray = (idx, z) => near[idx].map((value, axis) => vp[axis] + (value - vp[axis]) * z);
  const lerp = (a, b, t) => a.map((val,i) => val + (b[i] - val) * t);
  const wall = (side, z, h) => lerp(ray(side ? 2 : 3,z), ray(side ? 1 : 0,z), h);
  const pt = p => p.map(x => x.toFixed(2)).join(',');
  const shape = (points, fill, stroke = 'none', width = 1) => `<polygon points="${points.map(pt).join(' ')}" fill="${fill}" stroke="${stroke}" stroke-width="${width}"/>`;
  const line = (a,b,color,sw=1) => `<path d="M${pt(a)} L${pt(b)}" fill="none" stroke="${color}" stroke-width="${sw}"/>`;
  const panel = (side, a,b, low,high, fill, stroke='none', sw=1) => shape([wall(side,a,low),wall(side,a,high),wall(side,b,high),wall(side,b,low)],fill,stroke,sw);
  const g = (id,label) => `<g opacity="var(--${id})">${label}</g>`;
  const defs = `<defs>
  <linearGradient id="plaster" x1="0" y1="0" x2="1" y2=".54"><stop stop-color="var(--wall)"/><stop offset="1" stop-color="var(--side)"/></linearGradient>
  <linearGradient id="plaster-r" x1="1" y1="0" x2="0" y2=".83"><stop stop-color="var(--wall)"/><stop offset="1" stop-color="var(--side)"/></linearGradient>
  <linearGradient id="ceiling" x1="0" y1="0" x2="0" y2="1"><stop stop-color="var(--shadow)"/><stop offset="1" stop-color="var(--air)"/></linearGradient>
  <linearGradient id="ground" x1="0" y1="1" x2="0" y2="0"><stop stop-color="var(--floor)"/><stop offset=".68" stop-color="var(--side)"/><stop offset="1" stop-color="var(--air)"/></linearGradient>
  <linearGradient id="glass" x1="0" y1="1" x2=".7" y2="0"><stop stop-color="var(--wall)"/><stop offset=".56" stop-color="var(--sky)"/><stop offset="1" stop-color="var(--light)"/></linearGradient>
  <linearGradient id="oak" x1="0" y1="0" x2="1" y2=".5"><stop stop-color="#554432"/><stop offset=".54" stop-color="#39382b"/><stop offset="1" stop-color="var(--shadow)"/></linearGradient>
  <linearGradient id="paper" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#e2d6ac"/><stop offset="1" stop-color="#ab976c"/></linearGradient>
  <radialGradient id="haze" gradientUnits="userSpaceOnUse" cx="595" cy="272" r="317" gradientTransform="matrix(1 0 0 .8 0 45)"><stop stop-color="var(--depth)" stop-opacity=".44"/><stop offset="1" stop-color="var(--depth)" stop-opacity="0"/></radialGradient>
  <radialGradient id="vignette" cx=".53" cy=".43" r=".72"><stop offset=".44" stop-color="#101512" stop-opacity="0"/><stop offset="1" stop-color="#101512" stop-opacity=".68"/></radialGradient>
  <filter id="grain" x="0" y="0" width="100%" height="100%"><feTurbulence baseFrequency=".67" numOctaves="3" seed="18" type="fractalNoise"/></filter>
  <filter id="blur"><feGaussianBlur stdDeviation="7"/></filter>
  </defs>`;
  let art = defs;
  const back = [.13,.10];
  const [a,b,c,d] = [0,1,2,3].map(i=>ray(i,back[0]));
  art += shape([near[0],near[1],b,a],'url(#ceiling)') + shape([near[3],near[2],c,d],'url(#ground)') +
    shape([near[0],a,d,near[3]],'url(#plaster)') + shape([near[1],b,c,near[2]],'url(#plaster-r)');
  art += shape([a,b,c,d],'var(--wall)');
  for (let z=1;z>.14;z*=.77) art += line(ray(3,z),ray(2,z),'#a1a18a32',Math.max(.5,z*2));
  for(let i=0;i<=18;i++) art += line(lerp(near[3],near[2],i/18),lerp(d,c,i/18),'#161f1a55');
  for (const side of [0,1]) {
    art += panel(side,1,.13,0,.30,'url(#oak)');
    for (const h of [.018,.27,.295,.31,.91,.928]) art += line(wall(side,1,h),wall(side,.13,h),h === .31 ? 'var(--brass)' : '#151c1b85',h === .295 ? 5 : 2);
    for (let z=.95;z>.14;z*=.82) {
      art += panel(side,z,z*.86,.072,.234,'#85837110','#b6a06a4a',Math.max(.5,z*1.8));
    }
  }
  // Dormitory doors and brass room numbers.
  for (const z of [.94,.68,.50,.35,.25,.18]) {
    art += panel(0,z,z*.79,.03,.80,'url(#oak)','#151f1e',z*12);
    for (const [lo,hi] of [[.12,.29],[.36,.62],[.66,.74]]) art += panel(0,z*.97,z*.83,lo,hi,lo===.36?'#151f1e43':'#9684601d','#877958',z*2);
    const knob = wall(0,z*.85,.37);
    art += `<circle cx="${knob[0]}" cy="${knob[1]}" r="${z*6}" fill="var(--brass)" stroke="#212926"/>`;
  }
  const glows = [];
  for (const z of [1,.70,.48,.33,.23]) {
    art += panel(1,z,z*.74,.36,.85,'url(#glass)','#222d2b',z*11);
    art += panel(1,z,z*.74,.35,.363,'var(--brass)');
    art += panel(1,z,z*.74,.59,.615,'var(--side)');
    art += panel(1,z*.866,z*.84,.36,.85,'var(--side)');
    const sil = wall(1,z*.79,.40);
    art += g('echo',`<path transform="translate(${pt(sil)}) scale(${z*.62})" d="M-10 0 Q-11 -19 -6 -25 Q-10 -37 0 -42 Q10 -40 6 -26 Q14 -18 13 0Z" fill="var(--shadow)" opacity=".49"/>`);
    const p = ray(2,z), q = ray(2,z*.77);
    glows.push(shape([p,q,[q[0]-z*175,q[1]+z*79],[p[0]-z*163,p[1]+z*87]],'var(--light)'));
  }
  art += `<g opacity=".19" filter="url(#blur)">${glows.join('')}</g>`;
  // End wall: the same portal contains a closed door or an impossible continuation.
  art += shape([[548,216],[620,216],[620,308],[548,308]],'var(--shadow)','var(--brass)',2);
  art += g('real',`<rect x="554" y="221" width="61" height="83" rx="1" fill="url(#oak)" stroke="var(--side)" stroke-width="3"/><path d="M565 233h39v27h-39z M565 265h39v28h-39z" fill="none" stroke="#968365" stroke-width=".7"/><circle cx="605" cy="264" r="1.8" fill="var(--brass)"/>`);
  let distance = '<path d="M551 219h66v86h-66Z" fill="var(--depth)"/><path d="M551 305l33-44 33 44Z" fill="var(--floor)"/>';
  for (const s of [1,.77,.59,.45,.34,.24,.15]) distance += `<rect x="${584-32*s}" y="${261-40*s}" width="${64*s}" height="${83*s}" fill="none" stroke="var(--shadow)" stroke-width="${3*s}"/><circle cx="584" cy="${261-32*s}" r="${3*s}" fill="var(--light)"/>`;
  art += g('long',distance) + '<rect width="960" height="600" fill="url(#haze)"/>';
  for (const z of [.97,.68,.46,.30,.19]) {
    const p=lerp(ray(0,z),ray(1,z),.50);
    art += `<g transform="translate(${pt(p)}) scale(${z})"><path d="M0 0v69" stroke="var(--shadow)" stroke-width="3"/><ellipse cy="77" rx="26" ry="16" fill="var(--light)" opacity=".31" filter="url(#blur)"/><path d="M-13 72L-5 64H5L13 72V82H-13Z" fill="var(--brass)" stroke="var(--shadow)" stroke-width="2"/><path d="M-9 73h18v7h-18z" fill="var(--light)"/><path d="M-15 82h30" stroke="var(--shadow)" stroke-width="2"/></g>`;
  }
  art += `<path d="M0 121L397 210Q420 215 447 216L553 233M322 197v-33q0-10 10-10h8" fill="none" stroke="var(--shadow)" stroke-width="11"/><path d="M0 119L397 208Q420 213 447 214L553 231M321 196v-32q0-10 10-10h8" fill="none" stroke="var(--brass)" stroke-width="7"/><ellipse cx="335" cy="155" rx="12" ry="8" fill="var(--brass)"/><ellipse cx="337" cy="154" rx="6" ry="4" fill="var(--shadow)"/>`;
  art += `<g transform="translate(149 207) skewY(10)"><rect x="-7" y="-7" width="75" height="77" fill="#36352b" stroke="var(--brass)" stroke-width="3"/><rect width="61" height="64" fill="url(#paper)"/><path d="M7 16h47M7 31h44m-44 6h47m-47 6h41m-41 6h45m-45 6h38" stroke="#52472e" fill="none" stroke-width=".8"/><text x="7" y="12" font-family="Georgia,serif" font-size="7" fill="#3e3827">NIGHT DUTY</text></g>`;
  art += g('echo',`<g><path d="M105 401l88 11v27l-88-12Z" fill="#252923" stroke="var(--brass)" stroke-width="2"/><path d="M116 408v15m7-14v15m7-14v15m7-14v15m-25-11l29 10m8-10v15m7-14v15m7-14v15m7-14v15m-24-11l28 9m8-9v14m7-13v14" stroke="#e5e1cd" stroke-width="1.2"/></g>`);
  art += `<g><ellipse cx="625" cy="402" rx="32" ry="6" fill="#111815" opacity=".55"/><path d="M605 397L609 348l-6 24-8-4 6-32q4-11 17-11l4-7h12l4 7q13 4 16 13l4 29-9 2-7-23 4 50h-11l-6-37-6 35-12 6Z" fill="#303734" stroke="#202726" stroke-width="2"/><path d="M618 325l9 19 12-18m-14 23h6" fill="none" stroke="#aa9b78" stroke-width="2"/><path d="M620 320q-7-14-3-20 5-10 16-6 9 2 8 12 0 10-9 15Z" fill="#ac967b"/><path d="M617 310q-8-15 8-18 13-2 17 10l-10-3-9 10Z" fill="#26302f"/></g>`;
  art += '<rect width="960" height="600" fill="url(#vignette)" pointer-events="none"/><rect width="960" height="600" filter="url(#grain)" opacity=".12" style="mix-blend-mode:soft-light" pointer-events="none"/>';
  svg.insertAdjacentHTML('beforeend',art);
}
