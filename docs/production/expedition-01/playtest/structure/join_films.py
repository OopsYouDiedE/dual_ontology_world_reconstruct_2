"""Join synchronized Godot A/B clips losslessly in time, with a one-second poster."""
import argparse
import json
import subprocess
from pathlib import Path


def join(a, b, out):
    def stream(file):
        data = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-select_streams', 'v:0',
            '-show_entries', 'stream=width,height,avg_frame_rate,nb_frames,duration', '-of', 'json', str(file)]))
        return data['streams'][0]
    first = stream(a)
    if first != stream(b):
        raise ValueError('Unequal input streams: align the original captures before comparing.')
    subprocess.run(['ffmpeg','-nostdin','-hide_banner','-loglevel','error','-y','-i',str(a),'-i',str(b),
        '-filter_complex','[0:v][1:v]hstack=inputs=2[v]','-map','[v]','-an','-c:v','libx264','-crf','18',
        '-pix_fmt','yuv420p','-movflags','+faststart',str(out)],check=True)
    if stream(out) != dict(first,width=2*first['width']):
        raise RuntimeError('Unexpected output dimensions or timing')
    subprocess.run(['ffmpeg','-nostdin','-v','error','-y','-ss','1','-i',str(out),'-frames:v','1','-q:v','2',
                    str(out.with_name(out.stem+'-poster.jpg'))],check=True)


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('a','b','out'): p.add_argument(name,type=Path)
    args=p.parse_args();join(args.a,args.b,args.out)
