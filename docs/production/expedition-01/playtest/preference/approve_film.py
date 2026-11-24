"""Sign a specific review film after visual inspection; never issues a ballot."""
import argparse
import json
from pathlib import Path
import subprocess
from queue_review import DEFAULT, sha


def approve(movie, gate, observations):
    if not movie.is_file() or movie.suffix.lower() != '.mp4':
        raise ValueError('expected an existing .mp4')
    if any(not text.strip() for text in observations.values()):
        raise ValueError('record each inspection')
    info = json.loads(subprocess.check_output([
        'ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries',
        'stream=width,height,codec_name:format=duration', '-of', 'json', str(movie)]))
    if not info['streams'] or float(info['format']['duration']) <= 0:
        raise ValueError('expected a playable film')
    record = dict(ok=True, sha256=sha(movie), observations=observations, probe=info)
    gate.with_suffix('.tmp').write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding='utf8')
    gate.with_suffix('.tmp').replace(gate)


if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('stem',choices=['arcade','room']);ap.add_argument('--root',type=Path,default=DEFAULT/'round-03')
    keys=['entry','approach','detail','controls']
    for key in keys:ap.add_argument('--'+key,required=True)
    a=ap.parse_args();approve(a.root/(a.stem+'.mp4'),a.root/(a.stem+'-review.json'),{k:getattr(a,k) for k in keys})
