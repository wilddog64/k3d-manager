"""Regression coverage for evidence-based k3s-aws SSH failure analysis."""

import importlib.util
from importlib.machinery import SourceFileLoader
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WEBHOOK = ROOT / "bin" / "k3dm-webhook"
spec = importlib.util.spec_from_file_location(
    "k3dm_webhook_ssh_failure_analysis",
    WEBHOOK,
    loader=SourceFileLoader("k3dm_webhook_ssh_failure_analysis", str(WEBHOOK)),
)
webhook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(webhook)


def test_ssh_timeout_analysis_requires_evidence_and_safe_stack_inspection(monkeypatch):
    prompts = []
    monkeypatch.setattr(webhook, "_collect_cluster_state", lambda: "")
    monkeypatch.setattr(webhook, "_call_gemini", lambda prompt: prompts.append(prompt) or "analysis")

    result = webhook._analyze_failure(
        [
            "ERROR: ubuntu@ubuntu did not answer SSH within 180s; not starting k3sup",
        ]
    )

    assert result == "analysis"
    assert len(prompts) == 1
    prompt = prompts[0]
    assert "using only observed evidence" in prompt
    assert "Treat absent state as unknown" in prompt
    assert "label possible explanations as hypotheses" in prompt
    assert "inspect the existing CloudFormation stack and EC2 state/status checks" in prompt
    assert "reuse a healthy stack" in prompt
    assert "do not recommend duplicate provisioning or teardown" in prompt
    assert "did not finish booting" not in prompt
    assert "online and ready" not in prompt
