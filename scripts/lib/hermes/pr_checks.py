"""Collect and render the CI check state of open pull requests."""

import re
from datetime import datetime


REPOS = ("wilddog64/k3d-manager", "wilddog64/lib-foundation")
MAX_PRS = 20
FAILED = ("failure", "timed_out", "action_required", "startup_failure", "stale")
RUNNING = ("queued", "in_progress", "waiting", "requested", "pending")


def _epoch(value):
    if not value:
        return None
    return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()


def collect(fetch, repo):
    """Collect open PRs and their latest check run for each check name."""
    pulls = fetch(f"/repos/{repo}/pulls?state=open&per_page={MAX_PRS}")
    if not isinstance(pulls, list):
        raise ValueError("invalid pull request response")
    result = []
    for pull in pulls:
        head_sha = pull["head"]["sha"]
        runs = fetch(f"/repos/{repo}/commits/{head_sha}/check-runs?per_page=100")
        if not isinstance(runs, dict) or not isinstance(runs.get("check_runs"), list):
            raise ValueError("invalid check-runs response")
        newest = {}
        for run in runs["check_runs"]:
            name = run["name"]
            if name not in newest or run["id"] > newest[name]["id"]:
                newest[name] = run
        checks = []
        for run in newest.values():
            status = run.get("status")
            checks.append({
                "name": str(run.get("name", "")),
                "state": run.get("conclusion") if status == "completed" else status,
                "started": _epoch(run.get("started_at")),
                "completed": _epoch(run.get("completed_at")),
            })
        result.append({
            "number": int(pull["number"]),
            "title": str(pull.get("title", "")),
            "head": head_sha[:8],
            "draft": bool(pull.get("draft", False)),
            "checks": checks,
        })
    return result


def overall(checks):
    states = [check.get("state") for check in checks]
    if not states:
        return "none"
    if any(state in FAILED for state in states):
        return "failure"
    if any(state in RUNNING for state in states):
        return "running"
    return "success"


def label(value, limit=100):
    """Return a bounded Prometheus label value."""
    value = re.sub(r"[\\\"\t\r\n]", " ", str(value))
    value = re.sub(r"\s+", " ", value).strip()
    return value if len(value) <= limit else value[: limit - 1] + "…"


def _labels(values):
    return ",".join(f'{key}="{label(value)}"' for key, value in values.items())


def render(prs, now, repo):
    lines = []
    for pr in prs:
        base = {"repo": repo, "pr": pr["number"]}
        info = {**base, "title": pr["title"], "head": pr["head"],
                "draft": str(pr["draft"]).lower()}
        lines.append(f"k3dm_pr_info{{{_labels(info)}}} 1")
        lines.append(f"k3dm_pr_overall{{{_labels({**base, 'state': overall(pr['checks'])})}}} 1")
        for check in pr["checks"]:
            check_labels = {**base, "check": check["name"], "state": check["state"]}
            lines.append(f"k3dm_pr_check_state{{{_labels(check_labels)}}} 1")
            if check["started"] is not None:
                end = check["completed"] if check["completed"] is not None else now
                duration = end - check["started"]
                labels = _labels({**base, "check": check["name"]})
                lines.append(f"k3dm_pr_check_duration_seconds{{{labels}}} {duration}")
    labels = _labels({"repo": repo})
    lines.append(f"k3dm_pr_checks_open_prs{{{labels}}} {len(prs)}")
    lines.append(f"k3dm_pr_checks_last_scrape_timestamp_seconds{{{labels}}} {now}")
    lines.append(f"k3dm_pr_checks_scrape_success{{{labels}}} 1")
    return "\n".join(lines) + "\n"


def render_failure(now, repo):
    labels = _labels({"repo": repo})
    return (f"k3dm_pr_checks_last_scrape_timestamp_seconds{{{labels}}} {now}\n"
            f"k3dm_pr_checks_scrape_success{{{labels}}} 0\n")
