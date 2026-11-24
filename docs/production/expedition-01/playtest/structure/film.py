"""Render the matched Sol entrance edit in an isolated real Godot viewport."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--run', type=Path, default=ROOT/'.runtime/structure-565b9cfbef')
    ap.add_argument('--godot', type=Path, default=ROOT/'.runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64.exe')
    args = ap.parse_args()
    scratch = ROOT/'.runtime'/f'structure-film-{uuid.uuid4().hex[:8]}'
    scratch.mkdir()
    out = ROOT/'.runtime/design-review'
    out.mkdir(exist_ok=True)
    for layout in 'AB':
        report = args.run.resolve()/f'cautious-31-{layout}'/'report.json'
        data = json.loads(report.read_text(encoding='utf-8'))
        if (data['profile'], data['seed'], data['layout']) != ('cautious', 31, layout):
            raise ValueError(f'wrong source report: {report}')
        arm = scratch/layout
        user = arm/'user'
        user.mkdir(parents=True)
        env = dict(os.environ, **dict.fromkeys(('APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME',
                                               'XDG_CONFIG_HOME', 'XDG_CACHE_HOME'), str(user)))
        cmd = [str(args.godot.resolve()), '--path', str(ROOT), '--resolution', '960x540', '--fixed-fps', '30',
               '--rendering-method', 'forward_plus', '--log-file', str(arm/'engine.log'),
               '-s', 'res://' + (HERE/'film.gd').relative_to(ROOT).as_posix(), '--', str(report), str(arm)]
        print(f'Rendering {layout} to {arm}', flush=True)
        subprocess.run(cmd, cwd=ROOT, env=env, check=True, timeout=420)
        frames = sorted(arm.glob('*.png'))
        if [f.name for f in frames] != [f'{i:04}.png' for i in range(360)]:
            raise RuntimeError(f'{layout}: incomplete render')
        video = arm/f'{layout}.mp4'
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-framerate', '30', '-i', str(arm/'%04d.png'),
                        '-c:v', 'libx264', '-crf', '17', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(video)], check=True)
        metadata = subprocess.check_output(['ffprobe', '-v', 'error', '-count_frames', '-show_streams',
                                            '-show_format', '-of', 'json', str(video)], text=True)
        (arm/'ffprobe.json').write_text(metadata, encoding='utf-8')
        stream, = json.loads(metadata)['streams']
        if (stream['codec_name'], stream['avg_frame_rate'], stream['nb_read_frames'], float(stream['duration']),
                stream['width'], stream['height']) != ('h264', '30/1', '360', 12.0, 960, 540):
            raise RuntimeError(f'{layout}: unexpected stream metadata')
        for second in (1, 8, 10):
            subprocess.run(['ffmpeg', '-v', 'error', '-ss', str(second), '-i', str(video), '-frames:v', '1',
                            str(arm/f'check-{second:02}s.png')], check=True)
    for layout in 'AB':
        shutil.copyfile(scratch/layout/f'{layout}.mp4', out/f'{layout}.mp4')
    print(f'MP4s ready at {out}; frame and ffprobe evidence at {scratch}', flush=True)


if __name__ == '__main__':
    main()
