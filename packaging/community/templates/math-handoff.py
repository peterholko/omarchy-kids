"""Open Math Time once after unlock, without resetting a running quiz."""
import subprocess
import json


def reply(*args):
    result = subprocess.run(['omarchy-shell', *args], capture_output=True, text=True, timeout=3)
    return result.stdout.strip() if result.returncode == 0 else ''


def should_open():
    response = subprocess.run(['/usr/bin/omarchy-kids-controls-time-client', 'status'],
                              capture_output=True, text=True, timeout=5)
    try:
        status = json.loads(response.stdout)
    except ValueError:
        return False
    return (response.returncode == 0 and status.get('ok') is True
            and status.get('mode') != 'school' and status.get('phase') == 'empty'
            and status.get('philosophy') != 'together' and status.get('earn', {}).get('enabled') is True)


def main():
    plugin = 'io.github.peterholko.screen-time'
    if not should_open():
        return
    if reply('lock', 'isLocked') == 'false' and reply('shell', 'call', plugin, 'mathOpen', '') != 'true':
        if reply('shell', 'isPluginOpen', 'io.github.peterholko.math') != 'true':
            reply('shell', 'summon', plugin, '{"math":true,"forced":true}')


if __name__ == '__main__':
    try:
        main()
    except (OSError, subprocess.TimeoutExpired):
        pass
