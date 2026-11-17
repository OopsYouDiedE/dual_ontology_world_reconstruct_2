(() => {
  'use strict';
  const stateNames = {passed:'执行结束', failed:'失败', blocked:'受阻', cancelled:'已停止', running:'进行中', starting:'启动中', planned:'等待中', unknown:'未知'};
  const node = (tag, text = '') => { const e = document.createElement(tag); e.textContent = text; return e; };
  const href = path => document.body.dataset.projectBase + path.split('/').map(encodeURIComponent).join('/');
  function anchor(path, text) { const a = node('a', text); a.href = href(path); return a; }
  let lastData = null;
  function draw(data) {
    if (!data || !Array.isArray(data.rows)) return;
    const serialized = JSON.stringify(data);
    if (serialized === lastData) return;
    // Remove the standalone scene table from older generated reports.
    const legacy = document.querySelector('main > .scene-survey');
    if (legacy) legacy.remove();
    document.querySelectorAll('[data-test-card]').forEach(card => {
      const rows = data.rows.filter(row => row.segment_id === card.dataset.testCard);
      let section = card.querySelector('[data-scene-evidence]');
      if (!rows.length) { if (section) section.remove(); return; }
      if (!section) { section = node('section'); section.className = 'scene-survey'; section.dataset.sceneEvidence = ''; card.append(section); }
      let details = section.querySelector('details');
      if (!details) { details = node('details'); section.append(details); }
      const previousScroll = details.querySelector('.coverage-scroll');
      const scrollLeft = previousScroll?.scrollLeft || 0, scrollTop = previousScroll?.scrollTop || 0;
      const heading = node('summary', '场景执行详情与卡点');
      const summary = node('p', `场景批次 ${data.id} · 版本 ${(data.revision || '').slice(0,12)} · ${stateNames[data.state] || data.state} · `);
      if (data.status_path) summary.append(anchor(data.status_path, '批次状态'));
      const scroll = node('div'); scroll.className = 'coverage-scroll';
      const table = node('table'), head = node('thead'), tr = node('tr');
      ['场景','房间','最近阶段','执行状态','问题 / 卡点','证据'].forEach(label => tr.append(node('th', label)));
      head.append(tr); const tbody = node('tbody');
      rows.forEach(row => {
        const r = node('tr'); r.dataset.surveyCase = row.id;
        [row.id, row.room, row.phase, stateNames[row.state] || row.state, row.reason || (row.state === 'passed' ? '执行结束，评分见本片段' : '等待结果')]
          .forEach((text, i) => r.append(node(i === 0 ? 'th' : 'td', text)));
        const evidence = node('td');
        [[row.evidence,'结果'],[row.progress,'最近步骤'],[(row.images || []).at(-1),'画面']].forEach(([path,label]) => {
          if (path) evidence.append(anchor(path,label), node('span',' '));
        });
        if (!evidence.children.length) evidence.textContent = '—';
        r.append(evidence); tbody.append(r);
      });
      table.append(head,tbody); scroll.append(table); details.replaceChildren(heading,summary,scroll);
      scroll.scrollLeft = scrollLeft; scroll.scrollTop = scrollTop;
    });
    lastData = serialized;
  }
  let loading = false;
  function refresh() {
    if (loading) return;
    loading = true;
    const script = node('script'); script.src = 'scene-survey.js?t=' + Date.now();
    script.onload = () => { draw(window.SCENE_SURVEY); script.remove(); loading = false; };
    script.onerror = () => { script.remove(); loading = false; };
    document.body.append(script);
  }
  refresh(); setInterval(refresh, 2000);
})();
