# Bugfix: v1.16.0 — AMBIENT_CNI_* vars missing from argocd/vars.sh, bootstrap skips istio-ambient

**Branch:** `k3d-manager-v1.16.0`
**Files:** `scripts/etc/argocd/vars.sh`

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — the Hostinger ambient
  section records the change that introduced this regression.
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `scripts/etc/argocd/vars.sh` — the whole file, especially the `AMBIENT_ISTIO_VERSION` block at
    the end (lines 70–73) and its comment, which states the exact rule this spec enforces.
  - `scripts/plugins/argocd.sh` — the `_argocd_deploy_applicationsets` function, specifically the
    auto-derived variable list and the unset-variable refusal gate (currently ~lines 1206–1220).
  - `docs/bugs/2026-07-21-istio-ambient-cni-dirs-not-substrate-aware.md` — the spec whose fix
    (`9c0e336a`) introduced this regression. That fix is correct; do NOT revert it.
- Implement exactly what is written — no interpretation, no scope expansion.

---

## Problem

Commit `9c0e336a` parameterized the istio-cni host paths in
`scripts/etc/argocd/applicationsets/istio-ambient.yaml`:

```yaml
              cni:
                cniConfDir: ${AMBIENT_CNI_CONF_DIR}
                cniBinDir: ${AMBIENT_CNI_BIN_DIR}
```

and defaulted both vars in `scripts/plugins/istio_ambient.sh`. That is correct for
`deploy_istio_ambient`, which loads the plugin.

It is **not** correct for `deploy_argocd_bootstrap`. `_argocd_deploy_applicationsets` in
`scripts/plugins/argocd.sh` scans each ApplicationSet file for `${VAR}` placeholders, builds the
`envsubst` allowlist from what it finds, and **refuses to apply the file** if any of those
variables is unset in the environment:

```bash
      local _vars _v _name _unset=""
      _vars="$(grep -oh '\${[A-Za-z_][A-Za-z0-9_]*}' "$file" 2>/dev/null \
         | tr -d '${}' | sort -u | sed 's/^/$/' | tr '\n' ' ')"
      for _v in ${_vars}; do
         _name="${_v#\$}"
         [[ -z "${!_name:-}" ]] && _unset="${_unset} ${_name}"
      done
      if [[ -n "${_unset}" ]]; then
         _err "[argocd] Refusing to apply ${filename}: unset variable(s):${_unset}"
         continue
      fi
```

This path does **not** source or load `scripts/plugins/istio_ambient.sh`, so the two new vars are
unset. The result:

```
[argocd] Refusing to apply istio-ambient.yaml: unset variable(s): AMBIENT_CNI_CONF_DIR AMBIENT_CNI_BIN_DIR
```

The loop `continue`s and the function still `return 0`s, so **bootstrap reports success while
silently dropping the ambient ApplicationSet**. There is no non-zero exit and no summary line that
names the skipped file — only the one `_err` line, in the middle of a long bootstrap log.

**Root cause:** `AMBIENT_CNI_CONF_DIR` and `AMBIENT_CNI_BIN_DIR` were defaulted only in the plugin.
`scripts/etc/argocd/vars.sh` already documents this exact trap for the sibling variable — lines
70–72, verbatim:

```
# Istio ambient mesh chart version (consumed by istio-ambient.yaml ApplicationSet).
# Must be defaulted here, not only in istio_ambient.sh — the ArgoCD bootstrap path
# applies that ApplicationSet without loading the istio_ambient plugin.
```

`AMBIENT_ISTIO_VERSION` obeys that rule. The two new vars do not.

---

## Reproduction

Static — no cluster required. From the repo root, in a clean shell:

```bash
env -u AMBIENT_CNI_CONF_DIR -u AMBIENT_CNI_BIN_DIR bash -c '
  source scripts/etc/argocd/vars.sh
  export APP_CLUSTER_NAME="${APP_CLUSTER_NAME:-ubuntu-k3s}"
  for v in $(grep -oh "\${[A-Za-z_][A-Za-z0-9_]*}" \
      scripts/etc/argocd/applicationsets/istio-ambient.yaml | tr -d "\${}" | sort -u); do
    [[ -z "${!v:-}" ]] && echo "UNSET: $v"
  done'
```

> The `export APP_CLUSTER_NAME` line is **required** and is not part of the bug.
> `_argocd_deploy_applicationsets` sets `APP_CLUSTER_NAME` itself at runtime, before the loop that
> applies the files, so it is never unset on the real path. Without that line the check reports a
> false `UNSET: APP_CLUSTER_NAME`. Do NOT "fix" `APP_CLUSTER_NAME` in `vars.sh` — it is derived
> from the active provider context at runtime and must stay that way.

Actual (before the fix):

```
UNSET: AMBIENT_CNI_BIN_DIR
UNSET: AMBIENT_CNI_CONF_DIR
```

Expected (after the fix): no output.

Judge this gate by its **stdout only**, not its exit code — the loop's last `[[ -z ... ]]` test
leaves a non-zero status even when nothing was printed.

---

## Fix

### Change 1 — `scripts/etc/argocd/vars.sh`: default and export the two CNI dir vars

Append to the end of the file, immediately after the existing `AMBIENT_ISTIO_VERSION` line.

**Exact old block (lines 70–73, currently the end of the file):**

```bash
# Istio ambient mesh chart version (consumed by istio-ambient.yaml ApplicationSet).
# Must be defaulted here, not only in istio_ambient.sh — the ArgoCD bootstrap path
# applies that ApplicationSet without loading the istio_ambient plugin.
export AMBIENT_ISTIO_VERSION="${AMBIENT_ISTIO_VERSION:-1.24.2}"
```

**Exact new block:**

```bash
# Istio ambient mesh chart version (consumed by istio-ambient.yaml ApplicationSet).
# Must be defaulted here, not only in istio_ambient.sh — the ArgoCD bootstrap path
# applies that ApplicationSet without loading the istio_ambient plugin.
export AMBIENT_ISTIO_VERSION="${AMBIENT_ISTIO_VERSION:-1.24.2}"

# istio-cni host paths, same rule as above — the bootstrap path derives its envsubst
# allowlist from the ApplicationSet file and refuses to apply it if either is unset.
# Defaults are the Cilium paths; bare k3s flannel needs the /var/lib/rancher pair.
export AMBIENT_CNI_CONF_DIR="${AMBIENT_CNI_CONF_DIR:-/etc/cni/net.d}"
export AMBIENT_CNI_BIN_DIR="${AMBIENT_CNI_BIN_DIR:-/opt/cni/bin}"
```

> The defaults must be **byte-identical** to the ones in `scripts/plugins/istio_ambient.sh`
> (`/etc/cni/net.d` and `/opt/cni/bin`). The two files must not disagree.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/argocd/vars.sh` | default + export `AMBIENT_CNI_CONF_DIR` and `AMBIENT_CNI_BIN_DIR` |

---

## Rules

- `shellcheck -S warning scripts/etc/argocd/vars.sh` — zero new warnings.
- `bash -n scripts/etc/argocd/vars.sh` — must parse.
- **Refusal-gate check** — the Reproduction command above must print **nothing** after the fix.
  Paste the command and its (empty) output in your report.
- **Defaults agree across both files** — verify and paste:
  ```bash
  grep -n 'AMBIENT_CNI_CONF_DIR\|AMBIENT_CNI_BIN_DIR' \
    scripts/etc/argocd/vars.sh scripts/plugins/istio_ambient.sh
  ```
  The default values in `vars.sh` and `istio_ambient.sh` must be the same two strings.
- **Override still works** — an env override must win over the vars.sh default. Verify and paste:
  ```bash
  AMBIENT_CNI_CONF_DIR=/var/lib/rancher/k3s/agent/etc/cni/net.d \
    bash -c 'source scripts/etc/argocd/vars.sh; echo "$AMBIENT_CNI_CONF_DIR"'
  ```
  → must print `/var/lib/rancher/k3s/agent/etc/cni/net.d`, not the Cilium default.
- Do NOT run `deploy_argocd_bootstrap`, `deploy_istio_ambient`, or any `kubectl` against a live
  cluster. Codex has no live-cluster verification role here; static gates only. Claude runs the
  live check (below).

---

## Definition of Done

- [ ] `vars.sh` defaults and exports both vars, with the Cilium values.
- [ ] Defaults match `scripts/plugins/istio_ambient.sh` exactly (checked per Rules).
- [ ] Env override beats the default (checked per Rules).
- [ ] Refusal-gate reproduction command prints nothing.
- [ ] `shellcheck -S warning` clean; `bash -n` clean.
- [ ] No other file modified — `git show <sha> --stat` shows exactly one file.
- [ ] Committed and pushed to `k3d-manager-v1.16.0`; push verified with
      `git log origin/k3d-manager-v1.16.0 --oneline -1` (paste the output).
- [ ] memory-bank updated with commit SHA and task status — as a **separate commit**, never
      bundled with `vars.sh`.

**Commit message (exact):**
```
fix(argocd): default ambient CNI dir vars in argocd/vars.sh for the bootstrap path
```

### Live re-verify — Claude runs this after the push (NOT Codex)

Run `deploy_argocd_bootstrap` and confirm the log no longer contains
`Refusing to apply istio-ambient.yaml`, and that the applied ApplicationSet on the hub renders
concrete paths rather than literal `${AMBIENT_CNI_CONF_DIR}` placeholders.

---

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify any file other than `scripts/etc/argocd/vars.sh`.
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`.
- Do NOT revert `9c0e336a` or remove the `${AMBIENT_CNI_*}` placeholders from
  `scripts/etc/argocd/applicationsets/istio-ambient.yaml` — parameterizing them is the intended
  design; this spec only supplies the missing defaults.
- Do NOT edit `_argocd_deploy_applicationsets` in `scripts/plugins/argocd.sh`. Its allowlist is
  auto-derived from the file, so there is no list to extend, and its unset-variable refusal gate is
  a deliberate safety feature — it is what caught this. Leave it alone.
- Do NOT touch `scripts/lib/providers/k3s-oci.sh`. Its one-variable `envsubst '$ARGOCD_NAMESPACE'`
  allowlist leaks `${APP_CLUSTER_NAME}` and `${AMBIENT_ISTIO_VERSION}` literally and was already
  broken before `9c0e336a`. That is a separate pre-existing bug with its own spec — fixing it here
  would be scope creep.
- Do NOT remove or reword the existing `AMBIENT_ISTIO_VERSION` comment block — the new comment goes
  after it, not in place of it.
