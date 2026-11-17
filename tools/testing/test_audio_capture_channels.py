"""Verify independent channel files and silence handling without starting Godot."""
import array
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from audio_watch import find_ffmpeg
from mainline_metrics import audio_score, analyze_background

ROOT = Path(__file__).resolve().parents[2]


class AudioChannelTests(unittest.TestCase):
    @unittest.skipUnless(find_ffmpeg(), "FFmpeg unavailable")
    def test_parallel_channel_files_and_silence(self):
        runtime = ROOT / '.runtime'
        runtime.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=runtime) as temporary:
            path = Path(temporary)
            rate = 44100
            tone = array.array('f', (0.1 * math.sin(2 * math.pi * 440 * i / rate)
                                     for i in range(rate) for _ in range(2)))
            silence = array.array('f', [0.0]) * (rate * 2)
            processes = []
            for stem, samples, output in [('mix', silence, 'audio'), ('background-music', tone, 'background-music')]:
                pcm = path / (stem + '.f32le')
                pcm.write_bytes(samples.tobytes())
                stop = path / (stem + '.stop')
                stop.touch()
                processes.append(subprocess.Popen([sys.executable, str(ROOT / 'tools/testing/audio_watch.py'),
                    '--pcm', str(pcm), '--rate', str(rate), '--out', str(path / (output + '.json')),
                    '--stop', str(stop), '--owner', '0'], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE))
            for process in processes:
                _, stderr = process.communicate(timeout=40)
                self.assertEqual(process.returncode, 0, stderr.decode(errors='replace'))
            silent = json.loads((path / 'audio.json').read_text())
            music = json.loads((path / 'background-music.json').read_text())
            self.assertFalse(silent['signal_present'])
            self.assertIsNone(audio_score(silent)[0])
            self.assertTrue(music['signal_present'])
            for filename in ('mix.wav', 'background-music.wav', 'audio-ffmpeg.log', 'background-music-ffmpeg.log'):
                self.assertTrue((path / filename).is_file(), filename)
            self.assertNotEqual((path / 'mix.wav').read_bytes(), (path / 'background-music.wav').read_bytes())
            bus = {'volume_db': -6.0, 'muted': False, 'bypass': False, 'capture_active': True, 'send': 'Master', 'other_effects': []}
            master = {'volume_db': 0.0, 'muted': False, 'bypass': False, 'capture_active': True, 'other_effects': []}
            metadata = {'background_bus_inventory': ['Music']}
            summary = {'audio_route': {'stable': True, 'snapshot': {'any_solo': False, 'buses': {'Master': master, 'Music': bus}}},
                       'background_audio': {'Music': {'worker_pid': 1, 'discarded_frames': 0, 'start_offset_s': 0.0, 'writer': {'error': 0, 'bytes_queued': 0, 'bytes_written': (path / 'background-music.f32le').stat().st_size}}}}
            background = analyze_background(path, 'scene', [[0, 1]], rate, find_ffmpeg(), metadata, summary)
            self.assertTrue(background['complete'], background)
            self.assertTrue(background['signal_present'])
            self.assertAlmostEqual(background['peak_upper_bound_dbtp'], -26.0, delta=0.5)
            mix = {'status': 'complete', 'signal_present': True, 'integrated_lufs': -25, 'true_peak_dbtp': -10}
            self.assertEqual(audio_score(mix, background)[0], 8)
            summary['audio_route']['stable'] = False
            self.assertFalse(analyze_background(path, 'scene', [[0, 1]], rate, find_ffmpeg(), metadata, summary)['complete'])
            summary['audio_route']['stable'] = True
            summary['background_audio']['Music']['discarded_frames'] = 1
            self.assertFalse(analyze_background(path, 'scene', [[0, 1]], rate, find_ffmpeg(), metadata, summary)['complete'])
            summary['background_audio']['Music']['discarded_frames'] = 0
            (path / 'background-music.f32le').write_bytes(silence.tobytes())
            quiet = analyze_background(path, 'scene', [[0, 1]], rate, find_ffmpeg(), metadata, summary)
            self.assertTrue(quiet['complete'])
            self.assertFalse(quiet['signal_present'])
            self.assertIsNone(audio_score(mix, quiet)[0])



if __name__ == '__main__':
    unittest.main()
