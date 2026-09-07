# Bugfix — webhook `/ask` fix-mode role gating (F1) + `response_url` host allowlist (F3)

**Date:** 2026-09-07
**Source:** webhook-server security audit (`docs/issues/2026-09-07-webhook-server-security-audit.md`), findings F1 (HIGH) and F3 (MEDIUM).
**Branch:** `k3d-manager-v1.32.0`
**Files:** `bin/k3dm-webhook`, `scripts/lib/webhook/render.py`, `scripts/tests/lib/webhook.bats`

Two self-contained, audit-driven bugfixes landed together because both harden the same
`/ask` → Slack ingress path that the planned Hermes↔Slack approval feature will widen.

---

## F1 — `/ask` fix-mode privilege escalation (HIGH)

### Problem

`_run_cluster_ask(job_id, agent, question, response_url, thread_ts, max_turns)` was **never
passed the caller's role**. Whether the spawned agent ran in write-capable *fix mode* was decided
entirely by the question text:

```python
fixing = _is_fix_request(question)          # _FIX_RE: fix|heal|recover|repair|resolve|
                                            # remediate|restart|resync|re-sync|force.?sync|bounce
...
"K3DM_FIX_MODE": "1" if fixing else "0",
```

Because `ask` is `min_role: reader`, a **reader-tier Slack user could unlock state-changing
operations** (make `fix-*`, `kubectl rollout restart`, `kubectl delete pod`, `argocd app sync`)
simply by phrasing the question as "restart the crashlooping pod" / "resync app X". The
reader/operator/admin gate on write actions was bypassable through the AI path.

### Fix

Thread the caller role into `_run_cluster_ask` and gate fix mode on it via a small, unit-testable
predicate. `_FIX_RE` also matches diagnostic phrasing ("why does the pod keep restarting"), so a
reader is **downgraded to read-only**, not rejected — with a one-line notice prepended to the answer.

```python
def _fix_mode_enabled(question: str, role: str) -> bool:
    """Fix mode (write-capable agent) requires BOTH fix intent AND operator+ role."""
    return _is_fix_request(question) and _role_allows(role, "operator")
```

In `_run_cluster_ask` (signature gains `role="admin"`):

```python
fixing = _fix_mode_enabled(question, role)
if _is_fix_request(question) and not fixing:
    _fix_denied = True   # _finish() prepends "⚠️ Fix actions require *operator* role — ran read-only."
```

Both call sites now pass role:
- `_handle_thread_command` (Slack thread path) → `kwargs={..., "role": role}` (`slack_role`).
- `/api/v1/ask` handler (direct-token path) → `kwargs={..., "role": request_role}`.

The `default="admin"` preserves behavior for any internal caller that omits role (the single-admin-token
invariant, F4).

---

## F3 — `response_url` / `_slack_post` had no host allowlist → blind SSRF + output exfil (MEDIUM)

### Problem

`_slack_post(url, text)` POSTed job output to **whatever `url` it was given**, with no scheme/host
validation. `url` is the caller-supplied `response_url` from the request body. Slack's real
`response_url` is always `https://hooks.slack.com/…`, but the server trusted the relayed value —
enabling (a) **output exfiltration** to an attacker host and (b) a **blind-SSRF POST** primitive
against loopback services the laptop can reach (Vault `:18200`, ArgoCD `:8080`, k8s `:6443`).

### Fix

Central validation in `render.py` before any network call:

```python
_SLACK_POST_ALLOWED_HOSTS = frozenset({"hooks.slack.com", "slack.com"})

def _is_allowed_slack_url(url):
    if not url:
        return False
    parsed = urllib.parse.urlparse(url)
    return parsed.scheme == "https" and parsed.hostname in _SLACK_POST_ALLOWED_HOSTS

def _slack_post(url, text):
    if not _is_allowed_slack_url(url):
        return
    ...
```

`urlparse().hostname` lowercases the host and strips port/userinfo, so lookalikes like
`hooks.slack.com.attacker.example` and `hooks.slack.com@attacker.example` are rejected.

---

## Tests

`scripts/tests/lib/webhook.bats` (in CI via `scripts/tests/lib`):
- **"webhook fix mode requires operator+ role, not question phrasing"** — asserts `_fix_mode_enabled`
  returns `False` for reader + "restart pod" / "resync app foo", `True` for operator/admin + fix
  intent, and `False` for non-fix questions regardless of role.
- **"webhook _slack_post only targets https Slack hosts"** — asserts `_is_allowed_slack_url` accepts
  only `https` Slack hosts and rejects `http`, arbitrary hosts, loopback, subdomain/userinfo lookalikes,
  empty, and `None`.

Full suite: 57 tests, 0 failures.

## Not addressed here (tracked separately)

- **F2 (HIGH)** — `bin/k3dm-ask-bash` denylist / credential-dir read / GET egress → its own plan
  (`docs/plans/v1.32.0-ask-bash-sandbox-hardening.md`); must land **before** widening the Slack audience.
- **F4 (LOW)** — `X-K3DM-Role` header-asserted role; documented invariant, revisit if role-scoped tokens are added.
