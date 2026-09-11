"""Per-account daily practice quotas, committed before a pet is awarded.

The game owns its presentation and intermediate steps. This service verifies
issued problems' final answers and owns limits and completion counters. One
outstanding problem per account prevents concurrent windows spending a slot.
"""
from datetime import datetime
import copy
import pwd
import secrets
from ..core import paths, storage

OPERATIONS = ("add", "subtract", "multiply", "divide")
LIMITED = ("add", "subtract")


def answer_for(problem):
    operation, a, b = (problem.get(key) for key in ("operation", "a", "b"))
    if type(a) is not int or type(b) is not int or operation not in OPERATIONS:
        raise ValueError("invalid problem")
    if operation == "divide":
        if not (10 <= a <= 99 and 2 <= b <= 9 and a % b == 0 and a // b <= 9):
            raise ValueError("use exact two-digit / one-digit table facts")
        return a // b
    small = operation == "multiply" and 1 <= a <= 9 and 1 <= b <= 9
    if not small and not (10 <= a <= 999 and 10 <= b <= 999):
        raise ValueError("invalid operands")
    if operation == "subtract" and a < b:
        raise ValueError("negative subtraction")
    return a + b if operation == "add" else a - b if operation == "subtract" else a * b


class Service:
    def __init__(self, host):
        self.host = host
        self.path = host.layout.config_path.with_name("pawberry.json")
        self.state_dir = host.layout.state_dir / "pawberry"
        self.config = storage.read_json(self.path, {"users": {}})
        self.accounts = {}

    def managed_uids(self):
        result = []
        for name in self.config["users"]:
            try:
                result.append(pwd.getpwnam(name).pw_uid)
            except KeyError:
                pass
        return result

    def account(self, uid):
        if uid not in self.accounts:
            paths.private_dir(self.state_dir, scrub=False)
            self.accounts[uid] = storage.read_json(self.state_dir / (str(uid) + ".json"),
                {"day": "", "counts": {}, "pending": None, "receipt": None})
        state = self.accounts[uid]
        today = datetime.fromtimestamp(self.host.clock.now()).date().isoformat()
        # Never reset backwards after a clock or timezone change.
        if today > state["day"]:
            state["day"], state["counts"] = today, {}
            self.persist(uid, state)
        return state

    def persist(self, uid, state):
        storage.write_json(self.state_dir / (str(uid) + ".json"), state)
        self.accounts[uid] = state

    def status(self, uid):
        state = self.account(uid)
        name = pwd.getpwuid(uid).pw_name
        limits = {op: self.config["users"].get(name, {}).get(op) for op in LIMITED}
        counts = {op: state["counts"].get(op, 0) for op in OPERATIONS}
        return {"ok": True, "user": name, "day": state["day"], "limits": limits,
                "completed": counts, "remaining": {op: None if limits.get(op) is None
                    else max(0, limits[op] - counts[op]) for op in OPERATIONS}}

    def dispatch(self, peer, message):
        command = message.get("cmd")
        uid = self.host.resolve_uid(peer, message)
        if uid == 0:
            return {"ok": False, "error": "choose_child_user"}
        try:
            name = pwd.getpwuid(uid).pw_name
        except KeyError:
            return {"ok": False, "error": "unknown_user"}
        if command == "limits.set":
            patch = message.get("limits")
            if not isinstance(patch, dict) or not patch or set(patch) - set(LIMITED) or any(
                    value is not None and (type(value) is not int or not 0 <= value <= 10000)
                    for value in patch.values()):
                return {"ok": False, "error": "invalid_limits"}
            denied = self.host.auth.check(peer, message)
            if denied:
                return denied
            with self.host.lock:
                config = copy.deepcopy(self.config)
                config["users"].setdefault(name, {}).update(patch)
                storage.write_json(self.path, config)
                self.config = config
                return self.status(uid)
        with self.host.lock:
            if command == "status":
                return self.status(uid)
            if command not in ("begin", "complete"):
                return {"ok": False, "error": "unknown_command"}
            state = copy.deepcopy(self.account(uid))
            if command == "begin":
                problem = message.get("problem")
                try:
                    answer_for(problem if isinstance(problem, dict) else {})
                except ValueError:
                    return {"ok": False, "error": "invalid_problem"}
                operation = problem["operation"]
                status = self.status(uid)
                if status["remaining"][operation] == 0:
                    return {**status, "ok": False, "error": "daily_limit", "operation": operation}
                state["pending"] = {key: problem[key] for key in ("a", "b", "operation")}
                state["pending"]["id"] = secrets.token_hex(16)
                self.persist(uid, state)
                return {**status, "id": state["pending"]["id"]}
            identifier = message.get("id")
            if identifier and identifier == (state.get("receipt") or {}).get("id"):
                return {**self.status(uid), "id": identifier, "already_completed": True}
            pending = state.get("pending")
            if not pending or identifier != pending["id"]:
                return {"ok": False, "error": "stale_problem"}
            given = message.get("answer")
            if type(given) is not int or given != answer_for(pending):
                return {"ok": False, "error": "incorrect_answer"}
            status = self.status(uid)
            operation = pending["operation"]
            if status["remaining"][operation] == 0:
                return {**status, "ok": False, "error": "daily_limit", "operation": operation}
            state["counts"][operation] = state["counts"].get(operation, 0) + 1
            state["receipt"] = {"id": identifier}
            state["pending"] = None
            self.persist(uid, state)
            return {**self.status(uid), "id": identifier, "already_completed": False}

    def tick(self, now, elapsed):
        pass

    def save(self):
        # Every setting and completion is synchronously committed before reply.
        pass
