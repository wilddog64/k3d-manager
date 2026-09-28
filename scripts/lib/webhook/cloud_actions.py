"""Shared cloud-session action definitions."""

import re


JOB_ID_RE = re.compile(r"[0-9a-f]{8,64}")
NS_RE = re.compile(r"[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?")
# Prose search text. Kept byte-identical to webhook _ARG_PATTERNS["Q"]: every shell
# metacharacter is excluded because the value reaches a Makefile recipe.
Q_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9 ._,:/?!-]{0,199}")
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
    "make-test-pytest": ("POST", "/api/v1/make", {}, "test-pytest"),
    "make-test-python-unit": ("POST", "/api/v1/make", {}, "test-python-unit"),
    "make-find-similar-docs": ("POST", "/api/v1/make", {"Q": Q_RE}, "find-similar-docs"),
}
