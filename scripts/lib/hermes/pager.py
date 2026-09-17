"""Hermes SMS pager: a short allowlist of must-know events texted to the operator's phone.

Paging deliberately bypasses the two-signal correlator. Every page is de-duplicated
(one text on the way down, one on recovery) and capped by a daily SMS budget kept in
state. Delivery is Gmail SMTP to a carrier SMS gateway, with credentials read from the
laptop login Keychain only -- never from Vault, which lives in the cluster Hermes must
outlive.
"""

import smtplib
from email.message import EmailMessage

SMS_FROM_SERVICE = "k3dm-hermes-sms-from"
SMS_PASSWORD_SERVICE = "k3dm-alertmanager-gmail-app-password"
SMS_TO_SERVICE = "k3dm-hermes-sms-to"
SMS_MAX_CHARS = 140
SMTP_HOST = "smtp.gmail.com"
SMTP_PORT = 587
WEBHOOK_SENSORS = ("eso", "node_pressure")
WEBHOOK_DOWN_CYCLES = 2
SENSOR_UNKNOWN_CYCLES = 6
JOB_FAILURE_CYCLES = 2
SEVERE = ("critical", "high")


def send_sms(keychain, text, smtp_factory=smtplib.SMTP):
    """Text one message through Gmail SMTP; return success. Never raises."""
    sender = keychain(SMS_FROM_SERVICE)
    password = keychain(SMS_PASSWORD_SERVICE)
    recipient = keychain(SMS_TO_SERVICE)
    if not (sender and password and recipient):
        return False
    message = EmailMessage()
    message["From"] = sender
    message["To"] = recipient
    message["Subject"] = "Hermes"
    message.set_content(text[:SMS_MAX_CHARS])
    try:
        with smtp_factory(SMTP_HOST, SMTP_PORT, timeout=20) as smtp:
            smtp.starttls()
            smtp.login(sender, password)
            smtp.send_message(message)
        return True
    except Exception:
        return False


def _streak(state, key, active):
    streaks = state.setdefault("pager_streaks", {})
    streaks[key] = streaks.get(key, 0) + 1 if active else 0
    return streaks[key]


def _transition(state, key, firing, down_text, up_text):
    open_pages = state.setdefault("pager_open", [])
    if firing and key not in open_pages:
        open_pages.append(key)
        return [down_text]
    if not firing and key in open_pages:
        open_pages.remove(key)
        return [up_text]
    return []


def health_events(records, state):
    """Return page texts for a dead webhook and for any other sensor stuck at unknown."""
    by_sensor = {item["sensor"]: item for item in records}
    webhook_down = all(by_sensor.get(name, {}).get("status") == "unknown"
                       for name in WEBHOOK_SENSORS)
    cycles = _streak(state, "webhook", webhook_down)
    events = _transition(state, "webhook", cycles >= WEBHOOK_DOWN_CYCLES,
                         "Hermes: k3dm webhook DOWN (no health for 2 polls). "
                         "Try: make restart-webhook",
                         "Hermes: k3dm webhook recovered")
    for item in records:
        name = item["sensor"]
        if name in WEBHOOK_SENSORS:
            continue
        cycles = _streak(state, f"unknown:{name}", item["status"] == "unknown")
        events += _transition(state, f"unknown:{name}", cycles >= SENSOR_UNKNOWN_CYCLES,
                              f"Hermes: {name} check unknown 30+ min: {item['evidence']}",
                              f"Hermes: {name} check recovered")
    return events


def job_events(state, failure):
    """Return page texts for the Hermes poll job failing (failure = exception name or None)."""
    cycles = _streak(state, "job", failure is not None)
    return _transition(state, "job", cycles >= JOB_FAILURE_CYCLES,
                       f"Hermes: poll job failing ({failure}). "
                       "Check ~/Library/Logs/k3dm-hermes.log",
                       "Hermes: poll job recovered")


def _open_severe(github_get, headers, repo):
    ids = []
    for alert in github_get(f"/repos/{repo}/code-scanning/alerts?state=open&per_page=100",
                            headers):
        if ((alert.get("rule") or {}).get("security_severity_level") or "").lower() in SEVERE:
            ids.append(f"code-scanning #{alert.get('number')}")
    for alert in github_get(f"/repos/{repo}/dependabot/alerts?state=open&per_page=100",
                            headers):
        advisory = alert.get("security_advisory") or {}
        vuln = alert.get("security_vulnerability") or {}
        if ((advisory.get("severity") or vuln.get("severity")) or "").lower() in SEVERE:
            ids.append(f"dependabot #{alert.get('number')}")
    return ids


def security_events(github_get, keychain, state, this_hour, token_service, repo):
    """Once per UTC hour, page on newly opened critical/high CodeQL or Dependabot alerts."""
    if state.get("pager_security_hour") == this_hour:
        return []
    token = keychain(token_service)
    if not token:
        return []
    try:
        current = _open_severe(github_get, {"Authorization": f"token {token}"}, repo)
    except Exception:
        return []
    state["pager_security_hour"] = this_hour
    seen = set(state.get("pager_security_seen", []))
    new = [item for item in current if item not in seen]
    state["pager_security_seen"] = sorted(current)
    if not new:
        return []
    return [f"Hermes security: {len(new)} new critical/high alert(s) in {repo}: "
            + ", ".join(new)]


def deliver(texts, state, today, send, budget=10):
    """Send texts within the per-UTC-day SMS budget; return the texts actually sent."""
    counter = state.setdefault("pager_budget", {"day": today, "count": 0})
    if counter.get("day") != today:
        counter.update({"day": today, "count": 0})
    sent = []
    for text in texts:
        if counter["count"] >= budget:
            break
        counter["count"] += 1
        if send(text):
            sent.append(text)
    return sent
