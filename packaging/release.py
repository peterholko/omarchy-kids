"""Record the source and hashes for a complete, locally built release."""
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path


def metadata(archive):
    text = subprocess.check_output(['bsdtar', '-xOf', str(archive), '.PKGINFO'], text=True)
    return dict(line.split(' = ', 1) for line in text.splitlines() if line.startswith(('pkgname = ', 'pkgver = ', 'arch = ')))


def main():
    output, source, destination = map(Path, sys.argv[1:])
    packages = {}
    owners = {}
    for archive in output.glob('*.pkg.tar.zst'):
        info = metadata(archive)
        name = info['pkgname']
        if name in packages:
            raise SystemExit('Remove old package revisions from the output directory before building.')
        packages[name] = {**info, 'file': archive.name, 'sha256': hashlib.sha256(archive.read_bytes()).hexdigest()}
        for entry in subprocess.check_output(['bsdtar', '-tf', str(archive)], text=True).splitlines():
            if entry.endswith('/') or entry.removeprefix('./') in ('.PKGINFO', '.BUILDINFO', '.MTREE', '.INSTALL'):
                continue
            if entry in owners:
                raise SystemExit(f'Package ownership conflict: {entry} ({owners[entry]}, {name})')
            owners[entry] = name
    expected = {'omarchy-kids-base', 'omarchy-kids-settings'} | {'omarchy-kids-' + n for n in ('core', 'dns', 'browsing', 'time', 'school')}
    if set(packages) != expected:
        raise SystemExit('The release must contain exactly the base pair and all five module packages.')
    commit = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    dirty = bool(subprocess.check_output(['git', '-C', str(source), 'status', '--porcelain'], text=True).strip())
    (output / 'release.json').write_text(json.dumps({'source': commit, 'dirty': dirty, 'packages': packages}, indent=2) + '\n')
    # Promote only a complete release; an unsuccessful build leaves the
    # previous output intact. Keep unrelated output (such as UI captures).
    destination.mkdir(parents=True, exist_ok=True)
    for old in destination.glob('*.pkg.tar.zst'):
        if metadata(old)['pkgname'] in expected:
            old.unlink()
    for file in output.iterdir():
        shutil.copy2(file, destination / file.name)


if __name__ == '__main__':
    main()
