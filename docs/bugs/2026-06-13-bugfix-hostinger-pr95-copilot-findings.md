# Bugfix: v1.7.0 — Hostinger provider PR #95 Copilot findings

**Branch:** `k3d-manager-v1.7.0`
**Files:** `scripts/lib/providers/k3s-hostinger.sh`, `.github/copilot-instructions.md`

---

## Problem

Copilot review on PR #95 flagged four issues in the new `k3s-hostinger` provider:

1. **Masked kubeconfig-merge failures** — `_hostinger_merge_kubeconfig` ends with `_info`, so it
   always returns 0. A failed `cp`, `kubectl config view --flatten`, or `mv` is silently ignored
   and the caller proceeds as if the merge succeeded.
2. **Masked SSH failure on teardown** — in `destroy_cluster`, the uninstall SSH command is OR'd into
   an `_info` log with `2>/dev/null`, so any SSH failure (network down, auth failure) is reported as
   "k3s-uninstall.sh not present — skipping" rather than surfaced as an error.
3. **Provider list drift** — `.github/copilot-instructions.md:16` lists every provider except
   `k3s-hostinger`, making the instructions internally inconsistent.
4. **Misleading error text** — `_hostinger_require_host` tells the user to
   `export HOSTINGER_HOST=<vps-ip>`, but the provider accepts (and defaults to) a hostname.

**Root cause:** best-effort helper paths return success unconditionally; the doc/list and error
string were not updated when the hostname default landed.

---

## Reproduction

```bash
# 1: corrupt the source kubeconfig path, run deploy — merge "succeeds" with no error
# 2: power off the VPS, run destroy_cluster --confirm — prints "not present" instead of SSH error
# 3: grep k3s-hostinger .github/copilot-instructions.md  -> not in provider list
# 4: unset HOSTINGER_HOST; run any hostinger op -> error says <vps-ip> for a hostname field
```

---

## Fix

### Change 1 — `scripts/lib/providers/k3s-hostinger.sh`: fail loudly on merge errors

**Exact old block (lines 88–93):**

```bash
  cp "${_HOSTINGER_KUBECONFIG}" "${tmp_kube}"
  chmod 600 "${tmp_kube}"
  KUBECONFIG="${tmp_kube}:${HOME}/.kube/config" kubectl config view --flatten > "${tmp_merged}"
  mv "${tmp_merged}" "${HOME}/.kube/config"
  chmod 600 "${HOME}/.kube/config"
  rm -f "${tmp_kube}"
```

**Exact new block:**

```bash
  cp "${_HOSTINGER_KUBECONFIG}" "${tmp_kube}" || return 1
  chmod 600 "${tmp_kube}"
  if ! KUBECONFIG="${tmp_kube}:${HOME}/.kube/config" kubectl config view --flatten > "${tmp_merged}"; then
    rm -f "${tmp_kube}" "${tmp_merged}"
    return 1
  fi
  mv "${tmp_merged}" "${HOME}/.kube/config" || { rm -f "${tmp_kube}" "${tmp_merged}"; return 1; }
  chmod 600 "${HOME}/.kube/config"
  rm -f "${tmp_kube}"
```

### Change 2 — `scripts/lib/providers/k3s-hostinger.sh`: distinguish SSH failure from missing uninstall script

**Exact old block (lines 241–243):**

```bash
  _info "[k3s-hostinger] Uninstalling k3s on ${ssh_user}@${host}..."
  _run_command -- ssh -i "${ssh_key}" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "${ssh_user}@${host}" 'sudo /usr/local/bin/k3s-uninstall.sh' 2>/dev/null || \
    _info "[k3s-hostinger] k3s-uninstall.sh not present — skipping"
```

**Exact new block:**

```bash
  _info "[k3s-hostinger] Uninstalling k3s on ${ssh_user}@${host}..."
  local _uninstall_rc=0
  _run_command -- ssh -i "${ssh_key}" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "${ssh_user}@${host}" 'sudo sh -c "test -x /usr/local/bin/k3s-uninstall.sh && /usr/local/bin/k3s-uninstall.sh"' || _uninstall_rc=$?
  if [[ "${_uninstall_rc}" -eq 255 ]]; then
    printf 'ERROR: %s\n' "[k3s-hostinger] SSH to ${ssh_user}@${host} failed — cannot uninstall k3s" >&2
    return 1
  elif [[ "${_uninstall_rc}" -ne 0 ]]; then
    _info "[k3s-hostinger] k3s-uninstall.sh not present or returned ${_uninstall_rc} — skipping"
  fi
```

> Keep the `_run_command -- ssh ... 'sudo ...'` call on a **single physical line** beginning with
> `_run_command` (the `|| _uninstall_rc=$?` stays on that same line) so the `_agent_audit` bare-sudo
> guard passes. `ssh` returns `255` on connection failure; the remote `sh -c` returns non-zero only
> when the uninstall script is absent or itself fails.

### Change 3 — `scripts/lib/providers/k3s-hostinger.sh`: correct the host error text

**Exact old block (line 20):**

```bash
    printf 'ERROR: %s\n' "[k3s-hostinger] HOSTINGER_HOST is not set — export HOSTINGER_HOST=<vps-ip>" >&2
```

**Exact new block:**

```bash
    printf 'ERROR: %s\n' "[k3s-hostinger] HOSTINGER_HOST is not set — export HOSTINGER_HOST=<vps-host-or-ip>" >&2
```

### Change 4 — `.github/copilot-instructions.md`: add `k3s-hostinger` to the provider list

**Exact old block (line 16, the provider-name list only):**

```
- **Cluster providers**: `scripts/lib/providers/` — `k3d`, `orbstack`, `k3s-aws`, `k3s-oci`, `k3s-gcp`, `k3s-az`.
```

**Exact new block (replace only the provider-name list portion of line 16; leave the rest of the line unchanged):**

```
- **Cluster providers**: `scripts/lib/providers/` — `k3d`, `orbstack`, `k3s-aws`, `k3s-oci`, `k3s-gcp`, `k3s-az`, `k3s-hostinger`.
```

> NOTE: line 16 continues after the list with `Active provider is recorded to ...`. Do **not** drop
> that trailing sentence — only insert `, \`k3s-hostinger\`` before the period that ends the list.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/providers/k3s-hostinger.sh` | fail-loud kubeconfig merge; SSH-vs-missing-script teardown; host error text |
| `.github/copilot-instructions.md` | add `k3s-hostinger` to provider list |

---

## Rules

- `shellcheck -S warning scripts/lib/providers/k3s-hostinger.sh` — zero new warnings
- `bash -n scripts/lib/providers/k3s-hostinger.sh` — parses clean
- `./scripts/k3d-manager _agent_audit` — passes (the teardown `ssh ... sudo` call stays a single
  physical line beginning with `_run_command`)
- No other files touched (do NOT edit the Makefile, vars.sh, or other providers)

---

## Definition of Done

- [ ] `_hostinger_merge_kubeconfig` returns non-zero when `cp` / `kubectl config view` / `mv` fails
- [ ] `destroy_cluster` returns 1 on SSH failure (rc 255) and only logs "skipping" when the script is absent
- [ ] host error text reads `<vps-host-or-ip>`
- [ ] `.github/copilot-instructions.md` provider list includes `k3s-hostinger` (trailing sentence intact)
- [ ] `shellcheck -S warning`, `bash -n`, `_agent_audit` all clean
- [ ] Committed and pushed to `k3d-manager-v1.7.0`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(k3s-hostinger): surface merge/teardown failures; provider-list + host-text fixes (PR #95)
```

---

## What NOT to Do

- Do NOT create a PR (one is already open — #95)
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the two listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.7.0`
- Do NOT change the `_run_command -- ssh ... 'sudo ...'` line into a multi-line form (breaks the audit guard)
