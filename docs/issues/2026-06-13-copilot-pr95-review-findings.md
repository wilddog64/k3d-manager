# Copilot PR #95 review findings — k3s-hostinger provider

**PR:** [#95](https://github.com/wilddog64/k3d-manager/pull/95) — `feat: k3s-hostinger cluster provider (v1.7.0)`
**Fix commit:** `cb00eaee`
**Spec:** `docs/bugs/2026-06-13-bugfix-hostinger-pr95-copilot-findings.md`

Copilot raised 4 inline findings. All addressed in `cb00eaee`; all 4 threads resolved.

---

## Finding 1 — `_hostinger_merge_kubeconfig` masks failures (k3s-hostinger.sh:92)

Copilot: the function ends with `_info`, so failures from `cp` / `kubectl config view --flatten` /
`mv` are silently ignored (file is sourced, no `set -e`), leaving `~/.kube/config` partially
updated while `deploy_cluster` proceeds as if the merge succeeded.

**Before:**
```bash
cp "${_HOSTINGER_KUBECONFIG}" "${tmp_kube}"
chmod 600 "${tmp_kube}"
KUBECONFIG="${tmp_kube}:${HOME}/.kube/config" kubectl config view --flatten > "${tmp_merged}"
mv "${tmp_merged}" "${HOME}/.kube/config"
```

**After:**
```bash
cp "${_HOSTINGER_KUBECONFIG}" "${tmp_kube}" || return 1
chmod 600 "${tmp_kube}"
if ! KUBECONFIG="${tmp_kube}:${HOME}/.kube/config" kubectl config view --flatten > "${tmp_merged}"; then
  rm -f "${tmp_kube}" "${tmp_merged}"
  return 1
fi
mv "${tmp_merged}" "${HOME}/.kube/config" || { rm -f "${tmp_kube}" "${tmp_merged}"; return 1; }
```

**Root cause:** best-effort helper returned success unconditionally because its last statement was a log call.

---

## Finding 2 — `destroy_cluster` masks SSH failure (k3s-hostinger.sh:243)

Copilot: the uninstall SSH command discards stderr and is OR'd into an `_info` log, so any SSH
failure (unreachable VPS, auth failure) is reported as "k3s-uninstall.sh not present" — a
successful-looking destroy even when nothing was uninstalled.

**Before:**
```bash
_run_command -- ssh … "${ssh_user}@${host}" 'sudo /usr/local/bin/k3s-uninstall.sh' 2>/dev/null || \
  _info "[k3s-hostinger] k3s-uninstall.sh not present — skipping"
```

**After:**
```bash
local _uninstall_rc=0
_run_command -- ssh … "${ssh_user}@${host}" 'sudo sh -c "test -x /usr/local/bin/k3s-uninstall.sh && /usr/local/bin/k3s-uninstall.sh"' || _uninstall_rc=$?
if [[ "${_uninstall_rc}" -eq 255 ]]; then
  printf 'ERROR: %s\n' "[k3s-hostinger] SSH to ${ssh_user}@${host} failed — cannot uninstall k3s" >&2
  return 1
elif [[ "${_uninstall_rc}" -ne 0 ]]; then
  _info "[k3s-hostinger] k3s-uninstall.sh not present or returned ${_uninstall_rc} — skipping"
fi
```

`ssh` returns `255` on connection failure; the remote `sh -c` returns non-zero only when the
uninstall script is absent or fails. The SSH call stays a single physical line beginning with
`_run_command` so the `_agent_audit` bare-sudo guard still passes.

**Root cause:** `2>/dev/null || _info` collapsed all non-zero exits into one benign branch.

---

## Finding 3 — provider list drift (.github/copilot-instructions.md:16)

Copilot: the cluster-provider list omitted `k3s-hostinger` even though this PR adds it. Added
`k3s-hostinger` to the list (trailing active-provider sentence preserved).

**Root cause:** the doc list was not updated when the provider landed.

---

## Finding 4 — misleading host error text (k3s-hostinger.sh:22)

Copilot: the error said `export HOSTINGER_HOST=<vps-ip>` but the field accepts (and defaults to) a
hostname. Changed to `<vps-host-or-ip>`.

**Root cause:** the error string predated the hostname default.

---

## Process note

Findings 1 and 2 are the recurring "best-effort path returns success unconditionally" pattern —
a log/`_info` as the last statement of a function masks earlier failures. Worth a Copilot review
rule: **a function that performs file or remote mutations must not end on a bare `_info`; the
mutating commands need explicit `|| return 1` (or exit-code capture).**
