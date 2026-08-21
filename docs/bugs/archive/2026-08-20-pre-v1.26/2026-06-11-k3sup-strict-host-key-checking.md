# Bug: k3sup install/join prompt for unknown host key — breaks chatops automation

**Date:** 2026-06-11
**Branch:** k3d-manager-v1.6.5
**File:** `scripts/plugins/shopping_cart.sh`

---

## Symptom

`make up` (ACG/AWS path) blocks on:

```
The authenticity of host '54.190.152.93 (54.190.152.93)' can't be established.
ED25519 key fingerprint is SHA256:...
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

ACG EC2 instances are ephemeral — a new IP and host key on every sandbox. The prompt requires
manual input and cannot be bypassed in unattended / chatops execution.

---

## Root Cause

`k3sup install` and `k3sup join` in `_k3sup_join_agent()` and `deploy_app_cluster()` do not
pass `--ssh-option "StrictHostKeyChecking=no"`. The follow-up `ssh` call at the post-install
step also lacks `-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null`.

Every other provider (GCP, OCI, Azure) already sets `StrictHostKeyChecking=no` — shopping_cart.sh
was the only one missing it.

---

## Fix

### Change 1 — `scripts/plugins/shopping_cart.sh`: add `--ssh-option` to `k3sup join`

**Exact old block (lines 765–769):**

```bash
  _run_command -- k3sup join \
    --ip "${agent_ip}" \
    --server-ip "${server_ip}" \
    --user "${ssh_user}" \
    --ssh-key "${ssh_key}"
```

**Exact new block:**

```bash
  _run_command -- k3sup join \
    --ip "${agent_ip}" \
    --server-ip "${server_ip}" \
    --user "${ssh_user}" \
    --ssh-key "${ssh_key}" \
    --ssh-option "StrictHostKeyChecking=no" \
    --ssh-option "UserKnownHostsFile=/dev/null"
```

---

### Change 2 — `scripts/plugins/shopping_cart.sh`: add `--ssh-option` to `k3sup install`

**Exact old block (lines 865–871):**

```bash
  _run_command -- k3sup install \
    --ip "${external_ip}" \
    --user "${ssh_user}" \
    --ssh-key "${ssh_key}" \
    --local-path "${local_kubeconfig}" \
    --context "${kube_context}" \
    --k3s-extra-args '--disable traefik --disable servicelb'
```

**Exact new block:**

```bash
  _run_command -- k3sup install \
    --ip "${external_ip}" \
    --user "${ssh_user}" \
    --ssh-key "${ssh_key}" \
    --local-path "${local_kubeconfig}" \
    --context "${kube_context}" \
    --k3s-extra-args '--disable traefik --disable servicelb' \
    --ssh-option "StrictHostKeyChecking=no" \
    --ssh-option "UserKnownHostsFile=/dev/null"
```

---

### Change 3 — `scripts/plugins/shopping_cart.sh`: add SSH options to post-install `ssh` call

**Exact old block (line 876):**

```bash
  _run_command -- ssh -i "${ssh_key}" "${ssh_user}@${external_ip}" bash <<'REMOTE'
```

**Exact new block:**

```bash
  _run_command -- ssh -i "${ssh_key}" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "${ssh_user}@${external_ip}" bash <<'REMOTE'
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/plugins/shopping_cart.sh` | Add `--ssh-option StrictHostKeyChecking=no` + `UserKnownHostsFile=/dev/null` to `k3sup join`, `k3sup install`, and post-install `ssh` call |

---

## Rules

- `shellcheck -S warning scripts/plugins/shopping_cart.sh` — zero new warnings
- No other files touched

---

## Definition of Done

- [ ] `k3sup join` has both `--ssh-option` flags
- [ ] `k3sup install` has both `--ssh-option` flags
- [ ] Post-install `ssh` call has `-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null`
- [ ] `shellcheck -S warning scripts/plugins/shopping_cart.sh` passes
- [ ] Committed and pushed to `k3d-manager-v1.6.5`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(shopping_cart): add StrictHostKeyChecking=no to k3sup install/join and post-install ssh — blocks chatops on new ACG EC2 instances
```

---

## What NOT to Do

- Do NOT create a PR yourself — Claude handles PR creation after verifying the commit
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/plugins/shopping_cart.sh`
- Do NOT commit to `main` — work on `k3d-manager-v1.6.5`
