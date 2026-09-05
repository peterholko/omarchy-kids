#!/usr/bin/env python3
"""Stage module packages or exclude their files from the Omarchy base pair."""
import argparse
import json
import shutil
from pathlib import Path


def entries(source, module=None):
    ownership = json.loads((source / 'packaging/modules.json').read_text())
    result = {}
    for owner, roots in ownership.items():
        for relative in roots:
            entry = source / relative
            if not entry.exists():
                raise ValueError(f'missing package source: {relative}')
            files = [entry] if entry.is_file() or entry.is_symlink() else list(entry.rglob('*'))
            for path in files:
                if '__pycache__' in path.parts or path.suffix == '.pyc' or (path.is_dir() and not path.is_symlink()):
                    continue
                key = path.relative_to(source)
                if key in result:
                    raise ValueError(f'duplicate owner: {key}')
                result[key] = owner
    return {p: owner for p, owner in result.items() if module is None or owner == module}


def destinations(relative):
    if relative.parts[0] == 'bin':
        return [Path('usr/bin') / relative.name, Path('usr/share/omarchy') / relative]
    values = [Path('usr/share/omarchy') / relative]
    if relative.parts[:3] == ('default', 'libalpm', 'hooks'):
        values.append(Path('usr/share/libalpm/hooks') / relative.name)
    if str(relative) == 'default/parent/omarchy-parent-timed.service':
        values.append(Path('usr/lib/systemd/system') / relative.name)
    return values


def stage(source, dest, module):
    for relative in entries(source, module):
        original = source / relative
        targets = destinations(relative)
        for target in targets:
            path = dest / target
            path.parent.mkdir(parents=True, exist_ok=True)
            if relative.parts[0] == 'bin' and target.parts[:3] == ('usr', 'share', 'omarchy'):
                path.symlink_to('/usr/bin/' + relative.name)
            elif original.is_symlink():
                path.symlink_to(original.readlink())
            else:
                shutil.copy2(original, path)
    license_path = dest / 'usr/share/licenses' / ('omarchy-parent-' + module) / 'LICENSE'
    license_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / 'LICENSE', license_path)


def prune(source, dest):
    for relative in entries(source):
        for target in destinations(relative):
            path = dest / target
            if path.is_symlink() or path.is_file():
                path.unlink()
    # Remove now-empty feature directories so discovery cannot mistake them
    # for installed modules. Keep shared base directories.
    for path in sorted(dest.rglob('*'), key=lambda p: len(p.parts), reverse=True):
        if path.is_dir() and not path.is_symlink() and not any(path.iterdir()):
            path.rmdir()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['stage', 'prune', 'snapshot'])
    parser.add_argument('source', type=Path)
    parser.add_argument('dest', type=Path)
    parser.add_argument('module', nargs='?')
    args = parser.parse_args()
    if args.action == 'snapshot':
        shutil.copytree(args.source, args.dest, symlinks=True, ignore=shutil.ignore_patterns('.git', '.DS_Store', '__pycache__', '*.pyc', 'build-output'), dirs_exist_ok=True)
    elif args.action == 'prune':
        prune(args.source, args.dest)
    else:
        stage(args.source, args.dest, args.module)

if __name__ == '__main__':
    main()
