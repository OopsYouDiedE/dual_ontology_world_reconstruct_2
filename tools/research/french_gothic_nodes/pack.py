"""Pack only files referenced by validated inventories, excluding old runs/backups."""
import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

root = Path(__file__).resolve().parents[3] / '.runtime/french-gn'
with ZipFile(root/'french-gothic-nodes.zip', 'w', ZIP_DEFLATED, compresslevel=1) as z:
    z.write(Path(__file__).with_name('README.md'), 'README.md')
    z.write(Path(__file__).with_name('LICENSE.upstream'), 'LICENSE.upstream')
    for source in ('main','demo'):
        directory = root/source
        index = json.loads((directory/'inventory.json').read_text(encoding='utf-8'))
        for file in ['nodes.blend','inventory.json','index.csv']+[r['file'] for r in index['groups']]:
            z.write(directory/file, f'{source}/{file}')
    z.write(root/'main/probes.json','main/probes.json')
