"""`/cluster-diagnose <provider>` lists pods in every namespace; per-pod verbs stay allowlisted."""

import importlib.util
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))

from webhook import status  # noqa: E402

_WEBHOOK = ROOT / "bin" / "k3dm-webhook"
_spec = importlib.util.spec_from_file_location(
    "k3dm_webhook_diag", _WEBHOOK, loader=SourceFileLoader("k3dm_webhook_diag", str(_WEBHOOK))
)
wh = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(wh)


def test_get_pods_all_needs_no_namespace_and_drops_one_sent():
    body = {"provider": "hub", "action": "get-pods-all", "namespace": "kube-system"}
    assert wh._validate_diagnostics_request(body) is None
    assert "namespace" not in body
    assert body["context"] == "k3d-k3d-cluster"


def test_get_pods_all_still_requires_an_approved_context():
    body = {"action": "get-pods-all", "context": "some-other-cluster"}
    assert wh._validate_diagnostics_request(body) == "unsupported diagnostics context"


@pytest.mark.parametrize("namespace", ["shopping-cart-payment", "shopping-cart-data"])
@pytest.mark.parametrize("action", ["get-pods", "describe-pod", "logs"])
def test_payment_and_data_namespaces_are_approved(namespace, action):
    body = {"provider": "hub", "action": action, "namespace": namespace, "name": "payment-0"}
    assert wh._validate_diagnostics_request(body) is None


@pytest.mark.parametrize("action", ["get-pods", "describe-pod", "logs"])
def test_per_pod_verbs_still_refuse_unapproved_namespaces(action):
    body = {"provider": "hub", "action": action, "namespace": "kube-system", "name": "coredns-0"}
    assert wh._validate_diagnostics_request(body) == "namespace must be one of the approved repo-owned namespaces"


def test_get_pods_all_runs_kubectl_across_all_namespaces(tmp_path, monkeypatch):
    job_id = "diag-all"
    (tmp_path / job_id).mkdir()
    calls = []
    posted = []
    monkeypatch.setattr(status, "JOB_DIR", tmp_path)
    monkeypatch.setattr(status, "_spawn_capture_text",
                        lambda cmd, **_k: (calls.append(cmd), (0, "NAMESPACE NAME READY\nkube-system coredns 1/1", False))[1])
    monkeypatch.setattr(status, "_slack_post", lambda _url, text: posted.append(text))
    monkeypatch.setattr(status, "_notify_job", lambda _job, text: posted.append(text))
    monkeypatch.setattr(status, "_redact_secrets", lambda text: text)

    status._run_cluster_diagnostics(job_id, "https://example.test/response",
                                    request={"action": "get-pods-all", "context": "ubuntu-k3s", "provider": "aws"})

    assert calls == [["kubectl", "get", "pods", "--all-namespaces", "--context", "ubuntu-k3s",
                      "-o", "wide", "--request-timeout=15s"]]
    assert (tmp_path / job_id / "status").read_text() == "success"
    assert "pods in all namespaces on `ubuntu-k3s`" in posted[0]
    assert "kube-system coredns" in posted[0]
