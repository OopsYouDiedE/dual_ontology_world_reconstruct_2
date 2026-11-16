"""Record the real-time opening, retain timestamps, then encode review videos."""
from __future__ import annotations
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'mcp'))
import capture_provenance as provenance


def dump(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')


def encode(folder, sequence):
    ffmpeg = Path.home() / 'Documents/ffmpeg/bin/ffmpeg.exe'
    if not ffmpeg.is_file():
        raise FileNotFoundError('Configured FFmpeg is unavailable')
    frames = sequence['video_frames']
    for frame in frames:
        if frame.get('write_error') != 0 or not Path(frame['path']).is_file():
            raise ValueError('Missing video frame: ' + frame['path'])
    gaps = [b['time_s'] - a['time_s'] for a, b in zip(frames, frames[1:])]
    concat = folder / 'video.ffconcat'
    rows = ['ffconcat version 1.0']
    for i, frame in enumerate(frames):
        # All generated names are controlled, relative ASCII paths.
        rows += [f"file 'video/{i:06d}.jpg'", f"duration {gaps[i] if i < len(gaps) else 1/12:.6f}"]
    rows += [f"file 'video/{len(frames)-1:06d}.jpg'"]
    concat.write_text('\n'.join(rows) + '\n', encoding='utf-8')
    command = [str(ffmpeg), '-hide_banner', '-y', '-f', 'concat', '-safe', '1', '-i', str(concat),
               '-f', 'f32le', '-ar', str(int(sequence['audio_sample_rate'])), '-ac', '2',
               '-i', str(folder/'monitor/mix.f32le'), '-vf', 'fps=12', '-c:v', 'libx264',
               '-preset', 'veryfast', '-crf', '20', '-pix_fmt', 'yuv420p', '-c:a', 'aac',
               '-b:a', '160k', '-shortest', '-movflags', '+faststart', str(folder/'complete.mp4')]
    with (folder/'encoding.log').open('w', encoding='utf-8') as log:
        subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    boundary = next(e['time_s'] for e in sequence['events'] if e.get('state') == 'corridor:fadeout')
    clips = []
    for segment, start, end in [('wake', 0, boundary), ('corridor', boundary, frames[-1]['time_s'])]:
        target = folder / (segment + '.mp4')
        command = [str(ffmpeg), '-hide_banner', '-y', '-i', str(folder/'complete.mp4'), '-ss', str(start),
                   '-t', str(end-start), '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20',
                   '-c:a', 'aac', '-movflags', '+faststart', str(target)]
        with (folder/(segment+'-encoding.log')).open('w', encoding='utf-8') as log:
            subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
        clips.append({'segment_id':segment, 'path':str(target.relative_to(ROOT)).replace('\\','/'),
                      'start_s':start, 'end_s':end, 'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
    result = {'continuous':True, 'original_subtitles':True, 'speed':sequence['engine_time_scale'],
              'video_frame_count':len(frames), 'max_frame_gap_s':max(gaps),
              'gaps_over_250ms':sum(g > .25 for g in gaps), 'clips':clips}
    dump(folder/'video-coverage.json', result)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True)
    parser.add_argument('--encode-only', action='store_true')
    args = parser.parse_args()
    provenance.assert_runtime_root(ROOT)
    folder = provenance.project_path(args.output, ROOT)
    if not args.encode_only:
        folder.mkdir(parents=True, exist_ok=False)
        executable = provenance.host_executable(ROOT/'.runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64.exe')
        command = [executable, '--path', str(ROOT), '--script', 'res://tools/test/capture_opening_complete.gd', '--',
                   '--output='+str(folder), '--dv-checkpoint-stop='+str(folder/'interrupt.request')]
        launch = {'project':provenance.project_identity(ROOT), 'command':command, 'acceptance_eligible':False,
                  'revision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
                  'start':datetime.now().astimezone().isoformat(), 'source_sha256':{}}
        for relative in ['tools/test/capture_opening_complete.gd', 'tools/testing/TestStoryHost.gd',
                         'scenes/dual_world/DualWorldMain.gd', 'scenes/dual_world/WakeOpening.gd',
                         'scenes/dual_world/CorridorGathering.gd', 'scenes/components/testing/StoryCheckpoint.gd']:
            launch['source_sha256'][relative] = hashlib.sha256((ROOT/relative).read_bytes()).hexdigest()
        with (folder/'godot.log').open('w',encoding='utf-8') as log:
            proc = subprocess.Popen(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
            launch['host_pid'] = proc.pid
            dump(folder/'launch.json',launch)
            print('Recording PID',proc.pid,flush=True)
            try:
                launch['exit_code'] = proc.wait(timeout=330)
            except (subprocess.TimeoutExpired,KeyboardInterrupt):
                (folder/'interrupt.request').write_text(str(proc.pid),encoding='utf-8')
                try: launch['exit_code'] = proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    proc.terminate()
                    launch['exit_code'] = proc.wait(timeout=10)
        launch['end'] = datetime.now().astimezone().isoformat()
        dump(folder/'launch.json',launch)
        if launch['exit_code'] != 0:
            raise RuntimeError('Recording failed; inspect godot.log and latest.snapshot.json')
    launch = json.loads((folder/'launch.json').read_text(encoding='utf-8'))
    sequence = json.loads((folder/'sequence.json').read_text(encoding='utf-8'))
    provenance.validate_source(sequence['source_identity'],launch['project'],pid=launch['host_pid'])
    assert sequence['skip_subtitles'] is False and sequence['engine_time_scale'] == 1.0
    assert not sequence['failure']
    print(json.dumps(encode(folder,sequence),ensure_ascii=False),flush=True)


if __name__ == '__main__':
    main()
