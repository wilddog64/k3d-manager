#!/usr/bin/env python3
"""Configuration constants and filesystem-path helpers for k3dm-webhook.

Phase 1 of the in-repo modularization (see
docs/plans/v1.13.0-webhook-modularization.md): pure, side-effect-free
constants and path helpers extracted verbatim from bin/k3dm-webhook.
No command behavior changes.
"""

import os
import re
from pathlib import Path

PORT = int(os.environ.get("K3DM_WEBHOOK_PORT", "7443"))
MAX_BODY = 4096
_JOB_ID_RE = re.compile(r'^[0-9a-f]{8}$')

REPO_ROOT = os.environ.get(
    "K3DM_REPO_ROOT",
    str(Path.home() / "src/gitrepo/personal/k3d-manager")
)
SHOPPING_CARTS_ROOT = os.environ.get(
    "K3DM_SHOPPING_CARTS_ROOT",
    str(Path.home() / "src/gitrepo/personal/shopping-carts")
)
TOKEN_FILE = Path.home() / ".k3dm" / "webhook-token"
JOB_DIR = Path(os.environ.get("K3DM_JOB_DIR", Path.home() / ".local/share/k3d-manager/webhook-jobs"))
SCREENSHOT_DIR = Path.home() / ".local" / "share" / "k3d-manager" / "screenshots"
AUDIT_DIR = Path.home() / ".local" / "share" / "k3d-manager" / "audit"
RUN_DIR = Path(os.environ.get("K3DM_RUN_DIR", Path.home() / ".local/share/k3d-manager/run"))
_ASK_MAX_TURNS_DEFAULT = int(os.environ.get("K3DM_ASK_MAX_TURNS", "10"))
SLACK_WEBHOOK_URL = os.environ.get("K3DM_SLACK_WEBHOOK_URL", "")
PUSHGATEWAY_URL = os.environ.get("K3DM_PUSHGATEWAY_URL", "http://localhost:9091")
SLACK_BOT_TOKEN = os.environ.get("SLACK_BOT_TOKEN", "")
SLACK_CHANNEL_ID = os.environ.get("SLACK_CHANNEL_ID", "")
_PUSHGATEWAY_PUSH_RETRIES = 6
_PUSHGATEWAY_PUSH_SLEEP_SECS = 5
_ACTIVE_PROVIDER_FILE = Path.home() / ".local" / "share" / "k3d-manager" / "active-provider"


def _safe_job_dir(job_id):
    """Return resolved job directory only if it is a valid hex job ID and a direct child of JOB_DIR."""
    m = _JOB_ID_RE.match(job_id)
    if not m:
        raise ValueError(f"invalid job_id: {job_id!r}")
    safe_id = m.group(0)
    base = os.path.realpath(str(JOB_DIR))
    candidate = os.path.realpath(os.path.join(base, safe_id))
    if not candidate.startswith(base + os.sep) or os.path.dirname(candidate) != base:
        raise ValueError(f"invalid job_id: {job_id!r}")
    return Path(candidate)
