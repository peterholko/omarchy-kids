import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class ParentUnlockTest(unittest.TestCase):
    def test_pam_grant_without_desktop_environment_or_optional_client(self):
        # Exercise the installed helper's actual wire request. Only substitute
        # the root check (covered by parent-unlock-test.sh) and system paths.
        with tempfile.TemporaryDirectory(prefix='unlock-', dir='/tmp') as directory:
            base = Path(directory)
            address = str(base / 'sock')
            helper = base / 'unlock'
            source = (ROOT / 'bin/omarchy-parent-unlock').read_text()
            helper.write_text(source.replace('(( EUID == 0 ))', 'true')
                              .replace('/usr/bin/python3', sys.executable)
                              .replace('/run/omarchy-parent/screen-time/sock', address))
            # A hostile import path must not affect this privileged pre-session
            # helper, even if a caller somehow retains PYTHONPATH through sudo.
            (base / 'socket.py').write_text('raise RuntimeError("user import executed")\n')
            env = {key: value for key, value in os.environ.items()
                   if key not in {'OMARCHY_PATH', 'SCREEN_TIME_ROOT', 'PYTHONHOME'}}
            env.update(SUDO_USER='kid', PYTHONPATH=str(base))
            messages = []
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
                listener.bind(address)
                listener.listen(1)
                listener.settimeout(5)

                def receive():
                    connection, _ = listener.accept()
                    with connection:
                        connection.settimeout(5)
                        with connection.makefile('rb') as stream:
                            messages.append(json.loads(stream.readline()))
                        connection.sendall(b'{"ok":true}\n')

                worker = threading.Thread(target=receive)
                worker.start()
                result = subprocess.run(['bash', str(helper), '--grant-unlock-time', 'kid'],
                                        env=env, cwd=base, capture_output=True, timeout=8)
                worker.join(6)
                self.assertFalse(worker.is_alive())
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(messages, [{'scope': 'time', 'cmd': 'grant', 'user': 'kid', 'minutes': 5}])
            Path(address).unlink()
            # Removing screen time or stopping its daemon cannot reject an
            # already authenticated parent password at the login screen.
            result = subprocess.run(['bash', str(helper), '--grant-unlock-time', 'kid'],
                                    env=env, cwd=base, capture_output=True, timeout=8)
            self.assertEqual(result.returncode, 0, result.stderr)
