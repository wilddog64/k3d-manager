import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))

from hermes.preflight import run_preflight


def keychain(values):
    return lambda service: values.get(service, "")


def runner(read_rc=0, write_output="This workflow run cannot be retried"):
    def run(argv, env, cwd):
        assert env == {"GH_TOKEN": "pat"}
        assert cwd is None
        if "--method" in argv:
            return 1, write_output
        return read_rc, json.dumps({"workflow_runs": [{"id": 123, "conclusion": "success"}]})
    return run


def secrets(**overrides):
    values = {
        "k3dm-webhook-token": "webhook",
        "k3dm-hermes-argocd-token": "argocd",
        "k3dm-hermes-gh-token": "pat",
    }
    values.update(overrides)
    return values


def test_preflight_requires_all_required_secrets():
    report, code = run_preflight(keychain(secrets(**{"k3dm-hermes-gh-token": ""})), runner())

    assert code == 1
    assert report["secrets"]["pat"] is False


def test_preflight_fails_when_actions_read_fails():
    report, code = run_preflight(keychain(secrets()), runner(read_rc=1))

    assert code == 1
    assert report["actions_read"] is False


def test_preflight_fails_when_actions_write_is_missing():
    report, code = run_preflight(keychain(secrets()), runner(
        write_output="Resource not accessible by personal access token"))

    assert code == 1
    assert report["actions_read"] is True
    assert report["actions_write"] is False


def test_preflight_accepts_cannot_be_retried_as_actions_write_present():
    report, code = run_preflight(keychain(secrets()), runner())

    assert code == 0
    assert report["actions_read"] is True
    assert report["actions_write"] is True
