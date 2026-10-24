# Bug: the status ArgoCD login check reports "HTTP unavailable" for a rejected password, and nothing outside hub recovery repairs the stale Vault copy

**Status:** LANDED `9f48d5f0` 2026-10-23 — E1 green (pytest test_smoke_logins.py 18, bats hub_recovery.bats 58, shellcheck clean); the 401 and non-JSON-200 tests red on the pre-fix `smoke.py`. Pending E2: the operator runs `make argocd-admin-resync` from tmux, then a status report shows ArgoCD login HTTP 200.
**Priority:** P3 — ArgoCD itself and ArgoCD SSO are healthy; only the admin-password check fails, and the operator can read `argocd-initial-admin-secret`
**Severity:** low
**Release:** v1.43.5 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-23, by Claude, from the 19:55 PDT status report in #grafana-notification (job `c4b35b3c`: 20 ok / 1 fail)
**Approval:** explicit 2026-10-23. The operator said: "go ahead" (dispatch; critical because it changes the hub webhook)
**Related:** `docs/bugs/2026-10-18-argocd-admin-vault-copy-never-revalidated-after-rebuild.md`, `docs/bugs/2026-10-18-argocd-app-sync-stale-vault-admin-password.md`
**Component:** `scripts/lib/webhook/smoke.py` (`_smoke_post`, `_smoke_argocd_login`), `scripts/plugins/hub_recovery.sh` (`_hub_recovery_mirror_argocd_admin`)

## Problem

Every retained status job since 2026-10-20 13:58 PDT (the oldest kept) reports
`ArgoCD login: admin via Vault argocd/admin: HTTP unavailable`, while `ArgoCD: HTTP 200` and
`ArgoCD SSO login: code received` pass in the same report.

1. **The message is wrong.** `_smoke_post` does not catch `urllib.error.HTTPError`, unlike
   `_smoke_http_code`. A 401 from `POST /api/v1/session` raises, `_smoke_argocd_login`'s bare
   `except Exception` catches it, and the report says "HTTP unavailable". A rejected password and an
   unreachable server read the same. The public endpoint is reachable: `GET /api/version` returns
   200 JSON (`v3.5.5`) and `GET /api/v1/session` returns 405.
2. **The likely cause is a stale Vault copy that nothing repairs.** `argocd.3ai-talk.org` is the hub
   ArgoCD (`cicd/argocd-cm` `url`; `admin.enabled=true`). The hub was rebuilt on 2026-10-16
   (`argocd-secret` and `argocd-initial-admin-secret` created 02:08/02:11Z). The 10-18 fix
   (`_hub_recovery_mirror_argocd_admin`, which revalidates Vault `secret/argocd/admin` and replaces a
   rejected value) runs only inside `hub_recovery_reconcile`, so it has not run since it landed.
   `make show-service-passwords` only reports the copy as stale.

Not yet proven: Claude did not read or send the password. The operator's
`make show-service-passwords` prints `Vault secret/argocd/admin is stale (rejected by ArgoCD)` if
cause 2 holds.

## Fix

- **F1.** `_smoke_post` returns `(code, body)` for an `HTTPError`, as `_smoke_http_code` does; only a
  connection-level failure is "HTTP unavailable". `_smoke_argocd_login` reports `HTTP 401` (and any
  non-JSON 200 as `HTTP 200, no token`).
- **F2.** Expose the mirror on its own: `make argocd-admin-resync` runs
  `_hub_recovery_mirror_argocd_admin` against the hub context (revalidate; replace only when ArgoCD
  rejects it; keep the value when ArgoCD is unreachable). It prints no secret.

## Files

- `scripts/lib/webhook/smoke.py`
- `scripts/plugins/hub_recovery.sh` (only if a thin public wrapper is needed for the make target)
- `Makefile` (`argocd-admin-resync`, `.PHONY`)
- `scripts/tests/bin/test_smoke_logins.py`
- `scripts/tests/plugins/hub_recovery.bats`
- `README.md` (make target list), `CHANGELOG.md`

## Tests

- `scripts/tests/bin/test_smoke_logins.py` (existing; stub `urlopen`): a 401 on the session POST reports
  `HTTP 401`, not "unavailable"; a connection error still reports "HTTP unavailable"; other
  `_smoke_post` callers (Keycloak token, Grafana login) see the same codes they do today.
- `scripts/tests/plugins/hub_recovery.bats`: `make argocd-admin-resync` calls only the mirror (no
  other reconcile step), with stubbed `kubectl` and `curl`.

Show the 401 test red against the pre-fix `smoke.py`.

## Acceptance

```yaml
must:
  - id: M1
    text: A rejected ArgoCD admin login is reported with its HTTP status; "HTTP unavailable" means no HTTP response.
  - id: M2
    text: make argocd-admin-resync revalidates Vault secret/argocd/admin against the hub ArgoCD and replaces it only when ArgoCD rejects it.
must_not:
  - id: N1
    text: No secret value appears in the status report, the make output or test output.
  - id: N2
    text: argocd-admin-resync must not run any other hub recovery step, and must not overwrite Vault when ArgoCD is unreachable.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, N1, N2]
    text: pytest test_smoke_logins.py and bats hub_recovery.bats green; the 401 test red on the pre-fix smoke.py.
  - id: E2
    kind: live
    proves: [M1, M2]
    text: Before the resync the status report shows ArgoCD login HTTP 401; the operator runs make argocd-admin-resync; the next status report shows ArgoCD login HTTP 200.
interface:
  - status report line "ArgoCD login"
  - make argocd-admin-resync
  - Vault secret/argocd/admin (field password)
```

## Definition of Done

- [ ] F1, F2 and a CHANGELOG `[Unreleased]` `### Fixed` entry; README make-target list updated.
- [ ] Tests green; the 401 test shown red on a temp copy of the pre-fix code.
- [ ] Commit: `fix(status): report ArgoCD login rejections and add argocd-admin-resync`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT print, log or compare the password outside the existing redaction path.
- Do NOT modify files outside the Files list.
- Do NOT run `hub_recovery_reconcile`, `kubectl` or the real webhook from tests.
