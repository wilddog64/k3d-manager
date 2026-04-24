# Bug: GCP Provisioning Fails with Error 1 due to Bash Arithmetic Pitfall

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `scripts/lib/providers/k3s-gcp.sh`

---

## Summary

GCP cluster provisioning fails immediately after the "Waiting for node to be Ready..." message with `make: *** [up] Error 1`. This is caused by a Bash arithmetic evaluation returning a non-zero exit code, which triggers `set -e`.

---

## Reproduction Steps

1. Run `CLUSTER_PROVIDER=k3s-gcp make up`.
2. Observe the logs until the GCP instance is created and the kubeconfig is merged.
3. Observe the immediate exit with `Error 1` when entering the "Wait for Node" loop.

---

## Root Cause

The script `scripts/lib/providers/k3s-gcp.sh` contains two loops using the following pattern:

```bash
local attempts=0
until ...; do
  (( attempts++ ))
  ...
done
```

In Bash, `(( variable++ ))` evaluates to the *previous* value of the variable. When `attempts` is `0`, the expression evaluates to `0`. Bash treats a result of `0` in an arithmetic expression as a **failure** (exit code 1).

Because `bin/acg-up` sources the provider and runs with `set -e`, the shell terminates the script the moment it hits `(( 0 ))`.

---

## Proposed Fix

Replace the post-increment `(( attempts++ ))` with a pre-increment or an explicit assignment that ensures a non-zero exit status, or append `|| true`:

```bash
# Option 1 (Recommended)
(( ++attempts ))

# Option 2
(( attempts += 1 ))

# Option 3
(( attempts++ )) || true
```

---

## Impact

Critical. Completely blocks GCP provisioning on all platforms where `set -e` is active.

---

## Fix

Two hunks — both in `scripts/lib/providers/k3s-gcp.sh`. No other files.

### Hunk 1 — `_gcp_wait_for_ssh` (line 109)

**Old:**
```bash
    (( attempts++ ))
    if (( attempts >= 24 )); then
```

**New:**
```bash
    (( ++attempts ))
    if (( attempts >= 24 )); then
```

### Hunk 2 — node Ready loop (line 211)

**Old:**
```bash
    (( attempts++ ))
    if (( attempts >= 60 )); then
```

**New:**
```bash
    (( ++attempts ))
    if (( attempts >= 60 )); then
```

---

## Before You Start

1. `git pull origin k3d-manager-v1.1.0`
2. Read `scripts/lib/providers/k3s-gcp.sh` lines 103–117 (`_gcp_wait_for_ssh`) and 208–217 (node Ready loop) in full.
3. Read `memory-bank/activeContext.md`.
4. Run `shellcheck -S warning scripts/lib/providers/k3s-gcp.sh` — baseline is zero warnings. Record it.
5. Do NOT touch `(( attempts >= 24 ))` or `(( attempts >= 60 ))` — those are read-only comparisons inside `if`; they are not affected by this bug.

---

## Rules

- `shellcheck -S warning scripts/lib/providers/k3s-gcp.sh` must produce zero new warnings vs baseline.
- Only `scripts/lib/providers/k3s-gcp.sh` may be touched.
- Do NOT add `--no-verify` to any git command.
- Do NOT commit to `main`.
- Do NOT create a PR.

---

## Definition of Done

1. `scripts/lib/providers/k3s-gcp.sh` line 109: `(( attempts++ ))` → `(( ++attempts ))`.
2. `scripts/lib/providers/k3s-gcp.sh` line 211: `(( attempts++ ))` → `(( ++attempts ))`.
3. `shellcheck -S warning scripts/lib/providers/k3s-gcp.sh` — zero warnings.
4. Committed on `k3d-manager-v1.1.0` with message:
   ```
   fix(k3s-gcp): use pre-increment to avoid set -e exit on zero in wait loops
   ```
5. Branch pushed to `origin/k3d-manager-v1.1.0` before reporting done.
6. `memory-bank/activeContext.md`: update "GCP Provisioning Error 1" from OPEN → COMPLETE with real commit SHA.
7. `memory-bank/progress.md`: update "GCP Provisioning Error 1" from OPEN → COMPLETE with real commit SHA.
8. Report back: commit SHA + paste the memory-bank lines you updated.

---

## What NOT To Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside `scripts/lib/providers/k3s-gcp.sh`.
- Do NOT commit to `main`.
- Do NOT touch `(( attempts >= 24 ))` or `(( attempts >= 60 ))` — only the two `(( attempts++ ))` lines change.
- Do NOT use `(( attempts++ )) || true` — use `(( ++attempts ))` (pre-increment always evaluates to the new value, which is ≥ 1).
