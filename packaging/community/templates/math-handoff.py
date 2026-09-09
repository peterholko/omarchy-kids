"""Open Math Time once after unlock, without resetting a running quiz."""
import subprocess


def reply(*args):
    result = subprocess.run(['omarchy-shell', *args], capture_output=True, text=True, timeout=3)
    return result.stdout.strip() if result.returncode == 0 else ''


def main():
    plugin = 'io.github.peterholko.math'
    if reply('lock', 'isLocked') == 'false' and reply('shell', 'isPluginOpen', plugin) == 'false':
        reply('shell', 'summon', plugin, '{"forced":true}')


if __name__ == '__main__':
    try:
        main()
    except (OSError, subprocess.TimeoutExpired):
        pass
