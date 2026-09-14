#!/usr/bin/env bats
# shellcheck shell=bash

@test "hub ESO rows use the hub context and prefix" {
    local repo_root
    repo_root="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
    run env K3DM_WEBHOOK_PATH="${repo_root}/bin/k3dm-webhook" python3 - <<'PY'
import importlib.machinery
import json
import os

webhook = importlib.machinery.SourceFileLoader(
    "k3dm_webhook", os.environ["K3DM_WEBHOOK_PATH"]
).load_module()
calls = []
css = {"status": {"conditions": [{"type": "Ready", "status": "False"}]}}
items = [
    {"metadata": {"name": f"secret-{index}"},
     "status": {"conditions": [{"type": "Ready", "status": "False"}]}}
    for index in range(24)
] + [{"metadata": {"name": "ready-secret"},
      "status": {"conditions": [{"type": "Ready", "status": "True"}]}}]

def fake(command, timeout):
    calls.append(command)
    return (json.dumps(css if command[2] == "clustersecretstore" else {"items": items}), False)

webhook._posix_spawn_capture = fake
results = webhook._eso_health_results("k3d-k3d-cluster", "Hub ")
assert results[0] == ("Hub ESO ClusterSecretStore", False, "Ready=False")
assert results[1][0] == "Hub ESO ExternalSecrets"
assert results[1][1] is False
assert results[1][2].startswith("24/25 not synced")
assert all(command[command.index("--context") + 1] == "k3d-k3d-cluster" for command in calls)
PY
    [ "$status" -eq 0 ]
}

@test "app ESO rows keep legacy names" {
    local repo_root
    repo_root="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
    run env K3DM_WEBHOOK_PATH="${repo_root}/bin/k3dm-webhook" python3 - <<'PY'
import importlib.machinery
import json
import os

webhook = importlib.machinery.SourceFileLoader(
    "k3dm_webhook", os.environ["K3DM_WEBHOOK_PATH"]
).load_module()
css = {"status": {"conditions": [{"type": "Ready", "status": "True"}]}}
items = [
    {"metadata": {"name": f"secret-{index}"},
     "status": {"conditions": [{"type": "Ready", "status": "True"}]}}
    for index in range(20)
]

def fake(command, timeout):
    return (json.dumps(css if command[2] == "clustersecretstore" else {"items": items}), False)

webhook._posix_spawn_capture = fake
results = webhook._eso_health_results("ubuntu-hostinger")
assert results == [
    ("ESO ClusterSecretStore", True, "Ready=True"),
    ("ESO ExternalSecrets", True, "20/20 synced"),
]
PY
    [ "$status" -eq 0 ]
}

@test "absent ESO CRD is skipped rather than failed" {
    local repo_root
    repo_root="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
    run env K3DM_WEBHOOK_PATH="${repo_root}/bin/k3dm-webhook" python3 - <<'PY'
import importlib.machinery
import json
import os

webhook = importlib.machinery.SourceFileLoader(
    "k3dm_webhook", os.environ["K3DM_WEBHOOK_PATH"]
).load_module()

def fake(command, timeout):
    if command[2] == "externalsecret":
        return ('error: the server doesn\'t have a resource type "externalsecret"', False)
    return (json.dumps({"status": {"conditions": [{"type": "Ready", "status": "True"}]}}), False)

webhook._posix_spawn_capture = fake
results = webhook._eso_health_results("ubuntu-hostinger")
assert results[1][1] is None
assert "not installed" in results[1][2]
PY
    [ "$status" -eq 0 ]
}

@test "smoke test ESO wiring samples app and hub through helper" {
    local repo_root
    repo_root="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
    run env K3DM_WEBHOOK_PATH="${repo_root}/bin/k3dm-webhook" python3 - <<'PY'
import importlib.machinery
import inspect
import os

webhook = importlib.machinery.SourceFileLoader(
    "k3dm_webhook", os.environ["K3DM_WEBHOOK_PATH"]
).load_module()
source = inspect.getsource(webhook._smoke_test_services)
assert "_eso_health_results(app_context)" in source
assert "_eso_health_results(\"k3d-k3d-cluster\", \"Hub \")" in source
assert "clustersecretstore" not in source
PY
    [ "$status" -eq 0 ]
}
