"""Evidence-bound segment video export tests using synthetic recorder data."""
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
import zlib

import yaml
import segment_video as video


def png(rgb):
    def chunk(name, data):
        return struct.pack('>I', len(data)) + name + data + struct.pack('>I', zlib.crc32(name + data) & 0xffffffff)
    raw = b''.join(b'\x00' + bytes(rgb) * 4 for _ in range(4))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 4, 4, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')


class SegmentVideoTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=video.ROOT / '.runtime')
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.run = self.folder / 'run-123'
        self.dynamic = self.run / 'dynamic'
        self.dynamic.mkdir(parents=True)
        self.plan = self.folder / 'plan.json'
        self.plan.write_text(json.dumps({'test_id': 't1', 'revision': 'abcdef0', 'segment_id': 'wake'}))
        self.pcm = self.run / 'mix.f32le'
        self.pcm.write_bytes(struct.pack('<f', .1) * 8000 * 2 * 3)
        self.audio = self.run / 'audio.json'
        self.audio.write_text(json.dumps({'status': 'complete', 'sample_rate': 8000}))
        identity = dict(video.provenance.project_identity(video.ROOT), process_id=123)
        self.timeline = self.run / 'timeline.yaml'
        self.doc = {'metadata': {'test_id': 't1', 'revision': 'abcdef0', 'assessment_plan': str(self.plan),
                                 'assessment_plan_sha256': video.digest(self.plan), 'source_identity': identity},
                    'summary': {'audio_writer': {'error': 0, 'bytes_queued': 0, 'bytes_written': self.pcm.stat().st_size},
                                'audio_discarded_frames': 0, 'master_start_offset_s': .05, 'frames': 60}}
        self.timeline.write_text(yaml.safe_dump(self.doc))
        (self.run / 'frames.csv').write_text('frame,elapsed_s\n60,1.10\n')
        self.manifest = self.dynamic / 'frames.jsonl'
        self.rows = [{'type': 'configuration', 'timebase': 'RuntimeMonitor elapsed_s', 'fixed_timestep': False, 'sample_hz': 10}]
        for i, (stamp, colour) in enumerate(((.20, (255,0,0)), (.38, (0,255,0)), (.93, (0,0,255))), 1):
            frame = self.dynamic / f'{i:07}.png'
            frame.write_bytes(png(colour))
            self.rows.append({'type': 'frame', 'sequence': i, 'elapsed_s': stamp, 'scene_node': 'wake/room',
                              'path': str(frame), 'sha256': video.digest(frame), 'error': 0})
        self.rows.append({'type': 'summary', 'frames': 3, 'skipped_samples': 0, 'write_failures': 0})
        self.write_manifest()

    def write_manifest(self):
        self.manifest.write_text(''.join(json.dumps(row) + '\n' for row in self.rows))

    def test_validates_alignment_and_true_variable_intervals(self):
        data = video.inspect_recording(self.run, 'wake')
        self.assertAlmostEqual(data['audio_start_s'], .25)
        self.assertAlmostEqual(data['duration_s'], .90)
        self.assertEqual([f['elapsed_s'] for f in data['frames']], [.2, .38, .93])
        self.assertIn('performance telemetry', data['sampling']['scope'])

    def test_rejects_capture_loss_and_changed_frame(self):
        self.rows[-1]['skipped_samples'] = 1
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, 'missing samples'):
            video.inspect_recording(self.run, 'wake')
        self.rows[-1]['skipped_samples'] = 0
        self.write_manifest()
        (self.dynamic / '0000001.png').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'frame'):
            video.inspect_recording(self.run, 'wake')

    def test_rejects_audio_loss_or_insufficient_coverage(self):
        self.doc['summary']['audio_discarded_frames'] = 1
        self.timeline.write_text(yaml.safe_dump(self.doc))
        with self.assertRaisesRegex(ValueError, 'Audio capture'):
            video.inspect_recording(self.run, 'wake')
        self.doc['summary']['audio_discarded_frames'] = 0
        self.doc['summary']['master_start_offset_s'] = 5
        self.timeline.write_text(yaml.safe_dump(self.doc))
        with self.assertRaisesRegex(ValueError, 'does not cover'):
            video.inspect_recording(self.run, 'wake')

    def test_rejects_plan_mismatch_and_out_of_order_frames(self):
        self.plan.write_text('{}')
        with self.assertRaisesRegex(ValueError, 'plan'):
            video.inspect_recording(self.run, 'wake')
        self.doc['metadata']['assessment_plan_sha256'] = video.digest(self.plan)
        self.plan.write_text(json.dumps({'test_id': 't1', 'revision': 'abcdef0', 'segment_id': 'wake'}))
        self.doc['metadata']['assessment_plan_sha256'] = video.digest(self.plan)
        self.timeline.write_text(yaml.safe_dump(self.doc))
        self.rows[2]['elapsed_s'] = .1
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, 'timestamps'):
            video.inspect_recording(self.run, 'wake')

    @unittest.skipUnless(video.find_ffmpeg(), 'FFmpeg unavailable')
    def test_playable_mp4_uses_recorded_timestamps_and_does_not_overwrite(self):
        output = self.folder / 'review.mp4'
        # The source first turns on at .50 s.  After the .25 s source trim,
        # the audible transition should occur .25 s into the review copy.
        self.pcm.write_bytes(struct.pack('<f', 0.0) * 8000 + struct.pack('<f', .3) * (8000 * 2 * 3 - 8000))
        info = video.export_video(self.run, 'wake', output)
        self.assertTrue(output.is_file())
        self.assertEqual(video.digest(output), info['video_sha256'])
        raw = subprocess.run([video.find_ffmpeg(), '-v', 'error', '-i', str(output), '-map', '0:a:0',
                              '-f', 'f32le', '-ac', '2', '-ar', '8000', '-'], capture_output=True, check=True).stdout
        samples = struct.unpack('<' + 'f' * (len(raw) // 4), raw)
        onset = next(index for index in range(0, len(samples), 2) if abs(samples[index]) > .1) / (2 * 8000)
        self.assertAlmostEqual(onset, .25, delta=.04)
        self.assertTrue(output.with_suffix('.mp4.json').is_file())
        self.assertFalse(list(self.dynamic.glob('*.ffconcat')))
        with self.assertRaises(FileExistsError):
            video.export_video(self.run, 'wake', output)
        probe = Path(video.find_ffmpeg()).with_name('ffprobe.exe' if __import__('os').name == 'nt' else 'ffprobe')
        if probe.is_file():
            result = subprocess.run([str(probe), '-v', 'error', '-show_entries', 'stream=codec_type', '-of', 'json', str(output)], capture_output=True, text=True, check=True)
            self.assertEqual({s['codec_type'] for s in json.loads(result.stdout)['streams']}, {'video', 'audio'})
            times = subprocess.run([str(probe), '-v', 'error', '-select_streams', 'v:0', '-show_entries',
                                    'frame=best_effort_timestamp_time', '-of', 'json', str(output)],
                                   capture_output=True, text=True, check=True)
            stamps = [float(item['best_effort_timestamp_time']) for item in json.loads(times.stdout)['frames']]
            self.assertGreaterEqual(len(stamps), 3)
            self.assertAlmostEqual(stamps[0], 0, delta=.003)
            self.assertAlmostEqual(stamps[1], .18, delta=.003)
            self.assertAlmostEqual(stamps[2], .73, delta=.003)


if __name__ == '__main__': unittest.main()
