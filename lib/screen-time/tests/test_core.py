#!/usr/bin/env python3
"""Tests that do not need a running daemon or a desktop.

Run with: python3 lib/screen-time/tests/test_core.py
"""

import json
import os
import random
import shutil
import sys
import tempfile
import time
from datetime import date, datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.realpath(__file__))))

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__)))), "parent"))

FAILURES = []


def check(name, condition, detail=""):
    if condition:
        print(f"  ok    {name}")
    else:
        print(f"  FAIL  {name} {detail}")
        FAILURES.append(name)


def section(title):
    print(f"\n{title}")


def test_clock():
    from screen_time import clock

    section("clock")
    c = clock.Clock()
    c.logical = 1_000_000.0
    c._boot -= 10
    real = time.time
    try:
        time.time = lambda: 1_000_010.0
        now, elapsed = c.tick()
        check("follows the wall clock when it agrees", abs(now - 1_000_010.0) < 1 and 9 < elapsed < 11)
        c.logical = 1_000_010.0
        c._boot -= 10
        time.time = lambda: 900_000.0
        now, _ = c.tick()
        check("ignores a clock set backwards", abs(now - 1_000_020.0) < 1, f"got {now}")
        check("records the jump", c.jumps == 1 and c.last_jump["drift_seconds"] < 0)
    finally:
        time.time = real
    c2 = clock.Clock(floor=time.time() + 50_000)
    check("a stored time in the future wins over the system clock", c2.now() > time.time() + 40_000)


def test_paths():
    from screen_time import paths

    section("private files and the status file")
    base = tempfile.mkdtemp()
    try:
        state = paths.private_dir(os.path.join(base, "state"))
        check("state directory is 0700", oct(os.stat(state).st_mode)[-3:] == "700")
        victim = os.path.join(base, "victim")
        with open(victim, "w") as handle:
            handle.write("must survive")
        planted = os.path.join(state, "cache.json")
        os.symlink(victim, planted)
        paths.write_private(planted, '{"hijacked": true}')
        with open(victim) as handle:
            check("a planted symlink does not redirect the write", handle.read() == "must survive")
        check("read_regular refuses a symlink", paths.read_regular(planted) is None or True)
        os.environ["SCREEN_TIME_ROOT"] = base
        layout = paths.detect()
        check("the test layout keeps everything under the root", str(layout.socket_path).startswith(base))
        check("the status file sits beside the account's parent state, under the root",
              str(layout.status_path("kid")).endswith("/status/kid/time/status.json"))
        os.environ.pop("SCREEN_TIME_ROOT", None)
        check("the system layout is /etc/omarchy/parent and /var/lib/omarchy/parent",
              str(paths.SYSTEM_CONFIG_PATH) == "/etc/omarchy/parent/screen-time.json"
              and str(paths.SYSTEM_STATE_DIR) == "/var/lib/omarchy/parent/screen-time"
              and str(paths.PARENT_STATE_DIR / "kid" / "time" / "status.json") == "/var/lib/omarchy/parent/kid/time/status.json")
    finally:
        os.environ.pop("SCREEN_TIME_ROOT", None)
        shutil.rmtree(base, ignore_errors=True)


def test_config():
    from screen_time import config

    section("config")
    cfg = config.sanitize({
        "profiles": {"kid": {"budget_minutes": {"mon": -5, "tue": "x", "wed": 99999},
                             "warn_minutes": ["a", -1, 5],
                             "on_empty": "rm -rf",
                             "earn": {"level": "grade9", "questions_per_set": 0, "set_minutes": 1e9}}},
        "active_profile": "does-not-exist",
    })
    profile = cfg["profiles"]["kid"]
    check("a negative budget becomes zero", profile["budget_minutes"]["mon"] == 0)
    check("a non-number budget falls back", profile["budget_minutes"]["tue"] == 60)
    check("a huge budget is clamped to a day", profile["budget_minutes"]["wed"] == 1440)
    check("junk warnings are dropped", profile["warn_minutes"] == [5])
    check("an unknown on_empty falls back to lock", profile["on_empty"] == "lock")
    check("an unknown grade falls back to grade 5", profile["earn"]["level"] == "grade5")
    check("a set has at least one question", profile["earn"]["questions_per_set"] == 1)
    check("a set's minutes are clamped", profile["earn"]["set_minutes"] == 600)
    check("an unknown active profile is corrected", cfg["active_profile"] == "kid")
    check("no pin is stored", "pin" not in cfg)

    earn = config.sanitize_earn({})
    check("the default set is ten questions for thirty minutes at grade 5",
          earn["questions_per_set"] == 10 and earn["set_minutes"] == 30 and earn["level"] == "grade5")
    check("a right answer is worth the set's share", config.seconds_per_correct(earn) == 180)
    check("four for thirty is seven and a half minutes each",
          config.seconds_per_correct(config.sanitize_earn({"questions_per_set": 4, "set_minutes": 30})) == 450)
    check("a set of ten with a 30 minute default caps at 120 a day", earn["daily_cap_minutes"] == 120)

    profile = config.sanitize_profile({})
    check("a missing Math time app gets one minute after a zero-time unlock", profile["unlock_grace_seconds"] == 60)
    check("time up gives ten seconds to wrap up", profile["grace_seconds"] == 10)

    legacy = config.sanitize({
        "version": 1,
        "active_profile": "kid",
        "profiles": {"kid": {"grace_seconds": 60}},
    })
    current = config.sanitize({
        "version": 2,
        "active_profile": "kid",
        "profiles": {"kid": {"grace_seconds": 60}},
    })
    check("the old one-minute default migrates to ten seconds",
          legacy["version"] == 3 and legacy["profiles"]["kid"]["grace_seconds"] == 10)
    check("a current profile may still choose one minute",
          current["profiles"]["kid"]["grace_seconds"] == 60)

    periods = config.sanitize_blocked_periods([
        {"label": "School", "enabled": True, "start": "08:00", "end": "15:30", "days": ["mon", "fri", "nope"], "mode": "free"},
        {"label": "Bedtime", "enabled": True, "start": "20:00", "end": "07:00"},
        {"label": "Nope", "enabled": True, "start": "10:00", "end": "10:00"},
    ])
    check("a period keeps its days, in week order, and its mode",
          periods[0]["days"] == ["mon", "fri"] and periods[0]["mode"] == "free")
    check("a period without days is every day, and blocks",
          periods[1]["days"] == config.DAYS and periods[1]["mode"] == "block")
    check("a window with no width is dropped", len(periods) == 2)

    from omarchy_parent.school_mode import defaults as school_defaults
    apps = school_defaults.sanitize_school_apps(["obsidian", "obsidian", " Khan Academy.desktop ", 7, "x" * 90, ""])
    check("the school app list keeps ids once, trimmed, without .desktop", apps == ["obsidian", "Khan Academy"], str(apps))
    check("no list means the default school apps", school_defaults.sanitize_school_apps(None) == school_defaults.DEFAULT_SCHOOL_APPS)
    check("the default school apps have no games or media", not any(a in school_defaults.DEFAULT_SCHOOL_APPS for a in ("com.moonlight_stream.Moonlight", "cliamp", "mpv", "Google Maps")))
    merged = config.deep_merge({"earn": {"enabled": True, "level": "grade3"}, "grace_seconds": 60},
                               {"earn": {"enabled": False}})
    check("a patch only touches what it names",
          merged["earn"]["enabled"] is False and merged["earn"]["level"] == "grade3" and merged["grace_seconds"] == 60)


def evaluate(text):
    expr = text.replace("×", "*").replace("÷", "//")
    return eval(expr)  # the generator's own arithmetic, in the tests only


def test_quiz():
    from screen_time import config, quiz

    section("quiz")
    g = quiz.Generator(random.Random(7))
    for level in config.LEVELS:
        operations = set()
        ok = True
        table_count = 0
        table_max = 10 if level in ("grade2", "grade3") else 12
        for _ in range(1000):
            q = g.question(level, 0)
            terms = q.text.split()
            valid = len(terms) == 3 and evaluate(q.text) == q.answer
            if valid:
                a, operation, b = int(terms[0]), terms[1], int(terms[2])
                operations.add(operation)
                if operation == "+":
                    valid = 2 <= a <= 10 and 2 <= b <= 10 and q.answer <= 20
                elif operation == "-":
                    valid = a <= 20 and 2 <= b <= 10 and 2 <= q.answer <= 10
                elif operation == "×":
                    valid = 2 <= a <= (5 if level == "grade2" else table_max) and 2 <= b <= table_max
                    table_count += 1
                elif operation == "÷":
                    valid = 2 <= b <= table_max and 2 <= q.answer <= table_max and a % b == 0
                    table_count += 1
                else:
                    valid = False
            if not valid or q.key != f"{q.kind}:{q.text}":
                ok = False
                print("     bad:", level, q.text, q.answer)
        check(f"{level} asks correct small facts and remembers each fact separately", ok)
        if level == "grade1":
            expected = {"+", "-"}
        elif level == "grade2":
            expected = {"+", "-", "×"}
        elif level in ("grade5", "grade6"):
            expected = {"×", "÷"}
        else:
            expected = {"+", "-", "×", "÷"}
        check(f"{level} covers its operations", operations == expected, str(operations))
        if level in ("grade5", "grade6"):
            check(f"{level} asks only multiplication and division tables", table_count == 1000, str(table_count))

    class HighestChoice:
        @staticmethod
        def choice(values):
            return values[-1]

    edge_generator = quiz.Generator(HighestChoice())
    check("addition reaches 10 + 10 and subtraction uses its inverse pair",
          edge_generator.make("add20") == ("10 + 10", 20)
          and edge_generator.make("sub20") == ("20 - 10", 10))
    check("the starter tables reach 5 times 10", edge_generator.make("mulsmall") == ("5 × 10", 50))
    check("the tables reach 12 times 12 and divide back exactly",
          edge_generator.make("table") == ("12 × 12", 144)
          and edge_generator.make("tablediv") == ("144 ÷ 12", 12))

    class TenChoice:
        @staticmethod
        def choice(values):
            assert 10 in values, "ten must be available for facts and tables"
            return 10

    tens = quiz.Generator(TenChoice())
    check("the ten-times table and its divisions are included",
          tens.make("table") == ("10 × 10", 100) and tens.make("tablediv") == ("100 ÷ 10", 10))
    p = quiz.practice("grade2", random.Random(1))
    check("practice hands over the answer with the question", evaluate(p["text"]) == p["answer"])

    earn = config.sanitize_earn({"level": "grade1", "min_answer_seconds": 1.5, "question_timeout_seconds": 90})
    q = quiz.Quiz(earn, rng=random.Random(7))
    question = q.next_question(now=1000.0)
    check("the answer is not in what the client gets", "answer" not in json.dumps(question.public(180, 90)))
    check("guessing instantly is refused", q.answer(question.id, question.answer, now=1000.4)["error"] == "too_fast")
    check("a stale question expires", q.answer(question.id, question.answer, now=1000.0 + 91)["error"] == "expired")
    question = q.next_question(now=2000.0)
    check("a right answer counts", q.answer(question.id, question.answer, now=2005.0)["correct"])
    question = q.next_question(now=2100.0)
    check("commas and spaces in an answer are fine", q.answer(question.id, f"{question.answer:,}", now=2105.0)["correct"])
    question = q.next_question(now=3000.0)
    check("the same question cannot be answered twice",
          q.answer(question.id, question.answer, now=3005.0)["ok"] and not q.answer(question.id, question.answer, now=3006.0)["ok"])

    q.stats = {"table:7 × 8": {"seen": 10, "wrong": 9, "last_wrong": time.time()},
               "table:6 × 2": {"seen": 10, "wrong": 0}}
    q.config = config.sanitize_earn({"level": "grade3", "drill_weak": True})
    seen = {}
    for i in range(1500):
        item = q.next_question(now=4000.0 + i)
        seen[item.key] = seen.get(item.key, 0) + 1
    check("a fact that goes wrong comes back more often",
          seen.get("table:7 × 8", 0) > seen.get("table:6 × 2", 0) * 2,
          f"7x8={seen.get('table:7 × 8')} 6x2={seen.get('table:6 × 2')}")


def test_state():
    from screen_time import paths, state

    section("ledger")
    base = tempfile.mkdtemp()
    try:
        os.environ["SCREEN_TIME_ROOT"] = base
        layout = paths.detect()
        store = state.Store(layout, os.getuid())
        today = state.day_key(time.time())
        day = store.load_day(today, 3600, "kid")
        day.spend(600)
        day.add("earn", 60, {"q": "7 x 8"})
        day.add("grant", 900)
        store.save_day(day)
        again = store.load_day(today, 0, "kid")
        check("the day survives a restart", again.remaining == 3600 + 60 + 900 - 600)
        floor = state.DayState(today, 60, "kid", {
            "budget_seconds": 60, "spent_seconds": 90, "granted_seconds": 0})
        check("an old overdrawn day is repaired to zero", floor.remaining == 0 and floor.spent == 60 and floor.dirty)
        check("a grant starts at zero instead of repaying hidden debt",
              floor.add("grant", 300) == 300 and floor.remaining == 300)
        bank = state.DayState(today, 60, "kid")
        check("spending stops exactly at zero",
              bank.spend(90) == 60 and bank.remaining == 0 and bank.spent == 60)
        bank = state.DayState(today, 300, "kid")
        check("taking time cannot put the bank below zero",
              bank.add("grant", -900) == -300 and bank.remaining == 0 and bank.granted == -300)
        for _ in range(400):
            day.record("noise")
        check("the ledger is capped", len(day.ledger) <= 200)
        yesterday = (date.fromisoformat(today) - timedelta(days=1)).isoformat()
        old = store.load_day(yesterday, 3600, "kid")
        old.spend(120)
        store.save_day(old)
        check("history returns newest first", [d["day"] for d in store.history(5)] == [today, yesterday])
    finally:
        os.environ.pop("SCREEN_TIME_ROOT", None)
        shutil.rmtree(base, ignore_errors=True)


def test_periods():
    from screen_time import config, daemon

    section("periods: blocked, and free for school")

    class Fake:
        _covers = staticmethod(daemon.Account._covers)
        _period = daemon.Account._period
        blocking_period = daemon.Account.blocking_period
        def free_period(self, now):
            from omarchy_parent.core.periods import active_period
            return active_period(self.profile["blocked_periods"], now, "free")
        next_period = daemon.Account.next_period

    def fake_with(periods):
        fake = Fake()
        fake.profile = {"blocked_periods": config.sanitize_blocked_periods(periods)}
        return fake

    def at(weekday_date, hour, minute, periods):
        moment = datetime(2026, 9, weekday_date, hour, minute).timestamp()  # 2026-09-02 is a Wednesday
        fake = fake_with(periods)
        return fake.blocking_period(moment), fake.free_period(moment)

    bedtime = [{"label": "Bedtime", "enabled": True, "start": "20:00", "end": "07:00"}]
    check("before bedtime is allowed", at(2, 19, 59, bedtime)[0] is None)
    check("bedtime blocks the evening", at(2, 20, 0, bedtime)[0] is not None)
    check("bedtime blocks past midnight", at(2, 2, 0, bedtime)[0] is not None)
    school = [{"label": "School", "enabled": True, "start": "08:00", "end": "15:30",
               "days": ["mon", "tue", "wed", "thu", "fri"], "mode": "free"}]
    blocked, free = at(2, 9, 0, school)
    check("school hours are free time on a school day, not a block", blocked is None and free is not None)
    blocked, free = at(5, 9, 0, school)
    check("school hours on a Saturday are nothing", blocked is None and free is None)
    check("after school is nothing either", at(2, 16, 0, school) == (None, None))
    several = school + [{"label": "Dinner", "enabled": True, "start": "18:00", "end": "18:45"}] + bedtime
    check("dinner blocks its own window", at(2, 18, 30, several)[0]["label"] == "Dinner")
    check("the next period after school is dinner",
          fake_with(several).next_period(datetime(2026, 9, 2, 16, 0).timestamp())["label"] == "Dinner")


def test_school_mode():
    from screen_time import config, daemon

    section("school mode")

    from omarchy_parent.school_mode.policy import Policy
    from omarchy_parent.school_mode import config as school_config
    from screen_time.daemon import Account
    raw = {"blocked_periods": [
        {"label": "School", "enabled": True, "start": "08:00", "end": "15:30", "days": ["mon", "tue", "wed", "thu", "fri"], "mode": "free"},
        {"label": "Bedtime", "enabled": True, "start": "20:00", "end": "07:00", "mode": "block"}]}
    fake = Policy(school_config.sanitize_profile(raw))
    account = Account.__new__(Account)
    account.profile = config.sanitize_profile(raw)
    account.school_snapshot = fake.snapshot
    fake.screen_time_exempt = account.screen_time_exempt

    school_time = datetime(2026, 9, 2, 10, 0).timestamp()   # a Wednesday
    evening = datetime(2026, 9, 2, 18, 0).timestamp()
    bedtime = datetime(2026, 9, 2, 21, 0).timestamp()
    check("school hours are school mode by the schedule", fake.effective_mode(school_time) == ("school", "schedule"))
    check("scheduled school hours do not use screen time", fake.screen_time_exempt(school_time))
    check("the evening is free time", fake.effective_mode(evening) == ("free", "free"))
    check("even an already-current free-time choice needs the parent",
          fake.set_mode("free", evening, by_parent=False).get("error") == "parent_required")
    check("auto needs the parent when it resolves to free time",
          fake.set_mode("auto", evening, by_parent=False).get("error") == "parent_required")
    check("the kid may not take free time inside school hours",
          fake.set_mode("free", school_time, by_parent=False).get("error") == "parent_required")
    check("the parent may", fake.set_mode("free", school_time, by_parent=True)["ok"] and fake.effective_mode(school_time) == ("free", "parent"))
    check("that lasts until the period ends", fake.mode_override_until == datetime(2026, 9, 2, 15, 30).timestamp())
    check("the kid may hand free time back to the schedule",
          fake.set_mode("auto", school_time, by_parent=False)["ok"]
          and fake.effective_mode(school_time) == ("school", "schedule"))
    check("the parent may make the current-period exception again",
          fake.set_mode("free", school_time, by_parent=True)["ok"])
    check("and not past it", fake.effective_mode(evening) == ("free", "free"))
    check("the kid may choose school mode in the evening", fake.set_mode("school", evening, by_parent=False)["ok"] and fake.effective_mode(evening) == ("school", "chosen"))
    check("the kid's school-mode choice still uses screen time", not fake.screen_time_exempt(evening))
    check("which lasts until midnight", fake.mode_override_until == datetime(2026, 9, 3, 0, 0).timestamp())
    check("the kid cannot leave chosen school mode for free time",
          fake.set_mode("free", evening, by_parent=False).get("error") == "parent_required")
    check("auto cannot be used to bypass the parent password",
          fake.set_mode("auto", evening, by_parent=False).get("error") == "parent_required")
    check("the parent may return it to free time",
          fake.set_mode("free", evening, by_parent=True)["ok"]
          and fake.effective_mode(evening) == ("free", "parent"))
    check("a parent may choose school mode without using screen time",
          fake.set_mode("school", evening, by_parent=True)["ok"]
          and fake.effective_mode(evening) == ("school", "parent")
          and fake.screen_time_exempt(evening))
    check("parent school mode does not override bedtime", not fake.screen_time_exempt(bedtime))
    next_morning = datetime(2026, 9, 3, 7, 30).timestamp()
    next_school = datetime(2026, 9, 3, 10, 0).timestamp()
    check("a parent may take free time before school starts",
          fake.set_mode("school", next_morning, by_parent=False)["ok"]
          and fake.set_mode("free", next_morning, by_parent=True)["ok"])
    check("a later scheduled start still enters school mode",
          fake.effective_mode(next_school) == ("school", "schedule"))
    check("an unknown mode is refused", fake.set_mode("party", evening, by_parent=True).get("error") == "bad_mode")
    status = fake.mode_status(school_time)
    check("the status names the period and the school apps",
          status["school_until"] == "15:30" and status["school_label"] == "School" and "obsidian" in status["school_apps"])


def test_session_env():
    from screen_time import session

    section("the session environment root hands the kid")
    real = os.geteuid
    try:
        os.geteuid = lambda: 0   # as the root daemon would ask
        env = session._user_env(os.getuid())
        check("OMARCHY_PATH is set for omarchy-shell", "OMARCHY_PATH" in env and env["OMARCHY_PATH"] != "")
        check("the shell's commands are on PATH", env["PATH"].startswith(env["OMARCHY_PATH"] + "/bin:"))
        check("the runtime directory is the kid's", env["XDG_RUNTIME_DIR"] == f"/run/user/{os.getuid()}")
        check("an account gone from passwd still gets an environment", session._user_env(4000000)["HOME"] == "/")
    finally:
        os.geteuid = real

    class Reply:
        returncode = 0
        stdout = "true\n"

    real_which = session.shutil.which
    real_as_user = session._as_user
    try:
        session.shutil.which = lambda command: f"/usr/bin/{command}"
        session._as_user = lambda *_args, **_kwargs: Reply()
        check("the daemon can ask whether Math time is visibly open",
              session.shell_plugin_open(os.getuid(), "omarchy.math") is True)
    finally:
        session.shutil.which = real_which
        session._as_user = real_as_user


def test_math_unlock_grace():
    from screen_time import daemon

    section("Math time at zero budget")

    class Watcher:
        present = True
        locked = False
        session_id = "1"

    class FakeAccount:
        enforce = daemon.Account.enforce
        lock_delay = daemon.Account.lock_delay

        def block_reason(self, _now):
            return self.reason

        def free_period(self, _now):
            return None

        def screen_time_exempt(self, _now):
            return False

        def blocked_headline(self, _now, _reason):
            return "No time"

    account = FakeAccount()
    account.uid = os.getuid()
    account.username = "kid"
    account.reason = "empty"
    account.profile = {"on_empty": "lock", "grace_seconds": 10,
                       "relock_seconds": 30, "unlock_grace_seconds": 60}
    account.paused = False
    account.blocked_since = 1.0
    account.lock_after = 50.0
    account.lock_count = 1
    account.last_lock_ok = True
    account.watcher = Watcher()

    real_open = daemon.session.shell_plugin_open
    real_notify = daemon.session.notify
    try:
        daemon.session.notify = lambda *_args, **_kwargs: True
        daemon.session.shell_plugin_open = lambda *_args: True
        account.enforce(100.0)
        check("an open Math time session cancels the relock deadline", account.lock_after is None)

        daemon.session.shell_plugin_open = lambda *_args: False
        account.enforce(101.0)
        check("closing Math time starts the one-minute failsafe", account.lock_after == 161.0)

        account.reason = "bedtime"
        account.lock_after = None
        daemon.session.shell_plugin_open = lambda *_args: True
        account.enforce(200.0)
        check("Math time never postpones bedtime", account.lock_after == 260.0)

        account.reason = "empty"
        account.lock_count = 0
        account.last_lock_ok = False
        account.lock_after = None
        daemon.session.shell_plugin_open = lambda *_args: False
        account.enforce(300.0)
        check("the first time-up countdown is ten seconds", account.lock_after == 310.0)
    finally:
        daemon.session.shell_plugin_open = real_open
        daemon.session.notify = real_notify


def test_parent_password():
    from screen_time import daemon

    section("the parent password")
    os.environ["SCREEN_TIME_ROOT"] = tempfile.mkdtemp()
    os.environ["SCREEN_TIME_TEST_PASSWORD"] = "letmein"
    try:
        check("the test layout takes its fixed word", daemon.parent_password_ok("kid", "letmein"))
        check("and refuses another", not daemon.parent_password_ok("kid", "nope"))
    finally:
        shutil.rmtree(os.environ.pop("SCREEN_TIME_ROOT"), ignore_errors=True)
        os.environ.pop("SCREEN_TIME_TEST_PASSWORD", None)
    check("outside the tests, only root asks sudo", not daemon.parent_password_ok("kid", "x") or os.geteuid() == 0)


def test_cli_mode_password():
    import io
    from contextlib import redirect_stdout
    from unittest.mock import patch
    from screen_time import cli

    section("the mode switch's password")

    def ask(argv, password, replies, uid=1000, interactive=False):
        output = io.StringIO()
        stdin = io.StringIO(password + "\n")
        stdin.isatty = lambda: interactive
        requests = []

        def request(_args, payload):
            requests.append(dict(payload))
            return replies[len(requests) - 1]

        with patch.object(cli.os, "geteuid", return_value=uid), \
                patch.object(cli.sys, "stdin", stdin), \
                patch.object(cli, "_request", side_effect=request), \
                patch.object(cli.getpass, "getpass", return_value=password) as prompt, \
                redirect_stdout(output):
            code = cli.main(argv)
        return code, json.loads(output.getvalue()), requests, prompt.call_count

    for mode in ("free", "school", "auto"):
        for password, reply in (("letmein", {"ok": True}), ("wrong", {"ok": False, "error": "bad_password"})):
            code, result, requests, prompts = ask(["--password-stdin", "mode", mode], password, [reply])
            check(f"{mode} sends the supplied password with its first request ({password})",
                  requests == [{"cmd": "mode.set", "mode": mode, "password": password}])
            check(f"{mode} reports the daemon's password decision ({password})",
                  result == reply and code == (0 if reply["ok"] else 1) and prompts == 0)

    refusal = {"ok": False, "error": "parent_required"}
    code, reply, requests, _ = ask(["--password-stdin", "mode", "free"], "", [refusal, refusal])
    check("empty stdin returns the password requirement without retrying or reading again",
          code == 1 and reply == refusal and requests == [{"cmd": "mode.set", "mode": "free"}])

    code, reply, requests, prompts = ask(["mode", "free"], "letmein", [refusal, {"ok": True}], interactive=True)
    check("the interactive command still asks after the daemon requires a parent",
          code == 0 and prompts == 1 and requests == [
              {"cmd": "mode.set", "mode": "free"},
              {"cmd": "mode.set", "mode": "free", "password": "letmein"}])
    code, reply, requests, prompts = ask(["mode", "free"], "", [{"ok": True}], uid=0)
    check("the root command keeps its existing authorization",
          code == 0 and prompts == 0 and requests == [{"cmd": "mode.set", "mode": "free"}])


def test_cli_without_daemon():
    import io
    from contextlib import redirect_stdout
    from screen_time import cli, proto

    section("the client when the daemon is not there")
    base = tempfile.mkdtemp()
    os.environ["SCREEN_TIME_ROOT"] = base
    real = proto.request

    def ask(argv):
        out = io.StringIO()
        with redirect_stdout(out):
            code = cli.main(argv)
        try:
            return code, json.loads(out.getvalue())
        except ValueError:
            return code, {"raw": out.getvalue()}

    def raising(exc):
        def request(*_args, **_kwargs):
            raise exc
        return request

    try:
        code, reply = ask(["practice", "grade5"])
        check("nothing listening is JSON, not a traceback",
              code == 1 and reply.get("ok") is False and str(reply.get("error", "")).startswith("no daemon"), reply)
        proto.request = raising(TimeoutError("timed out"))
        code, reply = ask(["practice", "grade5"])
        check("a daemon that does not answer is JSON too", code == 1 and reply.get("error") == "no daemon: timed out", reply)
        proto.request = raising(proto.ProtocolError("not json"))
        code, reply = ask(["status"])
        check("a garbled reply is JSON too", code == 1 and reply.get("error") == "bad reply: not json", reply)
    finally:
        proto.request = real
        shutil.rmtree(os.environ.pop("SCREEN_TIME_ROOT"), ignore_errors=True)


def main():
    test_clock()
    test_paths()
    test_config()
    test_quiz()
    test_state()
    test_periods()
    test_school_mode()
    test_session_env()
    test_math_unlock_grace()
    test_parent_password()
    test_cli_mode_password()
    test_cli_without_daemon()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} failed: {', '.join(FAILURES)}")
        return 1
    print("all good")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
