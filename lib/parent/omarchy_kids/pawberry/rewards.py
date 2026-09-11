"""Optional adapter to the co-hosted Screen Time module; no package dependency."""

DEFAULTS = {"enabled": False, "minutes_per_problem": 1, "daily_cap_minutes": 30}


def valid_patch(patch):
    if not isinstance(patch, dict) or set(patch) - set(DEFAULTS):
        return False
    for key, value in patch.items():
        if key == "enabled":
            if type(value) is not bool:
                return False
        elif type(value) is not int or not 1 <= value <= (60 if key == "minutes_per_problem" else 1440):
            return False
    return True


class Rewards:
    def __init__(self, host):
        self.host = host

    def account(self, uid):
        service = self.host.services.get("time")
        if service is None or service.config.get("demo"):
            return None
        account = service.account_for(uid)
        # Kids packages can be updated separately. An older time module must
        # not break ordinary Pawberry play while its update is pending.
        if account and callable(getattr(account, "credit_activity", None)):
            account.rollover(self.host.clock.now())
            return account
        return None

    def status(self, uid, settings):
        account = self.account(uid)
        earned = account.day.activity_rewards.get("pawberry", {}).get("earned_seconds", 0) if account else 0
        room = min(max(0, settings["daily_cap_minutes"] * 60 - earned), account.earn_room()) if account else 0
        reason = "not_managed" if account is None else "disabled" if not settings["enabled"] else (
            account.activity_reward_reason(self.host.clock.now()) or ("daily_cap_reached" if room <= 0 else ""))
        return {**settings, "available": account is not None, "active": not reason, "reason": reason,
            "earned_today_seconds": earned, "remaining_today_seconds": room,
            "balance_seconds": account.day.remaining if account else 0}

    def settle(self, uid, receipt, settings):
        account = self.account(uid)
        if account is None or account.day.day != receipt["reward_day"]:
            return 0
        # Complete a previously committed credit even if the parent has since
        # disabled earning; otherwise a lost acknowledgement could hide it.
        previous = account.day.activity_rewards.get("pawberry", {})
        if previous.get("last_id") == receipt["id"]:
            return previous["last_reward_seconds"]
        seconds = min(receipt["requested_seconds"], settings["minutes_per_problem"] * 60) if settings["enabled"] else 0
        cap = min(receipt["daily_cap_minutes"], settings["daily_cap_minutes"]) * 60
        return account.credit_activity("pawberry", receipt["id"], seconds, cap,
            "Pawberry · " + receipt["label"], self.host.clock.now())
