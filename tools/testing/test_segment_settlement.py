"""Session settlement provenance, missing-measurement, and coverage checks."""
import hashlib
import json
from pathlib import Path
import tempfile
import sys
import subprocess
import unittest
from unittest.mock import patch

import yaml
import segment_settlement as settlement


class SegmentSettlementTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=settlement.ROOT / '.runtime')
        self.addCleanup(self.temp.cleanup)
        self.root = settlement.ROOT
        self.base = Path(self.temp.name)
        self.directory = self.base / 'run-4321'
        self.directory.mkdir()
        self.pid, self.sid = 4321, 'session-1'
        self.revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=self.root, text=True).strip()
        self.identity = dict(settlement.provenance.project_identity(self.root), process_id=self.pid)
        self.plan_path = self.base / 'plan.json'
        self.ready_path = self.base / 'ready.json'
        self.scenario = self.base / 'scenario.json'
        self.ref = self.base / 'reference.png'
        self.provenance = self.base / 'provenance.json'
        self.scenario.write_text('{}', encoding='utf-8')
        self.ref.write_bytes(b'reference')
        self.provenance.write_text('{}', encoding='utf-8')
        self._json(self.ready_path, {'test_id':'test-1', 'observer':'blind-player', 'ready':True, 'canonical_unseen':True})
        self.plan = {'schema_version':1, 'test_id':'test-1', 'revision':self.revision, 'collection_mode':'simultaneous',
                     'entry_mode':'segment', 'segment_id':'wake', 'max_fps':60, 'max_hosts':3,
                     'blind_observer':{'identity':'blind-player', 'canonical_unseen':True, 'ready_receipt':str(self.ready_path)},
                     'channels':{c:{'collector':'live', 'assessor':'blind-player', 'method':'recorded'} for c in settlement.CATEGORIES},
                     'cases':[{'id':'case-a', 'segment_id':'wake', 'scenario_path':str(self.scenario),
                               'scenario_sha256':settlement._hash(self.scenario),
                               'reference':{'path':str(self.ref), 'sha256':settlement._hash(self.ref), 'provenance':str(self.provenance)}}]}
        self._json(self.plan_path, self.plan)
        self.plan_hash = settlement._hash(self.plan_path)
        self.on_path, self.close_path = self.base/'on.json', self.base/'close.json'
        self.metrics_path, self.assessment_path = self.directory/'segment-metrics.json', self.directory/'assessment.json'
        server = dict(settlement.provenance.project_identity(self.root), server_pid=123, server_path=str(self.root/'mcp/game/server.py'))
        self.on = {'session_id':self.sid, 'assessment_test_id':'test-1', 'source_identity':self.identity,
                   'server_identity':server, 'metrics_directory':str(self.directory), 'scenario_ready':True,
                   'scene':'res://mcp/game/SegmentEntry.tscn', 'assessment_case_index':0, 'assessment_case_count':1}
        self.close = {'session_id':self.sid, 'closed':True, 'graceful_exit':True, 'metrics_status':'complete',
                      'source_identity':self.identity, 'server_identity':server, 'metrics_summary_path':str(self.metrics_path)}
        self._json(self.on_path, {'tool':'on', 'is_error':False, 'data':self.on})
        self._json(self.close_path, {'tool':'close', 'is_error':False, 'data':self.close})
        self.timeline = self.directory/'timeline.yaml'
        metadata = {'source_identity':self.identity, 'test_id':'test-1', 'revision':self.revision,
                    'collection_mode':'simultaneous', 'assessment_plan':str(self.plan_path),
                    'assessment_plan_sha256':self.plan_hash, 'entry':'scenario', 'scenario_path':str(self.scenario)}
        self.timeline.write_text(yaml.safe_dump({'metadata':metadata, 'timeline':[], 'summary':{'frames':100, 'audio_writer':{'error':0, 'bytes_queued':0, 'bytes_written':5}, 'audio_discarded_frames':0}}), encoding='utf-8')
        self.frame_csv = self.directory/'frames.csv'
        self.frame_csv.write_text('frame,elapsed_s,node,frame_ms\n1,10,wake/R05,16\n', encoding='utf-8')
        self._json(self.directory/'audio.json', {'status':'complete', 'signal_present':True})
        (self.directory/'mix.f32le').write_bytes(b'audio')
        (self.directory/'segment-wake-mix-audio.log').write_text('analyzer output', encoding='utf-8')
        (self.directory/'visible-text-changes.jsonl').write_text('{}', encoding='utf-8')
        concurrency = {'host_pid':self.pid, 'sampler_stopped':True, 'sample_count':2, 'peak_observed_godot_processes':2}
        self._json(self.directory/'concurrency-observation.json', concurrency)
        self.metrics = {'schema_version':1, 'finalized':True, 'measurement_context':'rendered_runtime',
                        'source_identity':self.identity, 'source_directory':str(self.directory), 'entry':'scenario',
                        'scenario_path':str(self.scenario), 'test_id':'test-1', 'assessment_revision':self.revision,
                        'source_sha256':{'timeline.yaml':settlement._hash(self.timeline), 'frames.csv':settlement._hash(self.frame_csv),
                                         'visible-text-changes.jsonl':settlement._hash(self.directory/'visible-text-changes.jsonl')},
                        'concurrency_observation':concurrency,
                        'segments':{'wake':{'intervals_s':[[0,10]], 'measured_scores':[8,8,None,8,None,None,None],
                                            'steady':{'frame_samples':100, 'spikes_over_33_3_ms':0},
                                            'text_score_reason':'Visible English prompt met limits.', 'visible_text':{'score':8},
                                            'audio':{'status':'complete','signal_present':True,'integrated_lufs':-25,'true_peak_dbtp':-24},
                                            'audio_score_reason':'Loudness below thresholds.'}}}
        self._json(self.metrics_path, self.metrics)
        self.notes = self.directory/'blind-observations.jsonl'
        note = {'schema_version':1, 'kind':'event', 'text':'A figure stands up.', 'test_id':'test-1',
                'revision':self.revision, 'session_id':self.sid, 'host_pid':self.pid, 'observer':'blind-player',
                'assessment_plan_sha256':self.plan_hash, 'case_id':'case-a', 'case_index':0, 'segment_id':'wake', 'monitor_elapsed_s':3.0}
        self.notes.write_text(json.dumps(note)+'\n', encoding='utf-8')
        dynamic = self.directory/'dynamic'
        dynamic.mkdir()
        self.image = dynamic/'0000001.png'
        self.image.write_bytes(b'frame')
        self.manifest = dynamic/'frames.jsonl'
        self.manifest.write_text(json.dumps({'type':'frame', 'path':str(self.image), 'elapsed_s':3.0, 'error':0,
                                              'sha256':settlement._hash(self.image)})+'\n'+
                                 json.dumps({'type':'summary', 'frames':1, 'skipped_samples':0, 'write_failures':0})+'\n', encoding='utf-8')
        self.assessment = {'schema_version':1, 'test_id':'test-1', 'revision':self.revision,
                           'session_id':self.sid, 'host_pid':self.pid, 'segment_id':'wake',
                           'assessment_plan_sha256':self.plan_hash,
                           'case_outcomes':{'case-a':{'status':'completed', 'reason':'Reached the next scene.', 'start_s':0, 'end_s':9}},
                           'reviews':{c:{'assessor':'blind-player', 'score':8, 'reason':'Observed and reviewed.',
                                          'case_evidence':{'case-a':[str(self.notes)]}} for c in settlement.SUBJECTIVE}}
        self.assessment['reviews']['action_sfx_integrity']['case_evidence']['case-a'].append(str(self.directory/'mix.f32le'))
        self.assessment['reviews']['aesthetic_similarity']['case_evidence']['case-a'] = [str(self.image), str(self.ref)]
        self._json(self.assessment_path, self.assessment)

    def _json(self, path, data):
        path.write_text(json.dumps(data), encoding='utf-8')

    def prepare(self):
        return settlement.prepare(self.plan_path, self.on_path, self.close_path, self.assessment_path,
                                  root=self.root, revision=self.revision)

    def make_recovery(self):
        self.close.update(session_id=self.sid, metrics_status='error', metrics_error='FFmpeg analysis timed out after 180 seconds')
        self.close.pop('metrics_summary_path', None)
        self._json(self.close_path, {'tool':'close', 'is_error':False, 'data':self.close})
        (self.directory / 'background-music.f32le').write_bytes(b'background')
        (self.directory / 'background-music.json').write_text('{}', encoding='utf-8')
        names = ['mix.f32le', 'background-music.f32le', 'audio.json', 'background-music.json', 'concurrency-observation.json']
        self.metrics['recovery'] = {'original_close_receipt': str(self.close_path),
            'original_close_receipt_sha256': settlement._hash(self.close_path),
            'analysis_script_sha256': settlement._hash(self.root/'tools/testing/mainline_metrics.py'),
            'source_sha256': {name:settlement._hash(self.directory/name) for name in names}}
        self.recovered_path = self.directory / 'segment-metrics-recovered.json'
        self._json(self.recovered_path, self.metrics)

    def recover(self):
        with patch('segment_settlement.summarize', return_value=self.metrics):
            return settlement.prepare(self.plan_path, self.on_path, self.close_path, self.assessment_path,
                                      root=self.root, revision=self.revision, recovered_metrics=self.recovered_path)

    def test_explicit_recovery_preserves_original_error_and_marks_incomplete(self):
        self.make_recovery()
        original = self.close_path.read_bytes()
        with self.assertRaisesRegex(ValueError, 'complete metrics'):
            self.prepare()
        result = self.recover()
        self.assertEqual(result['status'], 'incomplete')
        self.assertEqual(list(result['scores'].values()), [8] * 7)
        self.assertIn('timed out after 180 seconds', result['reasons']['audio_loudness'])
        self.assertEqual(self.close_path.read_bytes(), original)
        self.assertIn(self.recovered_path.relative_to(self.root).as_posix(), result['evidence'])
        self.assertIn((self.directory/'mix.f32le').relative_to(self.root).as_posix(), result['evidence'])

    def test_recovery_rejects_changed_receipt_sources_and_analysis_script(self):
        self.make_recovery()
        self.close_path.write_text(self.close_path.read_text(encoding='utf-8') + ' ', encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'original close receipt'):
            self.recover()
        self.make_recovery()
        (self.directory/'mix.f32le').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'Recovery source hash'):
            self.recover()
        (self.directory/'mix.f32le').write_bytes(b'audio')
        self.metrics['recovery']['analysis_script_sha256'] = 'wrong'
        self._json(self.recovered_path, self.metrics)
        with self.assertRaisesRegex(ValueError, 'analysis script hash'):
            self.recover()

    def test_recovery_rejects_edited_metrics_despite_matching_source_hashes(self):
        self.make_recovery()
        forged = json.loads(self.recovered_path.read_text(encoding='utf-8'))
        forged['segments']['wake']['measured_scores'][0] = 10
        self._json(self.recovered_path, forged)
        with self.assertRaisesRegex(ValueError, 'do not match reanalysis: segments'):
            self.recover()

    def test_recovery_requires_timeout_same_session_and_committed_revision(self):
        self.make_recovery()
        self.close['session_id'] = 'other-session'
        self._json(self.close_path, {'tool':'close', 'is_error':False, 'data':self.close})
        with self.assertRaisesRegex(ValueError, 'receipts'):
            self.recover()
        self.make_recovery()
        self.close['session_id'] = self.sid
        self.close['metrics_error'] = 'Another postprocessing error'
        self._json(self.close_path, {'tool':'close', 'is_error':False, 'data':self.close})
        with self.assertRaisesRegex(ValueError, 'FFmpeg timeout'):
            self.recover()
        self.make_recovery()
        with patch('segment_settlement.subprocess.check_output', side_effect=subprocess.CalledProcessError(1, 'git')):
            with self.assertRaisesRegex(ValueError, 'committed ancestor'):
                self.recover()

    def test_seven_scores_and_provenance_are_assembled_from_one_session(self):
        result = self.prepare()
        self.assertEqual(list(result['scores']), list(settlement.CATEGORIES))
        self.assertEqual(list(result['scores'].values()), [8] * 7)
        self.assertEqual(result['trajectory_id'], 'wake')
        self.assertEqual(result['status'], 'complete')
        self.assertIn('2', result['reasons']['fluidity'])
        self.assertIn(self.notes.relative_to(self.root).as_posix(), result['evidence'])

    def test_missing_settlement_publishes_seven_numeric_scores_to_static_and_live_report(self):
        self.assessment['reviews']['narrative_flow'].update(score=None, reason='Observer missed the transition.')
        self._json(self.assessment_path, self.assessment)
        batch = self.prepare()
        self.assertIsNone(batch['scores']['narrative_flow'])  # Internal missing-data sentinel.
        sys.path.insert(0, str(self.root / 'mcp' / 'review'))
        self.addCleanup(sys.path.remove, str(self.root / 'mcp' / 'review'))
        from core import Store
        import test_results
        with tempfile.TemporaryDirectory(dir=self.root / '.runtime' / 'review-tests') as sandbox:
            store = Store(test_sandbox=sandbox)
            event = store.add_scores(**batch)['event']
            self.assertEqual(event['test_result']['scores']['narrative_flow'], 0)
            self.assertEqual(event['test_result']['status'], 'incomplete')
            self.assertEqual(event['test_result']['provisional_categories'], ['narrative_flow'])
            self.assertTrue(all(isinstance(v, (int, float)) for v in event['test_result']['scores'].values()))
            result = test_results.collect([], [event])[0]
            card = test_results.card(dict(id='wake', label='Opening'), result, None, lambda path, label, page: label, lambda value: self.root / value, None)
            self.assertIn('0/10 (暂定·缺证据)', card)
            self.assertIn('Observer missed the transition', card)
            self.assertIn('已测 · 测试未完成', card)
            live = store.live.read_text(encoding='utf-8')
            self.assertIn('provisional_categories', live)
            self.assertIn('Observer missed the transition', live)

    def test_changed_source_and_wrong_revision_are_rejected(self):
        self.frame_csv.write_text('changed', encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'changed after settlement'):
            self.prepare()
        self.metrics['source_sha256']['frames.csv'] = settlement._hash(self.frame_csv)
        self.metrics['assessment_revision'] = 'different-revision'
        self._json(self.metrics_path, self.metrics)
        with self.assertRaisesRegex(ValueError, 'source revision'):
            self.prepare()

    def test_wrong_session_and_other_run_evidence_are_rejected(self):
        self.assessment['session_id'] = 'other-session'
        self._json(self.assessment_path, self.assessment)
        with self.assertRaisesRegex(ValueError, 'Assessment identity'):
            self.prepare()
        self.assessment['session_id'] = self.sid
        other = self.base/'different-test.json'
        self._json(other, {})
        self.assessment['reviews']['narrative_flow']['case_evidence']['case-a'] = [str(other)]
        self._json(self.assessment_path, self.assessment)
        with self.assertRaisesRegex(ValueError, 'another session'):
            self.prepare()

    def test_incomplete_case_preserves_observed_failure_and_missing_reasons(self):
        self.assessment['case_outcomes']['case-a'].update(status='stalled', reason='Door did not respond.')
        self.assessment['reviews']['action_sfx_integrity'].update(score=6, reason='Character visibly clips.')
        self.assessment['reviews']['narrative_flow'].update(score=None, reason='The scene stalled before transition.')
        self._json(self.assessment_path, self.assessment)
        result = self.prepare()
        self.assertEqual(result['status'], 'incomplete')
        self.assertIsNone(result['scores']['fluidity'])
        self.assertEqual(result['scores']['action_sfx_integrity'], 6)
        self.assertIsNone(result['scores']['narrative_flow'])
        self.assertEqual(result['reasons']['narrative_flow'], 'The scene stalled before transition.')
        self.assertIn('Door did not respond', result['reasons']['text_density'])

    def test_late_blind_notes_remain_recorded_but_do_not_count_as_case_observation(self):
        first = json.loads(self.notes.read_text(encoding='utf-8').strip())
        late = dict(first, monitor_elapsed_s=9.5, text='Retrospective note after the case ended.')
        self.notes.write_text(json.dumps(first)+'\n'+json.dumps(late)+'\n', encoding='utf-8')
        plan = settlement.validate_plan(self.plan_path, self.root, revision=self.revision)
        rows = settlement._blind_rows(self.notes, plan, self.sid, self.pid, self.assessment['case_outcomes'], [[0,10]])
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['monitor_elapsed_s'], 3.0)
        late['monitor_elapsed_s'] = 11
        self.notes.write_text(json.dumps(late)+'\n', encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'timeline'):
            settlement._blind_rows(self.notes, plan, self.sid, self.pid, self.assessment['case_outcomes'], [[0,10]])

    def test_blind_scores_require_timed_notes(self):
        self.assessment['reviews']['blind_narrative_match']['case_evidence']['case-a'] = [str(self.image)]
        self.notes.write_text('', encoding='utf-8')
        self.assessment['reviews']['action_sfx_integrity']['case_evidence']['case-a'] = [str(self.image), str(self.directory/'mix.f32le')]
        self._json(self.assessment_path, self.assessment)
        with self.assertRaisesRegex(ValueError, 'live blind notes'):
            self.prepare()

    def test_aesthetic_frame_hash_and_reference_are_checked(self):
        self.image.write_bytes(b'altered')
        with self.assertRaisesRegex(ValueError, 'capture hash'):
            self.prepare()

    def test_explicit_missing_subjective_reason_is_preserved(self):
        self.assessment['reviews']['narrative_flow'].update(score=None, reason='Observer missed the transition.')
        self._json(self.assessment_path, self.assessment)
        result = self.prepare()
        self.assertIsNone(result['scores']['narrative_flow'])
        self.assertEqual(result['reasons']['narrative_flow'], 'Observer missed the transition.')

    def test_mismatched_objective_scores_are_rejected(self):
        self.metrics['segments']['wake']['measured_scores'][0] = 6
        self._json(self.metrics_path, self.metrics)
        with self.assertRaisesRegex(ValueError, 'Fluidity score conflicts'):
            self.prepare()
        self.metrics['segments']['wake']['measured_scores'][0] = 8
        self.metrics['segments']['wake']['measured_scores'][3] = 6
        self._json(self.metrics_path, self.metrics)
        with self.assertRaisesRegex(ValueError, 'Audio score conflicts'):
            self.prepare()

    def test_interrupted_frame_capture_suppresses_complete_passes(self):
        rows = self.manifest.read_text(encoding='utf-8').splitlines()
        summary = json.loads(rows[-1])
        summary['skipped_samples'] = 1
        self.manifest.write_text(rows[0] + '\n' + json.dumps(summary) + '\n', encoding='utf-8')
        result = self.prepare()
        self.assertTrue(all(value is None for value in result['scores'].values()))
        self.assertIn('skipped samples', result['reasons']['fluidity'])

    def test_unstarted_case_retains_specific_blocker(self):
        plan = {'cases':[{'id':'case-a'}, {'id':'case-b'}]}
        windows = {'case-a':{'status':'stalled', 'reason':'Door stuck.', 'start_s':0, 'end_s':4},
                   'case-b':{'status':'not_started', 'reason':'The previous case stalled.', 'start_s':None, 'end_s':None}}
        missing = settlement._case_windows(windows, plan, [[0, 8]])
        self.assertEqual(len(missing), 2)
        self.assertIn('previous case stalled', missing[1])

    def test_corrupt_or_incomplete_audio_is_rejected(self):
        (self.directory/'mix.f32le').write_bytes(b'other size')
        with self.assertRaisesRegex(ValueError, 'Audio capture was incomplete'):
            self.prepare()

    def test_action_pass_requires_same_session_audio(self):
        self.assessment['reviews']['action_sfx_integrity']['case_evidence']['case-a'] = [str(self.notes)]
        self._json(self.assessment_path, self.assessment)
        with self.assertRaisesRegex(ValueError, 'same-session audio'):
            self.prepare()

    def test_wrong_assessor_is_rejected(self):
        self.assessment['reviews']['narrative_flow']['assessor'] = 'other'
        self._json(self.assessment_path, self.assessment)
        with self.assertRaisesRegex(ValueError, 'configured assessor'):
            self.prepare()

    def test_missing_load_observation_does_not_certify_fluidity_pass(self):
        self.metrics.pop('concurrency_observation')
        self._json(self.metrics_path, self.metrics)
        result = self.prepare()
        self.assertIsNone(result['scores']['fluidity'])
        self.assertIn('Concurrent load observation unavailable', result['reasons']['fluidity'])


if __name__ == '__main__':
    unittest.main()
