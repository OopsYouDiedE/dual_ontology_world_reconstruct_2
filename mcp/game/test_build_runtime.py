"""The rendered host's prerequisites are reused only while the import inputs match."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

import build_runtime


class PrepareResourcesTests(unittest.TestCase):
    def test_import_once_and_reimport_when_inputs_change(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / '.runtime').mkdir()
            (root / '.godot/imported').mkdir(parents=True)
            (root / '.godot/editor').mkdir()
            cache = root / '.godot/editor/filesystem_cache10'
            cache.write_text('editor inventory')
            process = Mock(returncode=0)
            process.communicate.return_value = ('import complete', None)
            with patch.object(build_runtime, 'ROOT', root), \
                 patch.object(build_runtime, '_import_stamp', return_value='first') as stamp, \
                 patch.object(build_runtime.asset_bundle, 'ensure') as assets, \
                 patch.object(build_runtime, 'spawn', return_value=process) as spawn:
                build_runtime._prepare_resources('godot', None)
                build_runtime._prepare_resources('godot', None)
                self.assertEqual(spawn.call_count, 1)
                self.assertEqual(assets.call_count, 1)
                stamp.return_value = 'second'
                build_runtime._prepare_resources('godot', None)
                self.assertEqual(spawn.call_count, 2)
                cache.unlink()
                build_runtime._prepare_resources('godot', None)
                self.assertEqual(spawn.call_count, 3)

    def test_failed_import_cannot_seed_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / '.runtime').mkdir()
            process = Mock(returncode=1)
            process.communicate.return_value = ('import failed', None)
            with patch.object(build_runtime, 'ROOT', root), \
                 patch.object(build_runtime, '_import_stamp', return_value='first'), \
                 patch.object(build_runtime.asset_bundle, 'ensure'), \
                 patch.object(build_runtime, 'spawn', return_value=process):
                with self.assertRaisesRegex(RuntimeError, 'import failed'):
                    build_runtime._prepare_resources('godot', None)
                self.assertFalse((root / '.runtime/godot-resource-import.json').exists())
