(() => {
  'use strict';
  const runs = document.querySelector('#runs');
  const state = document.querySelector('#state');
  const labels = {room: '单房间', interaction: '物品／人物交互', ui: 'UI', design: '可视化设计工具', story: '剧情节点',
    starting: '启动中', running: '测试中', passed: '通过', failed: '失败', incomplete: '未完成', blocked: '受阻',
    abandoned: '会话中断', pass: '通过', fail: '失败', not_applicable: '不适用'};
  const fmt = t => new Date(t).toLocaleString('zh-TW', {timeZone: 'Asia/Taipei', hour12: false});
  const el = (tag, text, parent) => {
    const node = document.createElement(tag);
    if (text !== undefined) node.textContent = text;
    if (parent) parent.append(node);
    return node;
  };
  const evidencePath = (item, id, extension) => {
    const match = /^runs\/([a-f0-9]{16})\/frames\/step-[0-9]{4,}(?:-[0-9]{2})?\.(png|wav)$/.exec(item.path);
    return match && match[1] === id && match[2] === extension ? 'focused/' + item.path : null;
  };
  const render = (list) => {
    const existing = new Map(Array.from(runs.children, node => [node.dataset.testId, node]));
    list.forEach((run, index) => {
      const previous = existing.get(run.test_id);
      const signature = JSON.stringify(run);
      const node = previous?.signature === signature ? previous : renderRun(run, previous?.open ?? index === 0, signature);
      if (previous && previous !== node) previous.replaceWith(node);
      if (runs.children[index] !== node) runs.insertBefore(node, runs.children[index] || null);
      existing.delete(run.test_id);
    });
    existing.forEach(node => node.remove());
    state.textContent = list.length ? `${list.length} 次测试 · 自动刷新 · 台北时间` : '等待 MCP 写入首条测试记录。';
  };
  function renderRun(run, opened, signature) {
    const card = el('details');
    card.dataset.testId = run.test_id;
    card.signature = signature;
    card.className = 'run';
    card.open = opened;
    const summary = el('summary', `${labels[run.scope]} · ${run.target} · ${labels[run.status] ?? run.status}`, card);
    summary.className = run.status;
    el('p', `${run.tester} · ${fmt(run.started_at)}${run.finished_at ? ' → ' + fmt(run.finished_at) : ''} · ${run.revision.slice(0, 12)}${run.dirty ? ' + 工作区改动' : ''} · ${run.test_id}`, card);
    if (run.entry) el('p', [run.entry.scene, run.entry.room, `Forward+ · PID ${run.entry.host_pid}`].filter(Boolean).join(' · '), card);
    if (run.error) el('p', run.error, card);
    const checks = el('ul', undefined, card);
    Object.entries(run.checks).forEach(([name, guidance]) => {
      const verdict = run.verdicts?.[name];
      const row = el('li', `${name} · ${verdict ? labels[verdict.outcome] : '待提交'} · ${verdict?.reason ?? guidance}`, checks);
      (verdict?.steps ?? []).forEach(id => {
        const link = el('a', ' ' + id, row);
        link.href = '#' + run.test_id + '-' + id;
      });
    });
    const steps = el('ol', undefined, card);
    run.steps.forEach(step => {
      const row = el('li', `${step.id} · ${step.operation.type}${step.room ? ' · ' + step.room : ''} · ${step.note}`, steps);
      row.id = run.test_id + '-' + step.id;
      if (Object.keys(step.observed ?? {}).length) el('details', undefined, row).append(el('summary', '观测状态'), el('pre', JSON.stringify(step.observed, null, 2)));
      if (step.error) el('p', step.error, row);
      if (step.host_errors?.length) el('details', undefined, row).append(el('summary','实机日志'), el('pre',step.host_errors.join('\n')));
      if (step.frames.length) {
        const gallery = el('div', undefined, row);
        gallery.className = 'frame-list';
        step.frames.forEach(frame => {
          const path = evidencePath(frame, run.test_id, 'png');
          if (!path) return;
          const a = el('a', undefined, gallery);
          const label = frame.frame === null ? '定点' : frame.frame === 0 ? '动作前' : `第 ${frame.frame} 帧 · ${Math.round(frame.elapsed_ms)} ms`;
          a.href = path;
          const img = el('img', undefined, a);
          img.src = path;
          img.loading = 'lazy';
          img.alt = label;
          el('span', label, a);
        });
      }
      const audio = step.audio && evidencePath(step.audio, run.test_id, 'wav');
      if (audio) {
        const player = el('audio', undefined, row);
        player.src = audio;
        player.controls = true;
        player.preload = 'none';
      } else if (step.audio_preview) el('p', step.audio_preview.reason, row);
    });
    return card;
  }
  function poll() {
    const script = document.createElement('script');
    script.src = 'focused/live.js?t=' + Date.now();
    function next() { script.remove(); setTimeout(poll, 2000); }
    script.onload = () => { try { render(window.FOCUSED_TESTS || []); } finally { next(); } };
    script.onerror = next;
    document.head.append(script);
  }
  poll();
})();
