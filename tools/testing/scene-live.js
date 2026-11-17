(() => {
  'use strict';
  const stateNames = {passed:'完成', failed:'失败', blocked:'受阻', cancelled:'已停止', running:'进行中', starting:'启动中', planned:'等待中', unknown:'未知'};
  const categories = ['fluidity','text_density','action_sfx_integrity','audio_loudness','blind_narrative_match','aesthetic_similarity','narrative_flow'];
  const labels = ['游玩流畅度','界面字数','动作与音效','音频响度','视听剧情替代','参考图相似度','剧情流畅性'];
  const node = (tag, text = '') => { const e = document.createElement(tag); e.textContent = text; return e; };
  const href = path => document.body.dataset.projectBase + path.split('/').map(encodeURIComponent).join('/');
  function anchor(path, text) { const a = node('a', text); a.href = href(path); return a; }
  function draw(data) {
    if (!data || !Array.isArray(data.rows)) return;
    let section = document.querySelector('.scene-survey');
    if (!section) {
      section = node('section'); section.className = 'score-coverage scene-survey';
      const main = document.querySelector('main');
      if (!main) return;
      main.insertBefore(section, main.firstChild);
    }
    const heading = node('h2', '场景逐项测试与卡点');
    const summary = node('p', `批次 ${data.id} · 版本 ${(data.revision || '').slice(0,12)} · ${stateNames[data.state] || data.state} · `);
    if (data.status_path) summary.append(anchor(data.status_path, '批次状态'));
    const scroll = node('div'); scroll.className = 'coverage-scroll';
    const table = node('table'), head = node('thead'), tr = node('tr');
    ['场景','房间','最近阶段','状态','问题 / 卡点',...labels,'证据'].forEach(label => tr.append(node('th', label)));
    head.append(tr); const tbody = node('tbody');
    data.rows.forEach(row => {
      const r = node('tr'); r.dataset.surveyCase = row.id;
      [row.id, row.room, row.phase, stateNames[row.state] || row.state, row.reason || (row.state === 'passed' ? '检查执行结束' : '等待结果')]
        .forEach((text, i) => r.append(node(i === 0 ? 'th' : 'td', text)));
      categories.forEach(key => {
        const cell = node('td'); cell.className = 'survey-score'; cell.dataset.surveyScore = key;
        const value = row.scores?.[key];
        const valid = typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 10;
        cell.append(node('strong', valid ? `${value}/10` : '未测'), node('small', row.reasons?.[key] || '该场景当前批次尚无评分。'));
        r.append(cell);
      });
      const evidence = node('td');
      [[row.evidence,'结果'],[row.progress,'最近步骤'],[(row.images || []).at(-1),'画面']].forEach(([path,label]) => {
        if (path) evidence.append(anchor(path,label), node('span',' '));
      });
      if (!evidence.children.length) evidence.textContent = '—';
      r.append(evidence); tbody.append(r);
    });
    table.append(head,tbody); scroll.append(table); section.replaceChildren(heading,summary,scroll);
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
