# First expedition · delivered dialogue and layout acceptance

[2026-11-24 · 478 局新测：首征剧情概率与返营战役路线](../../playtest-20261124/README.md)

## Rebuild the offline atlas

From the repository root:

```powershell
$d = 'docs/production/expedition-01/playtest'
python -B "$d/test_dialogue_atlas.py"
python -B "$d/dialogue_atlas.py" --matrix .runtime/route-matrix/seed31-wtqttmv7 --human .runtime/human_batch/20261124T084832Z-e35b902d --out .runtime/dialogue-atlas
```

Open the resulting `index.html` offline. Change the cohort/approach/profile, search the delivered text, or select zero hits. The XZ trace is decimated (one drawn vertex per five stored path samples); event coordinates and ticks in `hits.csv` retain replay precision. `rates.csv` gives distinct runs hearing a line / all runs in the selected cohort, plus repeat deliveries. `order.csv` audits mutually exclusive door captions and the order of the paired-window caption. It verifies delivery order; game facts and subtitle delivery are distinct. Use the route viewer for other action types.

**Inputs:** use one explicit batch root per cohort, never combine retries from overlapping batches. Death and timeout runs remain in the denominator. The archive here contains 72 fixed runs (60 completed, 12 died) and 6 limited-perception bot runs (all hit the tick limit). Replay `dialogue` events already include thoughts, the player's orders and the page excerpt, distinguished by speaker. `caption` mirrors and HUD feedback are excluded. Dialogue means the game posted a subtitle; the sample is the player's position, not Hale's. The catalog covers literal call sites in Expedition/ArchiveWitness, both textual variants, Hale's speech and stele tables, plus dynamic replies; live text missed by static extraction is retained. Two call sites with identical rendered text share a row. A missing line is a coverage item, not automatically a bug.

**Exposure** is measured for six lines with explicit production spatial predicates. Every stored 12-tick movement sample and subtitle position is checked, independent of story facts, gaze, Hale's arrival, cooldown or an occupied subtitle channel. Brief passages between samples may be missed. The local numerator counts cases with a delivery inside that predicate. Other lines show no exposure denominator. Changing spatial predicates in gameplay requires updating the audit too.

**2026-11-24:** 50 distinct texts, 787 deliveries. Fixed paths heard 20 texts; the six bots heard 10. Door branches were exclusive in all 78 logs, and every paired-door caption followed the window caption. Of five bots entering the door radius, four passed without either door line: `cautious-31`, `cautious-113`, `direct-31`, `direct-113`. Investigate the runtime DOOR beat, arrival, fact and subtitle-channel checks there; these historical traces lack a per-predicate rejection reason.

## Related evidence

- [Paired portal experiment, results and reproduction](structure/README.md)
- [Stair surfaces, capsule and transfer audit](stair-collision-audit.md)
- [Human-labelled layout preference estimator](preference/README.md)

## 生成与筛选设计候选

- [地图总复杂度、全图/单路线决策预算与联合验收](complexity/README.md)
- [三维杂物堆放参数及真实胶囊通行测试](clutter/README.md)
- [大规模对话采样与可续跑 SQLite](dialogue_campaign.md)
