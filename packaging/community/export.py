"""Export one independent community repository per Omarchy shell plugin.

Usage: python packaging/community/export.py OUTPUT_DIRECTORY
The source checkout stays intact. Each destination must be new or empty.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
TEMPLATES = Path(__file__).resolve().parent / 'templates'
PREFIX = 'io.github.peterholko.'
PLUGINS = {
    'screen-time': ('omarchy-screen-time', 'Screen Time', 'Daily budgets, bedtime, parent controls, and optional arithmetic rewards.', ['bar', 'kids', 'security']),
    'math': ('omarchy-math-time', 'Math Time', 'Friendly arithmetic facts for grades 1–6, with optional screen-time rewards.', ['education', 'kids', 'games']),
    'school-mode': ('omarchy-school-mode', 'School / Free Time', 'Scheduled school mode, an app allowlist, and password-protected free time.', ['education', 'kids', 'security']),
    'number-grove': ('omarchy-number-grove', 'Number Grove', 'An arithmetic garden game with calm and adventure play for grades 1–6.', ['education', 'kids', 'games']),
    'paw-post': ('omarchy-paw-post', 'Paw Post Typing', 'Deliver mail to animal friends while practising accurate, confident typing.', ['education', 'kids', 'games']),
    'pawberry': ('omarchy-pawberry', 'Pawberry Pet Hotel', 'Collect 23 pets and 20 accessories by showing every step of long arithmetic.', ['education', 'kids', 'games']),
}


def copy_tree(source, target):
    target.mkdir(parents=True, exist_ok=True)
    for path in sorted(source.iterdir()):
        if path.name in {'.DS_Store', '__pycache__', '.git'} or path.name.endswith('.pyc'):
            continue
        destination = target / path.name
        if path.is_dir():
            copy_tree(path, destination)
        else:
            # Built-in MathModel.js is a symlink. Community packages must carry
            # their own regular copy, and never refer back to the source tree.
            shutil.copy2(path, destination, follow_symlinks=True)


def replace(path, before, after):
    text = path.read_text()
    if before not in text:
        raise ValueError(f'{path.name}: expected source fragment is missing: {before[:70]!r}')
    path.write_text(text.replace(before, after))


def common_references(destination):
    mappings = {f'omarchy.{name}': PREFIX + name for name in PLUGINS}
    mappings.update({
        '/var/lib/omarchy/parent/': '/var/lib/omarchy-kids-controls/status/',
        'omarchy-number-grove.desktop': PREFIX + 'number-grove.desktop',
        'omarchy-paw-post.desktop': PREFIX + 'paw-post.desktop',
        'omarchy-pawberry.desktop': PREFIX + 'pawberry.desktop',
    })
    for path in destination.rglob('*'):
        if path.suffix not in {'.qml', '.js', '.json', '.jsonc'}:
            continue
        text = path.read_text()
        for old, new in mappings.items():
            text = text.replace(old, new)
        path.write_text(text)


def games(name, destination):
    entry = {'number-grove': 'NumberGrove.qml', 'paw-post': 'PawPost.qml', 'pawberry': 'Pawberry.qml'}[name]
    path = destination / entry
    text = path.read_text()
    start = text.index('  readonly property var schoolService:')
    end = text.index('  function open(', start)
    text = text[:start] + f'''  SchoolPolicy {{ id: schoolPolicy; desktopId: "{PREFIX}{name}.desktop" }}
  readonly property bool schoolAllowed: schoolPolicy.allowed

''' + text[end:]
    path.write_text(text)
    shutil.copy2(TEMPLATES / 'SchoolPolicy.qml', destination / 'SchoolPolicy.qml')
    if name == 'number-grove':
        replace(destination / 'RewardBridge.qml', 'omarchyPath + "/bin/omarchy-kids-grove-client"',
                '"/usr/bin/omarchy-kids-controls-grove-client"')
    test_directory = destination / 'test'
    test_directory.mkdir()
    for source in (ROOT / 'test' / name).glob('*.cjs'):
        text = source.read_text().replace(f'../../shell/plugins/{name}/', '../')
        (test_directory / source.name).write_text(text)
    visual = ROOT / 'test' / name / 'visual.py'
    if visual.exists():
        text = visual.read_text().replace('Path(__file__).resolve().parents[2]', 'Path(__file__).resolve().parents[1]')
        text = text.replace(f"ROOT / 'shell/plugins/{name}/", "ROOT / '")
        text = text.replace(f"ROOT / 'shell/plugins/{name}'", 'ROOT')
        (test_directory / 'visual.py').write_text(text)
    shutil.copy2(ROOT / 'docs/images' / (name + '.png'), destination / 'preview.png')
    if name == 'pawberry':
        shutil.copy2(ROOT / 'docs/images/pawberry-collection.png', destination / 'collection.png')


def math(destination):
    shutil.copy2(ROOT / 'shell/plugins/number-grove/Facts.js', destination / 'PracticeFacts.js')
    path = destination / 'MathTime.qml'
    replace(path, 'import "MathModel.js" as Quiz', 'import "MathModel.js" as Quiz\nimport "PracticeFacts.js" as Facts')
    replace(path, 'WlrLayershell.namespace: "omarchy-math"', 'WlrLayershell.namespace: "io.github.peterholko.math"')
    replace(path, 'Quickshell.env("OMARCHY_PATH") + "/bin/omarchy-kids-time-client"',
            '"/usr/bin/omarchy-kids-controls-time-client"')
    replace(path, 'homeDir + "/.local/state/omarchy/math-grade"',
            '(Quickshell.env("XDG_STATE_HOME") || homeDir + "/.local/state") + "/omarchy-math-time/grade"')
    replace(path, 'if (earning) questionProc.command = [clientPath, "quiz"]\n    else questionProc.command = [clientPath, "practice", Quiz.levelName(grade)]',
            '''if (!earning) {
      var question = Facts.question(grade)
      takeQuestion(JSON.stringify({ok: true, text: question.text, answer: question.answer}), "")
      Qt.callLater(function() { answerInput.forceActiveFocus() })
      return
    }
    questionProc.command = [clientPath, "quiz"]''')
    replace(path, 'if (!opened) return\n    var toplevels', 'if (!opened || !earning) return\n    var toplevels')
    replace(path, 'saveGradeProc.command = ["bash", "-c", "mkdir -p ~/.local/state/omarchy && printf \'%s\\\\n\' " + n + " >~/.local/state/omarchy/math-grade"]',
            'saveGradeProc.command = ["python3", "-I", decodeURIComponent(Qt.resolvedUrl("remember-grade.py").toString().replace(/^file:\\/\\//, "")), String(n)]')
    shutil.copy2(TEMPLATES / 'remember-grade.py', destination / 'remember-grade.py')


def license_file(destination, name):
    inherited = (ROOT / 'LICENSE').read_text()
    inherited = inherited.replace('MIT License\n', 'MIT License\n\nCopyright (c) 2026 Peter Holko', 1)
    if name in {'screen-time', 'school-mode'}:
        inherited = inherited.replace('Copyright (c) 2026 Peter Holko',
            'Copyright (c) 2026 Peter Holko\nCopyright (c) 2026 Jankees van Woezik\nCopyright (c) 2026 elgevan')
    (destination / 'LICENSE').write_text(inherited)
    (destination / 'ATTRIBUTION.md').write_text(
        '# Attribution\n\nExtracted from [Omarchy Kids](https://github.com/peterholko/omarchy-kids), maintained by Peter Holko. The inherited Omarchy MIT copyright notice is retained.\n\n'
        + ('The shared controls service and screen-time UI derive from Jankees van Woezik’s MIT-licensed omarchy-screen-time. School-mode work derives from elgevan’s MIT-licensed omarchy-kids-menu. Their notices are retained in LICENSE.\n' if name in {'screen-time', 'school-mode'} else '')
        + ('\nThe game artwork and launcher icons were generated for Omarchy Kids; their original prompts are included under assets/. The preview shows the game’s actual Qt interface.\n' if name in {'number-grove', 'paw-post', 'pawberry'} else '')
    )


def export(output):
    from service_export import export_service
    from school_export import export_school
    from readme import readme
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    for name, (repository, title, description, tags) in PLUGINS.items():
        destination = output / repository
        if destination.exists() and any(destination.iterdir()):
            raise ValueError(f'export destination is not empty: {destination}')
        copy_tree(ROOT / 'shell/plugins' / name, destination)
        common_references(destination)
        if name in {'number-grove', 'paw-post', 'pawberry'}:
            games(name, destination)
        elif name == 'math':
            math(destination)
        if name in {'screen-time', 'school-mode'}:
            export_service(ROOT, destination, name)
        if name == 'school-mode':
            export_school(ROOT, destination)
        manifest = json.loads((destination / 'manifest.json').read_text())
        manifest.update(id=PREFIX + name, name=title, author='Peter Holko',
                        description=description, license='MIT')
        if name == 'school-mode':
            manifest['barWidget'].update(displayName=title, description=description, defaultSection='right')
        (destination / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        license_file(destination, name)
        (destination / '.gitignore').write_text('.DS_Store\n__pycache__/\n*.pyc\n')
        (destination / 'README.md').write_text(readme(name, repository, title, description))
        (destination / 'SOURCE.json').write_text(json.dumps({
            'repository': 'https://github.com/peterholko/omarchy-kids', 'commit': revision,
            'path': 'shell/plugins/' + name, 'exporter': 'packaging/community/export.py',
        }, indent=2) + '\n')
        if name not in {'screen-time', 'school-mode'}:
            icon = PREFIX + name if name in {'number-grove', 'paw-post', 'pawberry'} else 'applications-education'
            (destination / (PREFIX + name + '.desktop')).write_text(
                f'[Desktop Entry]\nType=Application\nName={title}\nComment={description}\n'
                f'Exec=omarchy-shell shell summon {PREFIX}{name} {{}}\nIcon={icon}\nTerminal=false\nCategories=Education;Game;\n')
        for path in destination.rglob('*'):
            if path.is_file() and (path.suffix in {'.qml', '.js', '.py', '.md', '.json', '.jsonc', '.cjs', '.desktop'} or path.name == 'LICENSE'):
                path.write_text(path.read_text().rstrip() + '\n')
        print(destination)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    export(parser.parse_args().output.resolve())
