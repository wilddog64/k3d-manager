# Bug: `POST /api/v1/cluster {"action": "trust-vault-ca"}` is authorized for a reader token

**Status:** LANDED `d4dbe1ac` 2026-11-07 (Luna; Claude review tightened the flag check to `bool()`, matching `do_POST`). Offline: 31/31 pass; 4 fail on pre-fix code, N1 included
**Priority:** P2
**Waiting on:** live check — since 2026-11-07
**Fix commit:** `d4dbe1ac`
**Introduced by:** `ecae8a73` (v1.43.14)
**Should have been caught by:** review
**Severity:** medium — a token with the lowest role can start an admin-classed job on the hub (`bin/cluster-up --trust-vault-ca`, which can raise a SecurityAgent dialog on the hub's screen and pushes a deployment metric); no secret is exposed, because the Vault CA certificate is public
**Branch:** `k3d-manager-v1.43.15`
**Release:** v1.43.15 if there is room, otherwise the first item of the next bug-fix patch (pre-existing P2 found during a release)
**Filed:** 2026-11-07, by Claude, confirming a finding from the Argon baseline critique of the 2026-11-03 spec
**Approval:** operator, 2026-11-07 ("go for it")
**Assigned:** Luna (`gpt-6-luna`, Codex)
**Component:** `scripts/lib/webhook/policy.py` (`_action_policy`), `bin/k3dm-webhook` (`do_POST`, cluster handler)
**Related:** [`2026-11-03-vault-ca-trust-target-and-headless-sudoers-probe`](2026-11-03-vault-ca-trust-target-and-headless-sudoers-probe.md) (added the action)

## Problem

`do_POST` resolves the policy with `effective_policy(route, self.path, body)` (`bin/k3dm-webhook:2434`)
before the cluster handler turns `action == "trust-vault-ca"` into `action = "up", trust_vault_ca = True`
(`bin/k3dm-webhook:2522-2525`). `_action_policy` (`scripts/lib/webhook/policy.py:169-176`) knows only
`kill`, `up` and `down`, so it returns `None` for `trust-vault-ca`, and `effective_policy` falls back to the
route's `min_role`, which is `reader` (`bin/k3dm-webhook:2242`).

Offline probe on 2026-11-07, run against this branch (scratch HOME, `scripts/lib` on `sys.path`):

```text
{'action': 'trust-vault-ca'} -> {'name': 'cluster', 'min_role': 'reader'}
{'action': 'up', 'provider': 'aws', 'trust_vault_ca': True} -> {'name': 'cluster-up', 'min_role': 'admin', 'provider': 'aws'}
```

The same operation through `/api/v1/make` (`MAKE_TARGETS["trust-vault-ca"]`, `min_role: admin`) is gated
correctly, and that is the only path the 2026-11-03 Acceptance tested.

## Fix scope

Give `trust-vault-ca` its own admin policy in `_action_policy`, for both the `action` form and the
`trust_vault_ca: true` flag, so that neither depends on how `do_POST` rewrites the body. Keep the audit
name distinct from `cluster-up`. Do not change any other route's role.

## Files

- `scripts/lib/webhook/policy.py`
- `scripts/tests/bin/webhook_policy.py`
- `CHANGE.md`

## Acceptance

```yaml
interface:
  - "python: from webhook import policy; policy.effective_policy(route, '/api/v1/cluster', body) with route {'handler': 'cluster', 'min_role': 'reader', 'action_name': 'cluster'}"
  - "env: scratch HOME; scripts/lib on sys.path"
must:
  - id: M1
    text: "body {'action': 'trust-vault-ca'} resolves to min_role admin."
  - id: M2
    text: "body {'action': 'up', 'provider': 'aws', 'trust_vault_ca': True} resolves to min_role admin, with a policy name other than cluster-up."
  - id: M3
    text: "bodies {'action': 'up'}, {'action': 'down'} and {'action': 'kill'} resolve exactly as before (admin, admin, operator)."
must_not:
  - id: N1
    text: "a reader role passes the policy for body {'action': 'trust-vault-ca'} (red on pre-fix code)."
  - id: N2
    text: "a cloud-runner role passes the policy for the trust_vault_ca flag body."
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    text: "webhook_policy.py tests; N1 shown red against pre-fix policy.py"
  - id: E2
    proves: [N1]
    kind: live
    text: "operator or Claude: a reader-token POST of {'action': 'trust-vault-ca'} to the hub webhook returns 403 after the fix is deployed"
```
