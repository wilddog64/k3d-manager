"""Dependency-injected GitHub App/PAT credential and Actions-scope preflight."""

import json

from hermes import github_app
from hermes.sensors import ARGOCD_SERVICE, GITHUB_SERVICE, WEBHOOK_SERVICE

APP_ID_SERVICE = "k3dm-hermes-app-id"
APP_INSTALLATION_SERVICE = "k3dm-hermes-app-installation-id"
APP_PRIVATE_KEY_SERVICE = "k3dm-hermes-app-private-key"
REPOSITORY = "wilddog64/k3d-manager"


def _secrets(keychain):
    return {
        "webhook": bool(keychain(WEBHOOK_SERVICE)),
        "argocd": bool(keychain(ARGOCD_SERVICE)),
        "app_id": bool(keychain(APP_ID_SERVICE)),
        "app_installation_id": bool(keychain(APP_INSTALLATION_SERVICE)),
        "app_private_key": bool(keychain(APP_PRIVATE_KEY_SERVICE)),
        "pat": bool(keychain(GITHUB_SERVICE)),
    }


def _github_token(keychain, secrets, now):
    if all(secrets[name] for name in ("app_id", "app_installation_id", "app_private_key")):
        return github_app.installation_token(
            keychain(APP_ID_SERVICE), keychain(APP_INSTALLATION_SERVICE),
            keychain(APP_PRIVATE_KEY_SERVICE), now=now,
        ), "github-app"
    return keychain(GITHUB_SERVICE), "pat"


def run_preflight(keychain, runner, now=None):
    """Return a scope report and exit code; runner(argv, env, cwd) returns (rc, output)."""
    secrets = _secrets(keychain)
    app_ready = all(secrets[name] for name in ("app_id", "app_installation_id", "app_private_key"))
    report = {"secrets": secrets, "github_auth": "github-app" if app_ready else "pat",
              "actions_read": False, "actions_write": False}
    if not (secrets["webhook"] and secrets["argocd"] and (app_ready or secrets["pat"])):
        return report, 1

    token, _backend = _github_token(keychain, secrets, now)
    env = {"GH_TOKEN": token}
    read_rc, read_output = runner(
        ["gh", "api", f"/repos/{REPOSITORY}/actions/runs?per_page=1"], env, None)
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
    report["actions_write"] = "resource not accessible" not in write_output.lower()
    return report, 0 if report["actions_write"] else 1
