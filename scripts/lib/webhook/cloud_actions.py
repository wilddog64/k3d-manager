"""Shared cloud-session action definitions."""

import re


JOB_ID_RE = re.compile(r"[0-9a-f]{8,64}")
NS_RE = re.compile(r"[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?")
# Prose search text. Kept byte-identical to webhook _ARG_PATTERNS["Q"]: every shell
# metacharacter is excluded because the value reaches a Makefile recipe.
Q_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9 ._,:/?!-]{0,199}")
RUNNER_RE = re.compile(r"[a-z0-9][a-z0-9-]{0,31}")
# The /cluster-diagnose provider set; the webhook resolves each to a kube context.
PROVIDER_RE = re.compile(r"hostinger|aws|gcp|az|hub")
# The webhook's _RESOURCE_NAME_RE without anchors (fullmatch anchors it here).
NAME_RE = re.compile(r"[a-z0-9]([-.a-z0-9]*[a-z0-9])?")
# The 4th element is the server-side fixed part of the request: a make target name, or for
# diagnostics a dict merged over the args so request content can never choose the webhook action.
ACTION_ALLOWLIST = {
    "health": ("GET", "/api/v1/health", {}, None),
    "cluster-status": ("POST", "/api/v1/cluster-status", {}, None),
    "hostinger-status": ("POST", "/api/v1/hostinger-status", {}, None),
    "job-status": ("GET", "/api/v1/status/{job_id}", {"job_id": JOB_ID_RE}, None),
    "make-fix-list": ("POST", "/api/v1/make", {}, "fix-list"),
    "make-fix-status": ("POST", "/api/v1/make", {"NS": NS_RE}, "fix-status"),
    "make-status-public": ("POST", "/api/v1/make", {}, "status-public"),
    "make-observability-status": ("POST", "/api/v1/make", {}, "observability-status"),
    "make-vuln-scan": ("POST", "/api/v1/make", {}, "vuln-scan"),
    "make-e2e-runner-health": ("POST", "/api/v1/make", {}, "e2e-runner-health"),
    "make-test": ("POST", "/api/v1/make", {}, "test"),
    "make-test-bin": ("POST", "/api/v1/make", {}, "test-bin"),
    "make-test-pytest": ("POST", "/api/v1/make", {}, "test-pytest"),
    "make-test-python-unit": ("POST", "/api/v1/make", {}, "test-python-unit"),
    "make-test-python": ("POST", "/api/v1/make", {}, "test-python"),
    "make-test-all": ("POST", "/api/v1/make", {}, "test-all"),
    "make-find-similar-docs": ("POST", "/api/v1/make", {"Q": Q_RE}, "find-similar-docs"),
    "make-e2e-remote": ("POST", "/api/v1/make", {"RUNNER": RUNNER_RE}, "e2e-remote"),
    "make-e2e": ("POST", "/api/v1/make", {}, "e2e"),
    "diagnose-pods": ("POST", "/api/v1/diagnostics",
                      {"provider": PROVIDER_RE, "namespace": NS_RE}, {"action": "get-pods"}),
    "diagnose-describe-pod": ("POST", "/api/v1/diagnostics",
                              {"provider": PROVIDER_RE, "namespace": NS_RE, "name": NAME_RE},
                              {"action": "describe-pod"}),
    "diagnose-logs": ("POST", "/api/v1/diagnostics",
                      {"provider": PROVIDER_RE, "namespace": NS_RE, "name": NAME_RE}, {"action": "logs"}),
    "diagnose-apps": ("POST", "/api/v1/diagnostics", {}, {"action": "get-apps", "provider": "hub"}),
    "diagnose-app": ("POST", "/api/v1/diagnostics", {"name": NAME_RE},
                     {"action": "describe-app", "provider": "hub"}),
    "diagnose-appsets": ("POST", "/api/v1/diagnostics", {}, {"action": "get-appsets", "provider": "hub"}),
}
