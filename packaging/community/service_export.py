"""Build the same independently installed controls service for both plugins."""
from pathlib import Path
import shutil


def export_service(root, destination, name):
    from export import copy_tree, replace, TEMPLATES, PREFIX
    from school_export import export_desktop
    service = destination / 'service'
    service.mkdir()
    package = service / 'omarchy_kids'
    package.mkdir()
    shutil.copy2(root / 'lib/parent/omarchy_kids/__init__.py', package / '__init__.py')
    replace(package / '__init__.py', 'VERSION = "0.1.0"',
            'VERSION = "' + (TEMPLATES / 'service/VERSION').read_text().strip() + '"')
    for part in ('core', 'screen_time', 'school_mode', 'number_grove'):
        copy_tree(root / 'lib/parent/omarchy_kids' / part, package / part)
    # Package/ISO migrations and the old namespace manager are not part of the
    # community service. It never converts accounts or adopts Kids state.
    for file in ('modules.py', 'namespace.py', 'files.py', 'parent.sh', 'schedule.sh'):
        (package / 'core' / file).unlink(missing_ok=True)
    for path in package.rglob('*.py'):
        text = path.read_text()
        for old, new in {
            '/etc/omarchy/parent/': '/etc/omarchy-kids-controls/',
            '/var/lib/omarchy/parent': '/var/lib/omarchy-kids-controls',
            '/run/omarchy-kids/screen-time': '/run/omarchy-kids-controls',
            'omarchy.math': PREFIX + 'math',
            'omarchy.screen-time': PREFIX + 'screen-time',
            'omarchy-number-grove.desktop': PREFIX + 'number-grove.desktop',
            'omarchy-paw-post.desktop': PREFIX + 'paw-post.desktop',
            'omarchy-pawberry.desktop': PREFIX + 'pawberry.desktop',
            'Math Time.desktop': PREFIX + 'math.desktop',
        }.items():
            text = text.replace(old, new)
        path.write_text(text)
    replace(package / 'core/paths.py', ' or read_regular(Path("/etc/omarchy/profile")) in ("child", "child\\n")', '')
    replace(package / 'core/paths.py', 'APP = "omarchy-screen-time"', 'APP = "omarchy-kids-controls"')
    replace(package / 'core/paths.py', 'PARENT_STATE_DIR = Path("/var/lib/omarchy-kids-controls")',
            'PARENT_STATE_DIR = Path("/var/lib/omarchy-kids-controls/status")')
    replace(package / 'core/storage.py', '    paths.private_dir(target.parent, mode=0o755, scrub=False)',
            '''    if layout.mode == "system":
        paths.private_dir(paths.PARENT_STATE_DIR, mode=0o755, scrub=False)
        paths.private_dir(target.parent.parent, mode=0o755, scrub=False)
    paths.private_dir(target.parent, mode=0o755, scrub=False)''')
    replace(package / 'school_mode/defaults.py', '"Khan Academy", "Wikipedia", "Math Time"',
            '"Khan Academy", "Wikipedia", "io.github.peterholko.math"')
    replace(package / 'core/session.py',
            '    return value == "true" if value in ("true", "false") else None',
            '    if value == "true": return True\n    return shell_plugin_open(uid, "io.github.peterholko.math")')
    replace(package / 'core/session.py', 'kwargs["group"] = entry.pw_gid',
            'kwargs["group"] = entry.pw_gid\n        kwargs["extra_groups"] = []')
    replace(package / 'core/session.py', 'NOTIFY_COMMANDS = ["omarchy-notification-send", "notify-send"]',
            'NOTIFY_COMMANDS = ["omarchy-notification-send"]')
    replace(package / 'core/cli.py', 'prog="omarchy-kids-time-client", description="Screen time, the client of omarchy-kids-timed"',
            'prog="omarchy-kids-controls-" + SCOPE + "-client", description="Community controls service client"')
    # Bound local connections and reject oversized lines even when a newline
    # arrives in the same socket read as the end of an oversized request.
    replace(package / 'core/proto.py', '        line, _, rest = self.buffer.partition(b"\\n")',
            '        line, _, rest = self.buffer.partition(b"\\n")\n        if len(line) > MAX_LINE:\n            raise ProtocolError("line too long")')
    daemon = package / 'core/daemon.py'
    replace(daemon, '        self.server = None', '        self.server = None\n        self.connections = threading.BoundedSemaphore(32)')
    replace(daemon, '    def serve(self):', '''    def limited_handle(self, connection):
        try:
            self.handle(connection)
        finally:
            self.connections.release()

    def serve(self):''')
    replace(daemon, '            threading.Thread(target=self.handle, args=(conn,), daemon=True).start()',
            '''            if not self.connections.acquire(blocking=False):
                conn.close()
                continue
            threading.Thread(target=self.limited_handle, args=(conn,), daemon=True).start()''')
    auth = package / 'core/auth.py'
    text = auth.read_text()
    start = text.index('def parent_password_ok(')
    end = text.index('\nclass ParentAuth:', start)
    text = text[:start] + '''def parent_password_ok(username, password):
    """Check the separate plugin password; OS authentication is unchanged."""
    if os.geteuid() != 0 or not username or not password:
        return False
    from .credentials import verify_password
    return verify_password(password)
''' + text[end:]
    text = text.replace('accepted = password == "1234" if demo else bool(password) and self.verifier(session.username_for(uid), password)',
                        'accepted = bool(password) and self.verifier(session.username_for(uid), password)')
    auth.write_text(text)
    for filename in ('runtime.py', 'manage.py', 'VERSION', 'omarchy-kids-controls.service'):
        shutil.copy2(TEMPLATES / 'service' / filename, service / filename)
    shutil.copy2(TEMPLATES / 'service/credentials.py', package / 'core/credentials.py')
    export_desktop(root, service)
    module = 'controls'
    (destination / 'setup').write_text(f'''#!/bin/bash
# Install the reviewed local service payload; no code is downloaded here.
set -euo pipefail
plugin_dir=$(cd -- "$(dirname -- "${{BASH_SOURCE[0]}}")" && pwd)
exec /usr/bin/python3 -I "$plugin_dir/service/manage.py" install --module {module} "$@"
''')
    (destination / 'setup').chmod(0o755)
    shutil.copy2(root / 'shell/Ui/ParentPasswordField.qml', destination / 'ParentPasswordField.qml')
    replace(destination / 'ParentPasswordField.qml', 'import QtQuick', 'import QtQuick\nimport qs.Ui')
    for path in destination.rglob('*.qml'):
        text = path.read_text()
        text = text.replace('Quickshell.env("OMARCHY_PATH") + "/bin/omarchy-kids-time-client"',
                            '"/usr/bin/omarchy-kids-controls-time-client"')
        text = text.replace('Quickshell.env("OMARCHY_PATH") + "/bin/omarchy-kids-school-client"',
                            '"/usr/bin/omarchy-kids-controls-school-client"')
        path.write_text(text)
    if name == 'screen-time':
        # The stock lock screen has no Kids-specific handoff. Ask over the
        # public IPC after an unlock, and keep the daemon’s lock fallback.
        shutil.copy2(TEMPLATES / 'math-handoff.py', destination / 'math-handoff.py')
        text = (destination / 'Service.qml').read_text()
        text = text.replace('  function applyEvent(event) {', '''  Process {
    id: handoff
    command: ["python3", "-I", decodeURIComponent(Qt.resolvedUrl("math-handoff.py").toString().replace(/^file:\\/\\//, ""))]
  }
  Timer {
    interval: 5000
    running: root.connected && !root.schoolMode && root.phase === "empty"
    repeat: true
    onTriggered: if (!handoff.running) handoff.running = true
  }

  function applyEvent(event) {''')
        (destination / 'Service.qml').write_text(text)
