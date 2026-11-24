"""Run Human Sol live in the full Forward+ scene and sample its own camera."""
import argparse
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]


def inject(scratch):
    run = runpy.run_path(str(HERE/'run.py'))
    script = run['stage'](scratch)
    file = scratch/'human_structure.gd'
    source = file.read_text(encoding='utf-8')
    patches = (
        ('DisplayServer.get_name()!="headless" or Engine.physics_ticks_per_second!=60',
         'DisplayServer.get_name()=="headless" or RenderingServer.get_current_rendering_method()!="forward_plus" or Engine.physics_ticks_per_second!=60'),
        ('Batch requires headless 60 Hz', 'Live requires Forward+ viewport at 60 Hz'),
        ('\tvar decision_trace:=[]',
         '\tvar frames:=OS.get_environment("SOL_FILM_FRAMES")\n'
         '\tprint("LIVE ", RenderingServer.get_current_rendering_method(), " / ", RenderingServer.get_video_adapter_name())\n'
         '\tvar decision_trace:=[]'),
        ('\n\tapply({})\n', '\n\t\tif i<720 and i%4==0:\n'
         '\t\t\tawait RenderingServer.frame_post_draw\n'
         '\t\t\tvar frame:=root.get_texture().get_image()\n'
         '\t\t\tif frame.save_png(frames.path_join("%04d.png" % (i/4)))!=OK:\n'
         '\t\t\t\tpush_error("Live frame write failed");quit(3);return\n\tapply({})\n'),
    )
    for old, new in patches:
        if source.count(old) != 1:
            raise ValueError(f'Live hook changed: {old!r}')
        source = source.replace(old, new)
    file.write_text(source, encoding='utf-8')
    return script, run['BATCH']


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--godot', default=os.getenv('DV_GODOT'))
    args = ap.parse_args()
    scratch = ROOT/'.runtime'/f'structure-film-live-{uuid.uuid4().hex[:8]}'
    scratch.mkdir()
    script, batch = inject(scratch)
    exe = batch['godot_path'](args.godot)
    out = ROOT/'.runtime/design-review'
    out.mkdir(exist_ok=True)
    compare = {}
    for layout in 'AB':
        arm = scratch/layout
        user = arm/'user'
        user.mkdir(parents=True)
        env = dict(os.environ, **dict.fromkeys(('APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME',
                                               'XDG_CONFIG_HOME', 'XDG_CACHE_HOME'), str(user)),
                   SOL_FILM_FRAMES=str(arm))
        report = arm/'report.json'
        cmd = [str(exe), '--path', str(ROOT), '--resolution', '1280x720', '--fixed-fps', '60',
               '--rendering-method', 'forward_plus', '--log-file', str(arm/'engine.log'), '-s', script, '--',
               '--full', '--rogue-mcp-dir=', f'--layout={layout}', '--profile=cautious', '--run-seed=31',
               '--ticks=720', f'--output={report}', f'--batch-user-root={user.as_posix()}']
        (arm/'command.json').write_text(json.dumps(cmd, indent=2), encoding='utf-8')
        print(f'Live {layout}: {arm}', flush=True)
        with (arm/'console.log').open('wb') as log:
            proc = subprocess.run(cmd, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=420)
        if batch['ERROR'].search((arm/'engine.log').read_text(encoding='utf-8', errors='replace')):
            raise RuntimeError(f'{layout}: engine error; see logs')
        data = json.loads(report.read_text(encoding='utf-8'))
        row = batch['inspect_report'](data, 'cautious', 31, 720, user, proc.returncode, 'full')
        geometry = {'center_clear': layout == 'A', 'opening_clear': True,
                    'sensor_hits_portal_plane': layout == 'B'}
        if data['layout'] != layout or data['structure_probe'] != geometry or not data['decision_trace']:
            raise RuntimeError(f'{layout}: live gesture or geometry diagnostics failed: {data["structure_probe"]}')
        if sorted(p.name for p in arm.glob('*.png')) != [f'{i:04}.png' for i in range(180)]:
            raise RuntimeError(f'{layout}: incomplete live render')
        compare[layout] = dict(**row, geometry=geometry, first_beyond=next(
            (p for p in data['path_samples'] if p[1] >= 4.8), None))
        video = arm/f'live-{layout}.mp4'
        subprocess.run(['ffmpeg', '-v', 'error', '-framerate', '15', '-i', str(arm/'%04d.png'), '-c:v',
                        'libx264', '-crf', '17', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(video)], check=True)
        metadata = subprocess.check_output(['ffprobe', '-v', 'error', '-count_frames', '-show_streams',
                                            '-show_format', '-of', 'json', str(video)], text=True)
        (arm/'ffprobe.json').write_text(metadata, encoding='utf-8')
        stream, = json.loads(metadata)['streams']
        if (stream['codec_name'], stream['avg_frame_rate'], stream['nb_read_frames'], float(stream['duration']),
                stream['width'], stream['height']) != ('h264', '15/1', '180', 12., 1280, 720):
            raise RuntimeError(f'{layout}: unexpected live stream metadata')
        for second in (2, 7, 11):
            subprocess.run(['ffmpeg', '-v', 'error', '-ss', str(second), '-i', str(video), '-frames:v', '1',
                            str(arm/f'check-{second:02}s.png')], check=True)
    if compare['A']['policy_parameters'] != compare['B']['policy_parameters']:
        raise RuntimeError('Mismatched live policy parameters')
    (scratch/'pairs.json').write_text(json.dumps(compare, indent=2, ensure_ascii=False), encoding='utf-8')
    for layout in 'AB':
        shutil.copyfile(scratch/layout/f'live-{layout}.mp4', out/f'live-{layout}.mp4')
    print(f'Live MP4s ready at {out}; case evidence at {scratch}', flush=True)


if __name__ == '__main__':
    main()
