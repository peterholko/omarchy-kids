import importlib.util
import itertools
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'lib/parent'))
from omarchy_parent.core.modules import Manager

spec = importlib.util.spec_from_file_location('stage', ROOT / 'packaging/stage.py')
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)


class PackageTest(unittest.TestCase):
    def test_all_sixteen_optional_package_combinations(self):
        optional = ['dns', 'browsing', 'time', 'school']
        script = '''
import sys, os, json, importlib.util
sys.path.insert(0, sys.argv[1])
from omarchy_parent.core.daemon import Daemon
from omarchy_parent.core.paths import detect
host = Daemon(detect(), log=lambda _: None)
print(json.dumps(sorted(host.services)))
'''
        with tempfile.TemporaryDirectory(prefix='kids-packages-') as tmp:
            for bits in itertools.product([False, True], repeat=4):
                selected = [m for m, yes in zip(optional, bits) if yes]
                with self.subTest(modules=selected):
                    dest = Path(tmp) / ''.join(str(int(bit)) for bit in bits)
                    for module in ['core', *selected]:
                        stage.stage(ROOT, dest, module)
                    env = {**os.environ, 'SCREEN_TIME_ROOT': str(dest / 'state'), 'OMARCHY_PATH': str(dest / 'usr/share/omarchy')}
                    output = subprocess.check_output([sys.executable, '-I', '-c', script, str(dest / 'usr/share/omarchy/lib/parent')], env=env, text=True)
                    self.assertEqual(json.loads(output), sorted(set(selected) & {'school', 'time'}))
                    for module in optional:
                        self.assertEqual((dest / 'usr/bin' / ('omarchy-parent-' + module)).exists(), module in selected)
                    self.assertEqual((dest / 'usr/share/omarchy/shell/plugins/math').exists(), 'time' in selected)
                    self.assertEqual((dest / 'usr/share/omarchy/shell/plugins/school-mode').exists(), 'school' in selected)

    def test_base_relinquishes_every_module_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp)
            for module in ['core', 'dns', 'browsing', 'time', 'school']:
                stage.stage(ROOT, dest, module)
            stage.prune(ROOT, dest)
            for relative in stage.entries(ROOT):
                for target in stage.destinations(relative):
                    self.assertFalse((dest / target).exists(), target)

    def test_dependency_resolution_and_core_protection(self):
        manager = Manager(ROOT)
        self.assertEqual(manager.resolve(['school-mode', 'time', 'school']), ['core', 'school', 'time'])
        with self.assertRaises(ValueError):
            manager.remove('core')
        manager.catalog['core']['requires'] = ['school']
        with self.assertRaisesRegex(ValueError, 'cycle'):
            manager.resolve(['school'])

    def test_failed_shutdown_does_not_remove_package(self):
        manager = Manager(ROOT)
        with patch.object(manager, 'installed', return_value=True), patch.object(manager, 'users', return_value=['kid']), patch.object(manager, 'change', side_effect=ValueError('restoration failed')), patch('subprocess.run') as run:
            with self.assertRaisesRegex(ValueError, 'restoration failed'):
                manager.remove('school')
            run.assert_not_called()

    def test_installing_does_not_enable_browsing(self):
        manager = Manager(ROOT)
        with patch('subprocess.run') as run, patch.object(manager, 'refresh_desktops'), patch.object(manager, 'change') as change:
            manager.install(['browsing'])
            self.assertEqual(run.call_args_list[0].args[0], ['omarchy-pkg-add', 'omarchy-parent-core', 'omarchy-parent-browsing'])
            change.assert_not_called()
