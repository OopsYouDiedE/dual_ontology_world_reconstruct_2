(() => {
  'use strict';
  const dialog = document.getElementById('image-view');
  document.querySelectorAll('a.zoom').forEach(a => a.addEventListener('click', e => {
    e.preventDefault(); dialog.querySelector('img').src = a.href; dialog.showModal();
  }));
  dialog?.querySelector('button').addEventListener('click', () => dialog.close());
  dialog?.addEventListener('click', e => { if (e.target === dialog) dialog.close(); });
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
  update(); refresh(); setInterval(refresh, 5000);
})();
