#!/usr/bin/env python3
"""Headless MuseScore playback of a theme study with an explicit sound profile."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import zipfile
from xml.etree import ElementTree as ET

from theme_studies import meter_audio

VOICE_IDS = ('soprano', 'alto', 'tenor', 'bass')
DEFAULT_DIR = Path('Music/theme-studies')
SCRATCH = Path('.runtime/main-theme/musescore-render')
WINDOW_FLAGS = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0


def run(args, **opts):
    subprocess.run([str(a) for a in args], check=True, creationflags=WINDOW_FLAGS, **opts)


def verify_tracks(path, profile):
    rows = json.loads(path.read_text(encoding='utf-8'))['newTracks']
    voices = {item['instrumentId']: item for item in rows if item['instrumentId'] in VOICE_IDS}
    if set(voices) != set(VOICE_IDS):
        raise SystemExit(f'Expected four distinct SATB tracks, got {list(voices)}')
    print(json.dumps(voices, ensure_ascii=False))
    if profile == 'MuseSounds' and any('sampler' not in v['type'].lower() for v in voices.values()):
        raise SystemExit('MuseSounds did not load all four vocal tracks. No audition was published. '
                         'Install/complete Muse Choir or explicitly choose --profile "MuseScore Basic".')
    if profile == 'MuseScore Basic':
        assert all(v['type'] == 'fluid_soundfont' and v['name'] == 'MS Basic' for v in voices.values())
    return voices


def verify_native(path):
    with zipfile.ZipFile(path) as z:
        source = next(s for s in z.namelist() if s.endswith('.mscx'))
        p = ET.fromstring(z.read(source)).findall('./Score/Part/Instrument')
        assert [x.findtext('instrumentId') for x in p[:4]] == [f'voice.{v}' for v in VOICE_IDS]
        assert all(x.find('.//program').get('value') == '52' for x in p[:4]), 'Expected Choir Aahs GM fallback'


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('--musescore', default=r'C:\Program Files\MuseScore 4\bin\MuseScore4.exe')
    cli.add_argument('--score', type=Path, default=DEFAULT_DIR/'d-no-tomorrow.musicxml')
    cli.add_argument('--out', type=Path, default=DEFAULT_DIR)
    cli.add_argument('--profile', choices=('MuseSounds','MuseScore Basic'), default='MuseSounds')
    args = cli.parse_args()
    score = args.score.resolve(strict=True)
    out = args.out.resolve()
    suffix = 'muse-choir' if args.profile == 'MuseSounds' else 'ms-basic'
    base = f'{score.stem}-{suffix}'
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as folder:
        work = Path(folder).resolve()
        diff, diagnostic = work/'tracks.json', work/'diagnostic.mp3'
        wav, native, rendered = work/'raw.wav', work/f'{score.stem}.mscz', work/f'{base}.mp3'
        musescore = [args.musescore, '--sound-profile', args.profile]
        run([*musescore, '--tracks-diff', diff, '-b', '128', '-o', diagnostic, score], timeout=90)
        voices = verify_tracks(diff, args.profile)
        run([*musescore, '-o', wav, score], timeout=90)
        raw = meter_audio(wav)
        gain = min(-20-raw['integrated_lufs'], -1.5-raw['true_peak_dbtp'])
        run(['ffmpeg','-v','error','-y','-i',wav,'-af',f'volume={gain:.4f}dB',
             '-c:a','libmp3lame','-b:a','256k', '-metadata',f'title={score.stem} | {args.profile}',rendered])
        measure = meter_audio(rendered)
        assert measure['true_peak_dbtp'] <= -1.0
        run([args.musescore, '-o', native, score], timeout=90)
        verify_native(native)
        out.mkdir(parents=True, exist_ok=True)
        (out/rendered.name).write_bytes(rendered.read_bytes())
        (out/native.name).write_bytes(native.read_bytes())
        report = {'profile':args.profile, 'voice_tracks':voices, 'raw':raw,
                  'gain_db':round(gain, 2), 'delivered_mp3':measure}
        (out/f'{base}.json').write_text(json.dumps(report,indent=2) + '\n',encoding='utf-8')
        print(json.dumps(report,indent=2))


if __name__ == '__main__':
    main()
