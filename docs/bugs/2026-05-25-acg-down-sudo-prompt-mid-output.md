# Bugfix: acg-down — sudo password prompt appears mid-output

**Branch:** `k3d-manager-v1.4.9`
**Files:** `bin/acg-down`

---

## Before You Start

```bash
# Step 1 — get the spec
git -C ~/src/gitrepo/personal/k3d-manager pull origin k3d-manager-v1.4.9

# Step 2 — read this spec in full before touching anything

# Step 3 — read the target file before editing
# bin/acg-down lines 40–110
```

---

## Problem

`make down KEEP_LOCAL=1` shows a `Password:` prompt after several INFO lines have already
scrolled past — specifically after "ArgoCD port-forward launchd agent unloaded". The
`_run_command --interactive-sudo --quiet -- true` pre-warm is at line 106, inside the
`_is_mac` block, which runs too late.

**Root cause:** The pre-warm is placed after the ArgoCD port-forward teardown instead of
at the top of the script. Sudo is only needed for system LaunchDaemon operations
(Keycloak and ArgoCD browser listeners), but the prompt should appear upfront so the
user types the password once before any output begins.

---

## Fix

Move `_run_command --interactive-sudo --quiet -- true` from its current location (line 106,
inside the `_is_mac` block before Keycloak teardown) to immediately after the `--confirm`
gate (after line 41), wrapped in `_is_mac`. Remove the pre-warm from its current position.

**Exact old block (lines 41–43):**

```bash
fi

_info "[acg-down] keep-hub=${_keep_hub} hub-cluster=${_HUB_CLUSTER}"
```

**Exact new block:**

```bash
fi

if _is_mac; then
  _run_command --interactive-sudo --quiet -- true
fi

_info "[acg-down] keep-hub=${_keep_hub} hub-cluster=${_HUB_CLUSTER}"
```

**Exact old block (lines 105–107):**

```bash
if _is_mac; then
  _run_command --interactive-sudo --quiet -- true
  _info "[acg-down] Stopping Keycloak browser HTTP listener launchd daemon..."
```

**Exact new block:**

```bash
if _is_mac; then
  _info "[acg-down] Stopping Keycloak browser HTTP listener launchd daemon..."
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-down` | Move sudo pre-warm to top of script (after `--confirm` gate) |

---

## Rules

- `shellcheck -S warning bin/acg-down` — zero new warnings
- No other files touched

---

## Definition of Done

- [ ] `_run_command --interactive-sudo --quiet -- true` appears immediately after the `--confirm` gate, wrapped in `if _is_mac; then ... fi`
- [ ] The same pre-warm removed from its old location before the Keycloak teardown block
- [ ] `shellcheck -S warning bin/acg-down` passes with zero new warnings
- [ ] Committed and pushed to `k3d-manager-v1.4.9`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-down): move sudo pre-warm to top of script — prompt before any output
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-down`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.9`
- Do NOT remove the pre-warm from the `_is_mac` guard — it must stay mac-only
