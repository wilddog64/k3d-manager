# Bug: `bin/acg-sync-apps` readiness check uses https:// but ArgoCD serves plain HTTP

**Date:** 2026-04-24
**Status:** OPEN
**Severity:** HIGH (make sync-apps always fails — port-forward never deemed ready)
**Branch:** `k3d-manager-v1.1.0`

## Summary

`bin/acg-sync-apps` checks ArgoCD port-forward readiness with:

```bash
curl -sk --max-time 1 https://localhost:8080/
```

But `deploy_argocd` installs ArgoCD with `--set "server.insecure=true"` (argocd.sh line 153),
which means the argocd-server container serves plain HTTP on port 8080. The Kubernetes service
maps port 443 → container port 8080 (HTTP). When the port-forward delivers the bytes to the
container, the container sees a TLS ClientHello on an HTTP-only listener — the handshake fails,
the connection is closed, and `kubectl port-forward` logs:

```text
Handling connection for 8080
```

The `curl` call returns non-zero for every iteration of the 15-second readiness loop, the
port-forward process exits (nothing to keep it alive), and the script exits 1 with those
"Handling connection for 8080" lines appearing in the make output via the log tail.

`scripts/plugins/argocd.sh` already uses the correct form at line 68:

```bash
curl -sf http://localhost:8080/healthz >/dev/null 2>&1
```

## Root Cause

Two places in `bin/acg-sync-apps` use the wrong scheme and path:

| Location | Line | Current (wrong) | Should be |
|---|---|---|---|
| `_sync_apps_reconcile_port_forward` | 105 | `curl -sk --max-time 1 https://localhost:"${pf_port}"/` | `curl -sf --max-time 1 http://localhost:"${pf_port}"/healthz` |
| main readiness loop | 151 | `curl -sk --max-time 1 https://localhost:8080/` | `curl -sf --max-time 1 http://localhost:8080/healthz` |

Note: `-k` (skip TLS verify) is replaced with `-f` (fail on HTTP error) since the endpoint is
plain HTTP and a non-200 response should be treated as not-ready.

## Fix

**File:** `bin/acg-sync-apps`

**Old line 105:**
```bash
    if curl -sk --max-time 1 https://localhost:"${pf_port}"/ >/dev/null 2>&1; then
```

**New line 105:**
```bash
    if curl -sf --max-time 1 http://localhost:"${pf_port}"/healthz >/dev/null 2>&1; then
```

**Old line 151:**
```bash
    if curl -sk --max-time 1 https://localhost:8080/ >/dev/null 2>&1; then
```

**New line 151:**
```bash
    if curl -sf --max-time 1 http://localhost:8080/healthz >/dev/null 2>&1; then
```

Two lines changed. No other lines change.

---

## Before You Start

1. `git pull origin k3d-manager-v1.1.0`
2. Read `bin/acg-sync-apps` lines 100–155 in full.
3. Read `scripts/plugins/argocd.sh` line 68 — confirms the correct form: `curl -sf http://localhost:8080/healthz`.
4. Read `scripts/plugins/argocd.sh` line 153 — confirms `--set "server.insecure=true"`.
5. Run `shellcheck -x bin/acg-sync-apps` — must exit 0 before and after.

---

## Rules

- `shellcheck -x bin/acg-sync-apps` must exit 0.
- Only `bin/acg-sync-apps` may be touched.
- Do NOT add `--no-verify` to any git command.
- Do NOT commit to `main`.
- Do NOT create a PR.

---

## Definition of Done

1. `bin/acg-sync-apps` line 105 matches the **New line 105** block above exactly.
2. `bin/acg-sync-apps` line 151 matches the **New line 151** block above exactly.
3. `shellcheck -x bin/acg-sync-apps` exits 0.
4. Committed on `k3d-manager-v1.1.0` with message:
   ```
   fix(acg-sync-apps): use http://healthz readiness check matching ArgoCD insecure mode
   ```
5. Branch pushed to `origin/k3d-manager-v1.1.0` before reporting done.
6. `memory-bank/activeContext.md`: add entry for this fix as COMPLETE with real commit SHA under Open Items.
7. `memory-bank/progress.md`: add `[x] **acg-sync-apps https vs http readiness** — COMPLETE (<sha>)` under Known Bugs / Gaps.
8. Report back: commit SHA + paste the memory-bank lines you updated.

---

## What NOT To Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside `bin/acg-sync-apps`.
- Do NOT commit to `main`.
- Do NOT change any other curl calls or port-forward logic — only lines 105 and 151.
