# Bug: `bin/argocd-app-sync` uses a stale Vault admin password after a hub rebuild and fails with a Python traceback

**Filed:** 2026-10-18 (Claude, from the operator's tmux pane)
**Status:** FIXED — awaiting operator E2 run
**Priority:** P3 — a workaround exists (pass `ARGOCD_ADMIN_PASSWORD`, or use the UI)
**Severity:** low
**Approval:** approved — operator, 2026-10-18: "can you dispath those two to codex?"
**Branch:** `k3d-manager-v1.43.5`
**Release:** v1.43.5
**Component:** `bin/argocd-app-sync`
**Fix commit:** `9ab8368b`

## Symptom

`bin/argocd-app-sync ubuntu-hostinger-data-layer` (2026-10-18, operator tmux):

```
json.decoder.JSONDecodeError: Expecting value: line 1 column 1 (char 0)
ArgoCD API login failed for localhost:8080
```

The port-forward on 8080 was live (`/healthz` 200, `/api/version` v3.5.5).

## Root cause

The admin-password lookup takes the first non-empty source: `ARGOCD_ADMIN_PASSWORD`, then Vault
`secret/argocd/admin`, then `argocd-initial-admin-secret`. After the 2026-10-16 hub rebuild,
`argocd-secret`'s `admin.passwordMtime` equals the creation time of `argocd-initial-admin-secret`
(2026-10-16T02:11:10Z), while Vault still held a non-empty older password. The helper never reached
the current one. `POST /api/v1/session` returned 401; `curl -sf` printed nothing, and the Python
one-liner that reads `["token"]` raised on empty input. Passing `ARGOCD_ADMIN_PASSWORD` from the
initial secret logged in.

## Fix

- **F1.** Try each candidate password in order (env, Vault, initial secret), and move to the next one
  when the session POST fails. Fail only after every candidate fails.
- **F2.** Parse the session response without a traceback. On failure, print one line naming the
  server and the sources tried (never a password), for example
  `ArgoCD API login failed for localhost:8080 (tried: vault, argocd-initial-admin-secret)`.
- Passwords stay off command lines and out of `set -x` output, as they are now.

## Acceptance

```yaml
must:
  - id: M1
    text: When the Vault password is rejected and the initial-admin-secret password is accepted, the helper logs in and runs argocd app sync.
  - id: M2
    text: When every candidate is rejected, the helper exits non-zero with one line naming the server and the sources tried.
  - id: M3
    text: ARGOCD_ADMIN_PASSWORD, when set and accepted, is used without reading Vault or the cluster.
must_not:
  - id: N1
    text: A rejected login must not print a Python traceback (red on pre-fix).
  - id: N2
    text: A rejected Vault password must not end the run while another source remains (red on pre-fix).
  - id: N3
    text: No password value appears in stdout, stderr or a command line.
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2, N3]
    kind: offline
    text: BATS in scripts/tests/bin/argocd_app_sync.bats with stubbed curl, kubectl and argocd on PATH; N1/N2 red against the pre-fix script.
  - id: E2
    proves: [M1]
    kind: live
    text: the operator runs bin/argocd-app-sync <app> with no env override against the rebuilt hub and it syncs.
interface:
  - bin/argocd-app-sync <app> [--force] [--timeout SECONDS]
  - env ARGOCD_ADMIN_PASSWORD, ARGOCD_SERVER
```

## Definition of Done

- [ ] F1, F2 in `bin/argocd-app-sync`; tests in `scripts/tests/bin/argocd_app_sync.bats`.
- [ ] N1, N2 red against the pre-fix script.
- [ ] Commit: `fix(argocd-app-sync): fall back past a rejected admin password`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`.
- Do NOT contact a real ArgoCD, Vault or cluster.
- Do NOT write a password to a file outside a `mktemp` path that is removed on exit.

## Verification log

- 2026-10-18: Codex `9ab8368b`; Claude verified the diff and `argocd_app_sync.bats` 11/11 green. Against
  the pre-fix script (`bb53fd99`, in a temporary worktree) tests 8–10 (env→Vault fallback,
  Vault→initial-secret fallback, single safe error) fail, the other 8 pass.
