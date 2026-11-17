(() => {
  'use strict';
  const dialog = document.getElementById('image-view');
  document.querySelectorAll('a.zoom').forEach(a => a.addEventListener('click', e => {
    e.preventDefault(); dialog.querySelector('img').src = a.href; dialog.showModal();
  }));
  dialog?.querySelector('button').addEventListener('click', () => dialog.close());
  dialog?.addEventListener('click', e => { if (e.target === dialog) dialog.close(); });
  document.querySelectorAll('.score-editor').forEach(editor => {
    const original = JSON.parse(editor.dataset.review);
    const labels = JSON.parse(editor.dataset.labels);
    const form = document.createElement('form');
    const addField = (label, input) => {
      const wrapper = document.createElement('label');
      wrapper.append(document.createTextNode(label), input);
      form.append(wrapper);
      return input;
    };
    const id = addField('新记录 ID', document.createElement('input'));
    id.required = true; id.pattern = '[a-z0-9][a-z0-9_-]{1,119}';
    id.placeholder = '例如 wake-audit-01';
    const summary = addField('修订说明', document.createElement('input'));
    summary.required = true; summary.maxLength = 8000;
    const fields = labels.map((label, index) => {
      const score = document.createElement('input');
      score.type = 'number'; score.min = '0'; score.max = '10'; score.step = 'any';
      score.value = original.scores[index] ?? '';
      addField(label + ' (0–10，留空为待评)', score);
      const reason = document.createElement('textarea');
      reason.value = original.score_reasons[index] ?? '';
      addField(label + ' 评分依据', reason);
      return {score, reason};
    });
    const submit = document.createElement('button');
    submit.type = 'submit'; submit.textContent = '下载修订请求'; form.append(submit);
    const message = document.createElement('p'); message.className = 'meta';
    message.setAttribute('role', 'status'); form.append(message);
    form.addEventListener('submit', event => {
      event.preventDefault();
      const scores = fields.map(field => field.score.value === '' ? null : Number(field.score.value));
      if (id.value === original.id || scores.some((score, index) => score !== null && !fields[index].reason.value.trim())) {
        message.textContent = '请使用新的记录 ID，并为每个已评分项填写依据。'; return;
      }
      const record = {...original, id: id.value, supersedes: original.id,
        observed_at: new Date().toISOString(), scores,
        score_reasons: fields.map(field => field.reason.value)};
      const request = {work_id: id.value, summary: summary.value, record};
      const url = URL.createObjectURL(new Blob([JSON.stringify(request, null, 2) + '\n'], {type: 'application/json'}));
      const download = document.createElement('a');
      download.href = url; download.download = id.value + '.json'; download.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      message.textContent = '草稿已下载；请按项目说明通过 MCP 提交并验证。';
    });
    editor.querySelector('.score-editor-fields').append(form);
  });
  const list = document.getElementById('progress-events');
  if (!list) return;
  const seen = new Set(Array.from(list.children, row => row.dataset.eventId));
  const labels = {change: '修改', check: '检测', complete: '完成确认'};
  function node(tag, text, cls) {
    const el = document.createElement(tag); el.textContent = text;
    if (cls) el.className = cls;
    return el;
  }
  function update() {
    const events = window.MAINLINE_PROGRESS?.events;
    if (!Array.isArray(events)) return;
    // Recompute latest development values in ledger order; formal cards remain untouched.
    const latestScores = new Map();
    for (const e of events) {
      const score = e.development_score;
      if (!score || score.acceptance_eligible !== false || typeof score.score !== 'number' ||
          !Number.isFinite(score.score) || score.score < 0 || score.score > 10) continue;
      latestScores.set(e.segment_id + '\0' + score.category, e);
    }
    document.querySelectorAll('.segment[data-segment]').forEach(segment => {
      segment.querySelectorAll('[data-score-category]').forEach(card => {
        const e = latestScores.get(segment.dataset.segment + '\0' + card.dataset.scoreCategory);
        if (!e) return;
        const score = e.development_score;
        const dimension = card.closest('.dimension');
        if (dimension && dimension.dataset.formalScored === 'false') {
          dimension.querySelector('.primary-score').textContent = `${score.score}/10`;
          dimension.querySelector('.primary-score-label').textContent = '开发测试分数';
          dimension.classList.remove('pending', 'pass', 'fail');
          dimension.classList.add(score.score >= 8 ? 'pass' : 'fail');
        }
        card.querySelector('.development-score-value').textContent =
          `${score.score}/10 · ${score.rationale || 'No rationale supplied'} · ${e.at} · HEAD ${e.revision} · event ${e.event_id} · server PID ${e.server_identity?.server_pid ?? 'unknown'} · evidence ${(e.evidence || []).join(', ') || 'none supplied'}`;
      });
    });
    const counts = {formal: 0, development: 0, historical: 0, pending: 0};
    document.querySelectorAll('[data-coverage-segment]').forEach(row => {
      row.querySelectorAll('[data-coverage-category]').forEach(cell => {
        const event = latestScores.get(row.dataset.coverageSegment + '\0' + cell.dataset.coverageCategory);
        if (cell.dataset.formalScored !== 'true' && event) {
          cell.textContent = `${event.development_score.score} · 开发`;
          cell.dataset.scoreSource = 'development';
          cell.removeAttribute('title');
        }
        counts[cell.dataset.scoreSource]++;
      });
    });
    const coverageSummary = document.querySelector('[data-coverage-summary]');
    if (coverageSummary) coverageSummary.textContent = `正式 ${counts.formal} 项 · 开发 ${counts.development} 项 · 仅历史 ${counts.historical} 项 · 待评 ${counts.pending} 项`;
    for (const e of events) {
      if (seen.has(e.event_id)) continue;
      const row = document.createElement('li'); row.dataset.eventId = e.event_id;
      row.className = e.kind;
      row.append(node('b', e.at + ' · ' + labels[e.kind] + ' · ' + e.summary), node('p', String(e.result)));
      const evidence = document.createElement('p'); evidence.className = 'evidence-links';
      // A live ledger update does not re-read or re-hash historical files.
      // Avoid producing a potentially broken/stale link until milestone export
      // verifies it; the original path remains visible as plain text.
      for (const path of e.evidence || []) {
        evidence.append(node('span', '证据待批量核验：' + path, 'evidence-pending'));
      }
      row.append(evidence, node('small', e.work_id + ' · ' + e.segment_id + ' · ' + e.revision.slice(0, 8)));
      if (e.kind === 'complete') row.append(node('small', '确认事件：' + e.related_event_ids.join('、')));
      list.append(row); seen.add(e.event_id);
    }
    document.getElementById('progress-empty').hidden = list.children.length > 0;
  }
  let loading = false;
  function refresh() {
    if (loading) return;
    loading = true;
    const script = document.createElement('script');
    script.src = 'live-progress.js?t=' + Date.now();
    script.onload = () => { update(); script.remove(); loading = false; };
    script.onerror = () => { script.remove(); loading = false; };
    document.body.append(script);
  }
  update(); refresh(); setInterval(refresh, 1000);
})();
