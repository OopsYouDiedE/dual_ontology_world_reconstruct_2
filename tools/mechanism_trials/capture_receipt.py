"""Revision/source binding for a capture performed against an unchanged checkout."""
import hashlib
from pathlib import Path
import subprocess


SHARED_GAME_PATHS = (
    'project.godot', 'mcp/game/GameControl.gd', 'mcp/game/server.py',
    'scenes/components/rendering/post', 'scenes/blue_prince_lab/HallFinish.gdshader',
    'scenes/physics_lab/shutter_loom/ShutterRoom.gd', 'tools/building_construction/production',
    'tools/chronograph/capture.py',
)


def assert_frozen(root: Path, revision: str, paths) -> dict:
    def git(*args):
        return subprocess.check_output(['git', *args], cwd=root)

    if git('rev-parse', 'HEAD').decode().strip() != revision:
        raise ValueError('Capture must run with the requested frozen commit checked out')
    paths = tuple(sorted(set(paths)))
    subprocess.run(['git', 'diff', '--quiet', revision, '--', *paths], cwd=root, check=True)
    names = git('ls-tree', '-rz', '--name-only', revision, '--', *paths)
    records = []
    for name in names.decode('utf-8').rstrip('\0').split('\0'):
        if name:
            records.append({'path_at_revision': name,
                            'sha256': hashlib.sha256(git('show', f'{revision}:{name}')).hexdigest()})
    if not records:
        raise ValueError('No tracked paths bound to capture')
    return {'revision': revision, 'bound_paths': list(paths), 'files': records}
