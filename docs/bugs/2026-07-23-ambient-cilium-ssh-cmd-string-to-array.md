# Bugfix: v1.17.0 — `_ambient_install_cilium` SSH command string → array

**Branch:** `k3d-manager-v1.17.0`
**Files:** `scripts/plugins/shopping_cart.sh`

---

## Problem

`_ambient_install_cilium` builds its SSH invocation as a single string
(`ssh_cmd="ssh -o … -i ${ssh_key} ${ssh_user}@${external_ip}"`) and then calls it
unquoted (`${ssh_cmd} "…"`) at three sites. This relies on word-splitting to
re-tokenize the command, so any path or user containing a space or shell
metacharacter (e.g. an SSH key under `~/Library/Application Support/…`) would break
argument boundaries, and shellcheck flags the unquoted expansions (SC2086).

**Root cause:** the SSH command is stored as a word-split-dependent string instead of
an array. Deferred Copilot finding from PR #106.

---

## Reproduction

Static — no cluster needed:

```bash
shellcheck -S warning scripts/plugins/shopping_cart.sh
```

The three unquoted `${ssh_cmd}` invocations (idempotency probe, install heredoc, rollout
wait) are the word-splitting hazard. An array form removes the hazard and the SC2086 risk.

---

## Fix

### Change 1 — `scripts/plugins/shopping_cart.sh`: declare `ssh_cmd` as an array

**Exact old block (lines 1069–1071):**

```bash
  local ssh_cmd
  local remote_kubeconfig="/home/${ssh_user}/.kube/k3s.yaml"
  ssh_cmd="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${ssh_key} ${ssh_user}@${external_ip}"
```

**Exact new block:**

```bash
  local -a ssh_cmd
  local remote_kubeconfig="/home/${ssh_user}/.kube/k3s.yaml"
  ssh_cmd=(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${ssh_key}" "${ssh_user}@${external_ip}")
```

### Change 2 — idempotency probe invocation

**Exact old block (line 1074):**

```bash
  if ${ssh_cmd} "KUBECONFIG=${remote_kubeconfig} helm status cilium -n kube-system >/dev/null 2>&1" 2>/dev/null; then
```

**Exact new block:**

```bash
  if "${ssh_cmd[@]}" "KUBECONFIG=${remote_kubeconfig} helm status cilium -n kube-system >/dev/null 2>&1" 2>/dev/null; then
```

### Change 3 — install heredoc invocation

**Exact old block (lines 1080–1081):**

```bash
  # shellcheck disable=SC2029
  ${ssh_cmd} "
```

**Exact new block:**

```bash
  # shellcheck disable=SC2029
  "${ssh_cmd[@]}" "
```

### Change 4 — rollout-wait invocation

**Exact old block (line 1098):**

```bash
  until ${ssh_cmd} "KUBECONFIG=${remote_kubeconfig} kubectl -n kube-system rollout status daemonset/cilium --timeout=10s >/dev/null 2>&1" 2>/dev/null; do
```

**Exact new block:**

```bash
  until "${ssh_cmd[@]}" "KUBECONFIG=${remote_kubeconfig} kubectl -n kube-system rollout status daemonset/cilium --timeout=10s >/dev/null 2>&1" 2>/dev/null; do
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/plugins/shopping_cart.sh` | `ssh_cmd` string → array (1 declaration) + three invocation sites updated to `"${ssh_cmd[@]}"` |

---

## Rules

- `shellcheck -S warning scripts/plugins/shopping_cart.sh` — zero new warnings (the array form should
  drop any SC2086 on these lines; keep the existing `SC2029` disable at the install heredoc).
- Do NOT change any flags, hostnames, helm `--set` values, or retry logic — only the
  string→array conversion and the four invocation sites.
- No other function or file touched.
- Run `_agent_audit` before reporting done.

---

## Definition of Done

- [ ] `ssh_cmd` declared `local -a` and assigned as an array literal
- [ ] All four invocation sites use `"${ssh_cmd[@]}"` (grep `'${ssh_cmd}'` → 0 unquoted uses)
- [ ] `shellcheck -S warning scripts/plugins/shopping_cart.sh` passes with no new warnings
- [ ] Committed and pushed to `k3d-manager-v1.17.0`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(shopping_cart): ssh_cmd string -> array in _ambient_install_cilium
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/plugins/shopping_cart.sh`
- Do NOT commit to `main` — work on `k3d-manager-v1.17.0`
- Do NOT refactor `deploy_app_cluster` or any surrounding function
