(() => {
  'use strict';
  const categories = ['fluidity', 'text_density', 'action_sfx_integrity', 'audio_loudness', 'blind_narrative_match', 'aesthetic_similarity', 'narrative_flow'];
  const labels = ['游玩流畅度', '界面字数', '动作与音效', '音频响度', '视听剧情替代', '参考图相似度', '剧情流畅性'];
  const scoreText = value => value === null ? '评分缺项' : `${value}/10`;
  const element = (tag, text) => { const node = document.createElement(tag); node.textContent = text; return node; };
  const valid = batch => categories.every(key => Object.hasOwn(batch.scores || {}, key)
    && (batch.scores[key] === null || (typeof batch.scores[key] === 'number' && Number.isFinite(batch.scores[key]) && batch.scores[key] >= 0 && batch.scores[key] <= 10))
    && typeof batch.reasons?.[key] === 'string' && batch.reasons[key].trim());
  function update() {
    const latest = new Map();
    for (let event of window.MAINLINE_PROGRESS?.events || []) {
      if (!event.test_result && event.development_score) {
        const old = event.development_score;
        event = {...event, test_result: {test_id: event.event_id,
          scores: Object.fromEntries(categories.map(key => [key, key === old.category ? old.score : null])),
          reasons: Object.fromEntries(categories.map(key => [key, key === old.category ? (old.rationale || 'Recorded test score.') : 'This test did not collect this dimension.']))}};
      }
      if (!event.test_result || !valid(event.test_result)) continue;
      const previous = latest.get(event.segment_id);
      if (!previous || Date.parse(event.at) > Date.parse(previous.at) ||
          (event.at === previous.at && event.test_result.test_id > previous.test_result.test_id)) latest.set(event.segment_id, event);
    }
    document.querySelectorAll('[data-test-card]').forEach(card => {
      const event = latest.get(card.dataset.testCard);
      if (!event || (card.dataset.testAt && (Date.parse(event.at) < Date.parse(card.dataset.testAt) ||
          (Date.parse(event.at) === Date.parse(card.dataset.testAt) && event.test_result.test_id <= card.dataset.testId)))) return;
      const source = event.test_result;
      const provisional = new Set(source.provisional_categories || []);
      for (const key of categories) if (source.scores[key] === null) provisional.add(key);
      const batch = {...source,
        scores: Object.fromEntries(categories.map(key => [key, source.scores[key] === null ? 0 : source.scores[key]])),
        reasons: Object.fromEntries(categories.map(key => [key, provisional.has(key) && !source.reasons[key].startsWith('Provisional 0:')
          ? 'Provisional 0: evidence unavailable; test incomplete. ' + source.reasons[key] : source.reasons[key]]))};
      const formatted = key => scoreText(batch.scores[key]) + (provisional.has(key) ? ' (暂定·缺证据)' : '');
      const body = document.createElement('div'); body.dataset.resultBody = '';
      body.append(element('p', `测试 ${batch.test_id} · ${event.at} · 版本 ${event.revision.slice(0, 12)}`));
      const values = categories.map(key => batch.scores[key]);
      body.append(element('p', provisional.size || source.status === 'incomplete' ? '已测 · 测试未完成' : values.some(v => v < 8) ? '不合格' : '合格'));
      const grid = document.createElement('div'); grid.className = 'dimensions';
      categories.forEach((key, i) => {
        const value = batch.scores[key], dim = document.createElement('div');
        dim.className = 'dimension ' + (provisional.has(key) ? 'pending' : value >= 8 ? 'pass' : 'fail');
        dim.append(element('span', labels[i]), element('b', formatted(key)), element('p', batch.reasons[key]));
        grid.append(dim);
      });
      body.append(grid);
      if (event.evidence?.length) {
        const evidence = element('details', ''); evidence.append(element('summary', '测试证据'));
        for (const path of event.evidence) {
          const anchor = element('a', path.split(/[\\/]/).pop());
          anchor.href = document.body.dataset.projectBase + path.replaceAll('\\', '/').split('/').map(encodeURIComponent).join('/');
          evidence.append(anchor, element('br', ''));
        }
        body.append(evidence);
      } else if (values.every(v => v !== null && v >= 8)) {
        body.children[1].textContent = '已测 · 评分不全';
        body.append(element('p', 'This test did not attach measurement evidence.'));
      }
      card.querySelector('[data-result-body]').replaceWith(body);
      // A newer test replaces the whole result, including the older screenshots.
      card.querySelector(':scope > p')?.remove();
      card.dataset.testAt = event.at;
      card.dataset.testId = batch.test_id;
      document.querySelectorAll('[data-test-segment]').forEach(row => {
        if (row.dataset.testSegment !== event.segment_id) return;
        row.querySelector('[data-test-id]').textContent = batch.test_id;
        row.querySelectorAll('[data-batch-score]').forEach(cell => { cell.textContent = formatted(cell.dataset.batchScore); });
      });
    });
  }
  const dialog = document.getElementById('image-view');
  document.querySelectorAll('a.zoom').forEach(a => a.addEventListener('click', event => {
    event.preventDefault(); dialog.querySelector('img').src = a.href; dialog.showModal();
  }));
  dialog?.querySelector('button').addEventListener('click', () => dialog.close());
  let loading = false;
  function refresh() {
    if (loading) return;
    loading = true;
    const script = document.createElement('script'); script.src = 'live-progress.js?t=' + Date.now();
    script.onload = () => { update(); script.remove(); loading = false; };
    script.onerror = () => { script.remove(); loading = false; };
    document.body.append(script);
  }
  refresh(); setInterval(refresh, 2000);
})();
