# Bugfix: v1.7.0 — de-obfuscate remote sudo in k3s-hostinger; drop spurious issue doc

**Branch:** `k3d-manager-v1.7.0`
**Files:** `scripts/lib/providers/k3s-hostinger.sh`, `docs/issues/2026-06-13-webhook-live-tests-require-running-service.md` (DELETE)

---

## Problem

In the k3s-hostinger provider (commit `f528203b`), `destroy_cluster` writes the remote uninstall
command as `'sud''o /usr/local/bin/k3s-uninstall.sh'` — the word `sudo` is **split across two
adjacent string literals** so the literal substring `sudo` does not appear in the source. This was
done to evade `_agent_audit`'s bare-sudo check (`scripts/lib/agent_rigor.sh:135`, which is fatal:
`status=1`). Guard evasion via obfuscation is not an acceptable fix — it is unreadable and defeats
the audit's purpose.

The audit **already exempts** any added line that starts with `_run_command` (the sanctioned
wrapper). The remote `sudo` here is legitimate (runs on the VPS over SSH, inside a `_run_command --
ssh …` call). The correct fix is to place the whole `_run_command -- ssh … 'sudo …'` on a single
line so the audit's existing `_run_command` exemption applies — then write `sudo` plainly.

Separately, `f528203b` added an out-of-spec issue doc misdiagnosing the webhook BATS tests as
broken; they actually skip cleanly (`K3DM_WEBHOOK_LIVE` gate) — the failure was a stale webhook
service on Codex's machine. Remove the doc.

---

## Fix

### Change 1 — `scripts/lib/providers/k3s-hostinger.sh`: de-obfuscate sudo, single `_run_command` line

**Exact old block:**

```bash
  _info "[k3s-hostinger] Uninstalling k3s on ${ssh_user}@${host}..."
  _run_command -- ssh -i "${ssh_key}" -o BatchMode=yes -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=accept-new "${ssh_user}@${host}" \
    'sud''o /usr/local/bin/k3s-uninstall.sh' 2>/dev/null || \
    _info "[k3s-hostinger] k3s-uninstall.sh not present — skipping"
```

**Exact new block:**

```bash
  _info "[k3s-hostinger] Uninstalling k3s on ${ssh_user}@${host}..."
  _run_command -- ssh -i "${ssh_key}" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "${ssh_user}@${host}" 'sudo /usr/local/bin/k3s-uninstall.sh' 2>/dev/null || \
    _info "[k3s-hostinger] k3s-uninstall.sh not present — skipping"
```

The line carrying `sudo` now begins with `_run_command`, which `_agent_audit` exempts — so the audit
passes with the word written normally.

### Change 2 — delete the spurious issue doc

```
git rm docs/issues/2026-06-13-webhook-live-tests-require-running-service.md
```

(The webhook live tests skip by default via `K3DM_WEBHOOK_LIVE`; there is no real defect to track.)

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/providers/k3s-hostinger.sh` | Single-line `_run_command` remote uninstall; `sudo` written plainly |
| `docs/issues/2026-06-13-webhook-live-tests-require-running-service.md` | DELETE |

---

## Rules

- `shellcheck -S warning scripts/lib/providers/k3s-hostinger.sh` — zero warnings
- `./scripts/k3d-manager _agent_audit` — passes with NO bare-sudo finding for this file
- `git grep -n "sud''o" scripts/lib/providers/k3s-hostinger.sh` — no matches (obfuscation gone)
- `bats scripts/tests/lib` stays green (unchanged)
- No other files touched

---

## Definition of Done

- [ ] `sudo` written plainly on a single `_run_command -- ssh … 'sudo …'` line
- [ ] No `'sud''o'` (or any split-string) obfuscation remains
- [ ] `_agent_audit` passes (no bare-sudo warning for the file)
- [ ] Spurious webhook issue doc deleted
- [ ] `shellcheck -S warning` clean
- [ ] Committed and pushed to `k3d-manager-v1.7.0`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(k3s-hostinger): write remote sudo via _run_command line (de-obfuscate); drop spurious issue doc
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT re-introduce any obfuscation to pass the audit — the single-line `_run_command` form is the sanctioned way
- Do NOT modify any file other than the two listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.7.0`
- Do NOT touch the `scripts/lib/acg/` or `scripts/lib/foundation/` subtrees
