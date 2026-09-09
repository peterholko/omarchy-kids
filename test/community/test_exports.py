"""Check the exported installation contract and all bundled local assets."""
import hashlib
import json
import os
from pathlib import Path
import re
import unittest

BASE = Path(os.environ['COMMUNITY_EXPORT'])
NAMES = ['screen-time', 'math-time', 'school-mode', 'number-grove', 'paw-post', 'pawberry']


class ExportsTest(unittest.TestCase):
    def test_six_distinct_root_plugins(self):
        ids = set()
        for name in NAMES:
            root = BASE / ('omarchy-' + name)
            manifest = json.loads((root / 'manifest.json').read_text())
            self.assertTrue(manifest['id'].startswith('io.github.peterholko.'))
            self.assertNotIn(manifest['id'], ids); ids.add(manifest['id'])
            self.assertEqual(manifest['license'], 'MIT')
            for entry in manifest['entryPoints'].values(): self.assertTrue((root / entry).is_file())
            self.assertIn('## Remove', (root / 'README.md').read_text())
            self.assertIn('Copyright', (root / 'LICENSE').read_text())
            self.assertFalse((root / '.github/workflows').exists())
            for path in root.rglob('*'): self.assertFalse(path.is_symlink(), str(path))

    def test_shared_service_payloads_are_identical(self):
        def hashes(module):
            root = BASE / ('omarchy-' + module) / 'service'
            return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob('*')
                    if p.is_file() and '__pycache__' not in p.parts}
        self.assertEqual(hashes('screen-time'), hashes('school-mode'))

    def test_qml_local_imports_exist_and_no_private_kids_paths_remain(self):
        for name in NAMES:
            root = BASE / ('omarchy-' + name)
            for path in root.glob('*.qml'):
                text = path.read_text()
                for relative in re.findall(r'^import "([^\"]+)"', text, re.M):
                    self.assertTrue((path.parent / relative).exists(), str(path) + ': ' + relative)
                for old in ['omarchy-profile-child', 'mutateShellConfig', '/bin/omarchy-kids-time-client', '/bin/omarchy-kids-school-client', '/bin/omarchy-kids-grove-client', '/var/lib/omarchy/parent/']:
                    self.assertNotIn(old, text)
                for target in re.findall(r'serviceFor\("([^\"]+)"\)', text):
                    self.assertEqual(target, json.loads((root / 'manifest.json').read_text())['id'])

    def test_optional_games_use_canonical_school_ids(self):
        for name in ('number-grove', 'paw-post', 'pawberry'):
            root = BASE / ('omarchy-' + name)
            policy = (root / 'SchoolPolicy.qml').read_text()
            self.assertIn('desktopId.replace(/\\.desktop$/', policy)
            self.assertIn('/var/lib/omarchy-kids-controls/status/', policy)
            self.assertTrue((root / ('io.github.peterholko.' + name + '.desktop')).is_file())

    def test_math_practice_has_no_backend_process_dependency(self):
        text = (BASE / 'omarchy-math-time/MathTime.qml').read_text()
        self.assertIn('var question = Facts.question(grade)', text)
        self.assertNotIn('"practice", Quiz.levelName(grade)', text)
        self.assertIn('"-I", decodeURIComponent(Qt.resolvedUrl("remember-grade.py")', text)


if __name__ == '__main__': unittest.main()
