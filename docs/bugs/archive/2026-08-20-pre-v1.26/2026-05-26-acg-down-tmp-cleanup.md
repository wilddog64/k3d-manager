# Bugfix: v1.4.10 — acg-down leaves stale /tmp files after teardown

**Branch:** `k3d-manager-v1.4.10`
**Files:** `bin/acg-down`

---

## Problem

Three categories of stale files accumulate in `/tmp` across `acg-up`/`acg-down` cycles and
are never cleaned up:

1. **`/tmp/argocd-*.sock`** — Unix domain sockets created by the `argocd` CLI each time it
   connects via `--port-forward`. The CLI creates a new socket per invocation and never
   removes it on exit. These accumulate indefinitely (51 found spanning May 2–18).

2. **`/tmp/k3d-config-tmp-*.yaml`** — Temporary k3d cluster config files written by the
   `k3d` binary during `k3d cluster create`. Left behind after cluster deletion.

3. **`/tmp/k3d-hostsfile-*`** — Temporary hosts file fragments written by the `k3d` binary
   during cluster create. Also left behind after cluster deletion.

**Root cause:** `acg-down` tears down the tunnel, CloudFormation stack, launchd agents, and
the k3d cluster, but has no `/tmp` cleanup step.

---

## Fix

### Change 1 — `bin/acg-down`: add /tmp cleanup step before final Done message

Insert after line 156 (`_info "[acg-down] --keep-hub set — local Hub cluster preserved."`),
before line 158 (`if [[ "${_keep_hub}" -eq 1 ]]; then`).

**Exact old block (lines 156–162):**

```bash
else
  _info "[acg-down] --keep-hub set — local Hub cluster preserved"
fi

if [[ "${_keep_hub}" -eq 1 ]]; then
  _info "[acg-down] Done. Remote cluster deleted; local Hub preserved."
else
  _info "[acg-down] Done. Remote cluster and local Hub deleted."
fi
```

**Exact new block:**

```bash
else
  _info "[acg-down] --keep-hub set — local Hub cluster preserved"
fi

_info "[acg-down] Cleaning up stale /tmp files..."
rm -f /tmp/argocd-*.sock
rm -f /tmp/k3d-config-tmp-*.yaml
rm -f /tmp/k3d-hostsfile-*
_info "[acg-down] /tmp cleanup complete"

if [[ "${_keep_hub}" -eq 1 ]]; then
  _info "[acg-down] Done. Remote cluster deleted; local Hub preserved."
else
  _info "[acg-down] Done. Remote cluster and local Hub deleted."
fi
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-down` | Add `/tmp` cleanup step (4 lines) before final Done message |

---

## Rules

- `shellcheck -S warning bin/acg-down` — zero new warnings
- No other files touched
- The three `rm -f` lines must use the glob patterns exactly as shown — no quoting the globs
- `rm -f` (not `rm -rf`) — these are files, not directories

---

## Definition of Done

- [ ] `bin/acg-down` contains the three `rm -f` lines in the exact location specified
- [ ] `shellcheck -S warning bin/acg-down` passes with zero new warnings
- [ ] Committed and pushed to `k3d-manager-v1.4.10`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-down): clean up stale argocd sockets and k3d tmp files on teardown
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-down`
- Do NOT use `rm -rf` — these are files only
- Do NOT quote the glob patterns (e.g. `rm -f "/tmp/argocd-*.sock"` would not expand)
- Do NOT commit to `main` — work on `k3d-manager-v1.4.10`
