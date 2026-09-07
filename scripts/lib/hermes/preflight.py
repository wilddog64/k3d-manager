"""Dependency-injected PAT credential and Actions-scope preflight."""

import json

from hermes.sensors import ARGOCD_SERVICE, GITHUB_SERVICE, WEBHOOK_SERVICE

REPOSITORY = "wilddog64/k3d-manager"


def _secrets(keychain):
    return {
        "webhook": bool(keychain(WEBHOOK_SERVICE)),
        "argocd": bool(keychain(ARGOCD_SERVICE)),
        "pat": bool(keychain(GITHUB_SERVICE)),
    }


def run_preflight(keychain, runner):
    """Return a scope report and exit code; runner(argv, env, cwd) returns (rc, output)."""
    secrets = _secrets(keychain)
    report = {"secrets": secrets, "github_auth": "pat",
              "actions_read": False, "actions_write": False}
    if not (secrets["webhook"] and secrets["argocd"] and secrets["pat"]):
        return report, 1

    env = {"GH_TOKEN": keychain(GITHUB_SERVICE)}
    read_rc, read_output = runner(
        ["gh", "api", f"/repos/{REPOSITORY}/actions/runs?per_page=30"], env, None)
    if read_rc != 0:
        return report, 1
    report["actions_read"] = True
    try:
        runs = json.loads(read_output).get("workflow_runs", [])
        succeeded = next(run for run in runs if run.get("conclusion") == "success")
        run_id = succeeded["id"]
    except (KeyError, StopIteration, ValueError, TypeError):
        return report, 1
    _write_rc, write_output = runner(
        ["gh", "api", "--method", "POST",
         f"/repos/{REPOSITORY}/actions/runs/{run_id}/rerun-failed-jobs"], env, None)
    report["actions_write"] = bool(write_output) and "resource not accessible" not in write_output.lower()
    return report, 0 if report["actions_write"] else 1
