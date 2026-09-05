"""OS parent authentication shared by all privileged feature actions."""
import math
import os
import subprocess
import threading
import time
from . import session

PASSWORD_LOCKOUT = [0, 0, 1, 5, 15, 60, 300]

def parent_password_ok(username, password):
    """Whether this is the parent password: root's, which sudo checks under
    Defaults rootpw. Asked as the kid, since root asks itself nothing; the
    password travels on stdin, never as an argument. faillock's limit on root
    applies to guesses, the same as for sudo itself. In the test layout the
    check is a fixed word, so no sudo is involved."""
    if os.environ.get("SCREEN_TIME_ROOT"):
        return str(password) == os.environ.get("SCREEN_TIME_TEST_PASSWORD", "letmein")
    if os.geteuid() != 0 or not username or not password:
        return False
    try:
        result = subprocess.run(
            ["/usr/bin/runuser", "-u", str(username), "--",
             "/usr/bin/sudo", "-k", "-S", "-u", "root", "--", "/usr/bin/true"],
            input=str(password) + "\n", capture_output=True, text=True, timeout=15, check=False)
    except (OSError, subprocess.SubprocessError):
        return False
    return result.returncode == 0

class ParentAuth:
    def __init__(self, verifier=None, monotonic=time.monotonic):
        self.verifier = verifier or parent_password_ok
        self.monotonic = monotonic
        self.failures = {}
        self.busy = set()
        self.lock = threading.Lock()

    def check(self, uid, message, demo=False):
        if uid == 0:
            return None
        password = str(message.get("password", message.get("pin", "")))
        with self.lock:
            count, until = self.failures.get(uid, (0, 0))
            now = self.monotonic()
            if uid in self.busy:
                return {"ok": False, "error": "password_checking"}
            if now < until:
                return {"ok": False, "error": "password_locked_out", "retry_in_seconds": math.ceil(until - now)}
            self.busy.add(uid)
        try:
            accepted = password == "1234" if demo else bool(password) and self.verifier(session.username_for(uid), password)
        except (OSError, subprocess.SubprocessError):
            accepted = False
        with self.lock:
            self.busy.discard(uid)
            if accepted:
                self.failures.pop(uid, None)
                return None
            count += 1
            self.failures[uid] = (count, self.monotonic() + PASSWORD_LOCKOUT[min(count, len(PASSWORD_LOCKOUT) - 1)])
        return {"ok": False, "error": "bad_password"}
