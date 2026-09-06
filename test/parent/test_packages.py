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
from omarchy_kids.core.modules import Manager

spec = importlib.util.spec_from_file_location('stage', ROOT / 'packaging/stage.py')
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)


class PackageTest(unittest.TestCase):
    def test_default_child_install_includes_the_catalog_without_duplicate_ids(self):
        catalog = Manager(ROOT).catalog
        packages = [line.strip() for line in (ROOT / 'install/omarchy-child.packages').read_text().splitlines()
                    if line.strip() and not line.startswith('#')]
        self.assertEqual(set(packages), {item['package'] for item in catalog.values()})
        self.assertEqual(len(packages), len(set(packages)))
        plugins = [plugin for item in catalog.values() for plugin in item['shellPlugins']]
        self.assertEqual(len(plugins), len(set(plugins)))

    def test_all_optional_package_combinations(self):
        optional = [name for name in Manager(ROOT).catalog if name != 'core']
        script = '''
import sys, os, json, importlib.util
sys.path.insert(0, sys.argv[1])
from omarchy_kids.core.daemon import Daemon
from omarchy_kids.core.paths import detect
host = Daemon(detect(), log=lambda _: None)
print(json.dumps(sorted(host.services)))
'''
        with tempfile.TemporaryDirectory(prefix='kids-packages-') as tmp:
            for bits in itertools.product([False, True], repeat=len(optional)):
                selected = [m for m, yes in zip(optional, bits) if yes]
                with self.subTest(modules=selected):
                    dest = Path(tmp) / ''.join(str(int(bit)) for bit in bits)
                    for module in ['core', *selected]:
                        stage.stage(ROOT, dest, module)
                    self.assertTrue((dest / 'usr/lib/systemd/system/omarchy-kids-timed.service').exists())
                    env = {**os.environ, 'SCREEN_TIME_ROOT': str(dest / 'state'), 'OMARCHY_PATH': str(dest / 'usr/share/omarchy')}
                    output = subprocess.check_output([sys.executable, '-I', '-c', script, str(dest / 'usr/share/omarchy/lib/parent')], env=env, text=True)
                    self.assertEqual(json.loads(output), sorted(set(selected) & {'school', 'time'}))
                    for module in optional:
                        self.assertEqual((dest / 'usr/bin' / ('omarchy-kids-' + module)).exists(), module in selected)
                    self.assertEqual((dest / 'usr/share/applications/omarchy-paw-post.desktop').exists(), 'typing' in selected)
                    self.assertEqual((dest / 'usr/share/omarchy/shell/plugins/paw-post/TypingView.qml').exists(), 'typing' in selected)
                    self.assertEqual((dest / 'usr/share/applications/omarchy-number-grove.desktop').exists(), 'grove' in selected)
                    self.assertEqual((dest / 'usr/share/omarchy/shell/plugins/number-grove/GameView.qml').exists(), 'grove' in selected)
                    self.assertEqual((dest / 'usr/share/omarchy/shell/plugins/math').exists(), 'time' in selected)
                    self.assertEqual((dest / 'usr/share/omarchy/shell/plugins/school-mode').exists(), 'school' in selected)

    def test_base_relinquishes_every_module_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp)
            for module in Manager(ROOT).catalog:
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
            self.assertEqual(run.call_args_list[0].args[0], ['omarchy-pkg-add', 'omarchy-kids-core', 'omarchy-kids-browsing'])
            change.assert_not_called()

    def test_grove_is_an_independent_application(self):
        manager = Manager(ROOT)
        self.assertEqual(manager.resolve(['grove']), ['core', 'grove'])
        with patch.object(manager, 'installed', return_value=True), patch.object(manager, 'refresh_desktops'), patch('subprocess.run') as run:
            with self.assertRaisesRegex(ValueError, 'ready when installed'):
                manager.change('grove', True)
            run.assert_not_called()
            manager.remove('grove')
            self.assertEqual(run.call_args_list[0].args[0], ['omarchy-pkg-drop', 'omarchy-kids-grove'])
        with patch.object(manager, 'installed', side_effect=lambda name: name in ('core', 'grove')), patch('omarchy_kids.core.proto.request', return_value={}):
            item = next(item for item in manager.listing() if item['id'] == 'grove')
            self.assertTrue(item['enabled'])
            self.assertTrue(item['healthy'])

    def test_typing_is_independent_and_removal_only_drops_its_package(self):
        manager = Manager(ROOT)
        self.assertEqual(manager.resolve(['typing']), ['core', 'typing'])
        with patch.object(manager, 'installed', return_value=True), patch.object(manager, 'refresh_desktops'), patch('subprocess.run') as run:
            with self.assertRaisesRegex(ValueError, 'ready when installed'):
                manager.change('typing', True)
            run.assert_not_called()
            manager.remove('typing')
            self.assertEqual(run.call_args_list[0].args[0], ['omarchy-pkg-drop', 'omarchy-kids-typing'])
