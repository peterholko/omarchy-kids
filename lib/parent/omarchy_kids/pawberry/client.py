"""Parent CLI and the game's unprivileged transport; no passwords in argv."""
import argparse
import getpass
import json
import os
import sys
from ..core import paths, proto


def limit(value):
    if value == "unlimited":
        return None
    try:
        number = int(value)
        if str(number) != value or not 0 <= number <= 10000:
            raise ValueError()
        return number
    except ValueError:
        raise argparse.ArgumentTypeError("use 0–10000, or unlimited") from None


def main(argv=None):
    parser = argparse.ArgumentParser(prog="omarchy kids pawberry",
        description="Play Pawberry, or configure parent practice limits and optional time rewards.")
    sub = parser.add_subparsers(dest="command", required=True)
    for command in ("status", "limits", "settings"):
        part = sub.add_parser(command)
        part.add_argument("--user", default=os.environ.get("SUDO_USER"))
        if command in ("limits", "settings"):
            part.add_argument("--addition", type=limit, default=argparse.SUPPRESS)
            part.add_argument("--subtraction", type=limit, default=argparse.SUPPRESS)
            part.add_argument("--password-stdin", action="store_true")
        if command == "settings":
            part.add_argument("--screen-time", choices=("on", "off"))
            part.add_argument("--minutes-per-problem", type=int)
            part.add_argument("--daily-reward-minutes", type=int)
    sub.add_parser("request").add_argument("payload")
    args = parser.parse_args(argv)
    if args.command == "request":
        try:
            payload = json.loads(args.payload)
            if not isinstance(payload, dict) or payload.get("cmd") not in {"status", "begin", "complete"}:
                raise ValueError()
        except ValueError:
            parser.error("invalid game request")
    else:
        payload = {"cmd": "status", "user": args.user}
        if args.command in ("limits", "settings"):
            patch = {op: getattr(args, option) for option, op in
                     (("addition", "add"), ("subtraction", "subtract")) if hasattr(args, option)}
            if not patch and args.command == "limits":
                parser.error("limits requires --addition or --subtraction")
            payload.update(cmd="limits.set", limits=patch)
            if args.command == "settings":
                rewards = {key: getattr(args, option) for option, key in
                    (("minutes_per_problem", "minutes_per_problem"), ("daily_reward_minutes", "daily_cap_minutes"))
                    if getattr(args, option) is not None}
                if args.screen_time is not None:
                    rewards["enabled"] = args.screen_time == "on"
                payload.update(cmd="settings.set", screen_time=rewards)
            if os.geteuid() != 0:
                payload["password"] = sys.stdin.readline().rstrip("\n") if args.password_stdin else getpass.getpass("Parent password: ")
    payload["scope"] = "pawberry"
    try:
        result = proto.request(paths.client_socket_candidates(), payload, timeout=25)
    except (OSError, proto.ProtocolError):
        result = {"ok": False, "error": "unavailable"}
    print(json.dumps(result))
    return 0 if result.get("ok") else 1
