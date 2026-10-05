# Bug: `cluster-up`'s data-layer wait fails without saying why, and the reconnect timeout logs "connected"

**Status:** FIXED
**Filed:** 2026-10-05
**Branch:** `k3d-manager-v1.41.0`
**Severity:** Medium. Nothing breaks, but the operator watched 8 minutes of identical lines and
then got an error naming no cause.
**Files:** `bin/cluster-up`, `scripts/tests/bin/cluster_up.bats`

Related: `docs/bugs/2026-10-05-sandbox-node-notready-trivy-cilium-scan-starves-kubelet.md` (the
failure this wait hid). The wait loops themselves came from
`v1.6.3-bugfix-data-layer-argocd-controller-reconnect-race.md` and
`v1.6.3-bugfix-data-layer-sync-timeout-retry.md`; neither covered diagnostics.

## Symptom

`make up` 2026-10-05 (abridged):

```
INFO: [acg-up] ArgoCD controller not yet connected to ubuntu-k3s — waiting...   (x24)
WARN: [acg-up] ArgoCD controller did not reconnect to ubuntu-k3s within 120s — proceeding anyway
INFO: [acg-up] ArgoCD controller connected to ubuntu-k3s — proceeding
...
INFO: [acg-up] data-layer not yet Synced — waiting...                           (x48)
WARN: [acg-up] data-layer did not reach Synced within 300s — force-syncing and retrying (one attempt)...
ERROR: [acg-up] data-layer ArgoCD Application did not reach Synced after force-sync + 180s retry — check: kubectl get application ...
```

The real cause was in two places the script already reads from:

- `.status.operationState.message` on the Application:
  `failed calling webhook "validate.externalsecret.external-secrets.io" ... no endpoints available`
- a NotReady node on `ubuntu-k3s`

Neither was printed. The operator saw "no output" and had to ask.

## Root cause

1. **The reconnect loop (`bin/cluster-up` about line 917):** when the deadline is hit, the loop
   `break`s, and then the unconditional `_info "... connected to ubuntu-k3s — proceeding"` runs
   anyway. The log says "did not reconnect" and "connected" back to back.
2. **The data-layer loop (about line 960):** on both the 300s warning and the final error, it
   reports only *that* the sync is not done, never *why*. The image-pull case already has a
   dedicated explainer (`_acg_data_layer_abort_on_image_pull`). Everything else gets nothing.

## Fix spec

### File 1 — `bin/cluster-up`

**1a — add a helper.** Insert it directly after the closing `}` of
`function _acg_data_layer_abort_on_image_pull()`, followed by one blank line:

```bash

# Explain why the data-layer Application is not Synced: ArgoCD's last sync
# operation message and any app-cluster node that is not Ready.
function _acg_data_layer_explain() {
  local _app="$1" _msg _nodes _line
  _msg=$(kubectl get application "${_app}" -n cicd --context k3d-k3d-cluster --request-timeout=15s \
    -o jsonpath='{.status.operationState.message}' 2>/dev/null || true)
  if [[ -n "${_msg}" ]]; then
    _warn "[acg-up] data-layer last sync operation: ${_msg:0:400}"
  fi
  _nodes=$(kubectl get nodes --context ubuntu-k3s --request-timeout=15s --no-headers 2>/dev/null \
    | awk '$2 != "Ready" {print $1 " " $2}' || true)
  while IFS= read -r _line; do
    [[ -n "${_line}" ]] && _warn "[acg-up] app-cluster node not Ready: ${_line}"
  done <<< "${_nodes}"
  return 0
}
```

**1b — call it at both timeouts.** Directly after the line

```bash
        _warn "[acg-up] data-layer did not reach Synced within 300s — force-syncing and retrying (one attempt)..."
```

insert

```bash
        _acg_data_layer_explain "${_dl_app_name}"
```

and directly before the line

```bash
            _err "[acg-up] data-layer ArgoCD Application did not reach Synced after force-sync + 180s retry — check: kubectl get application ${_dl_app_name} -n cicd --context k3d-k3d-cluster"
```

insert (same indentation as that `_err`)

```bash
            _acg_data_layer_explain "${_dl_app_name}"
```

**1c — the reconnect log.** Replace:

```bash
_argocd_conn_deadline=$(( $(date +%s) + 120 ))
until argocd cluster list -o json \
```

with:

```bash
_argocd_conn_deadline=$(( $(date +%s) + 120 ))
_argocd_connected=1
until argocd cluster list -o json \
```

replace:

```bash
    _warn "[acg-up] ArgoCD controller did not reconnect to ubuntu-k3s within 120s — proceeding anyway"
    break
```

with:

```bash
    _warn "[acg-up] ArgoCD controller did not reconnect to ubuntu-k3s within 120s — proceeding anyway"
    _argocd_connected=0
    break
```

and replace:

```bash
_info "[acg-up] ArgoCD controller connected to ubuntu-k3s — proceeding"
```

with:

```bash
if [[ "${_argocd_connected}" == "1" ]]; then
  _info "[acg-up] ArgoCD controller connected to ubuntu-k3s — proceeding"
fi
```

### File 2 — `scripts/tests/bin/cluster_up.bats`

Use the file's existing extract-and-source pattern (see `_load_image_pull_helpers`):
`sed -n '/^function _acg_data_layer_explain()/,/^}$/p' bin/cluster-up`, then source
`scripts/lib/system.sh` and the extract. Stub `kubectl` by dispatching on its arguments
(`get application` vs `get nodes`).

1. **Explains both causes:** the application stub prints
   `failed calling webhook "validate.externalsecret.external-secrets.io": no endpoints available`;
   the nodes stub prints `ip-a Ready ...` and `ip-b NotReady ...`. Assert that the output contains
   `no endpoints available` and `app-cluster node not Ready: ip-b NotReady`, does **not** contain
   `ip-a`, and that status is 0.
2. **Silent when healthy:** both stubs print nothing / only Ready nodes. Assert status 0 and that
   the output contains neither `last sync operation` nor `not Ready`.
3. **Truncates:** an application message of 1000 `x` characters produces a line with at most
   400 `x`.
4. **Survives kubectl failure:** `kubectl() { return 1; }` gives status 0.
5. **Reconnect log is gated:** extract the block from `_argocd_conn_deadline=` through the
   `ArgoCD controller connected` `fi` with `sed -n`, stub `argocd` to print `[]`, `date` so the
   first call is past the deadline, `sleep` as a no-op, and `python3` to print `Unknown`, then run
   it. Assert that the output contains `did not reconnect` and does **not** contain
   `connected to ubuntu-k3s — proceeding`. If extracting it standalone proves impractical, report
   why rather than falling back to a whole-line source grep.

### File 3 — docs

- `CHANGELOG.md` `[Unreleased]` → `### Fixed`: a prose entry.
- This file: flip **Status** to FIXED.

## Definition of Done

- [ ] Pre-fix proof: tests 1–3 and 5 are RED against `HEAD` (paste output).
- [ ] Mutation: drop the `_acg_data_layer_explain` call before the final `_err`. Show
      `git grep -c '_acg_data_layer_explain "${_dl_app_name}"' bin/cluster-up` going from 2 to 1,
      then restore from a `$TMPDIR` snapshot and prove it with `cmp`. Also mutate the
      `$2 != "Ready"` awk filter to `$2 == "Ready"`, and test 1 goes red; restore and `cmp`.
- [ ] `bats scripts/tests/bin/cluster_up.bats` green; paste the counts.
- [ ] `shellcheck bin/cluster-up` shows no new findings vs `HEAD`.
- [ ] Changes are left **unstaged**. Claude verifies and commits.

## What NOT to do

- Do NOT change any timeout, deadline, retry count or exit code. This is a diagnostics-only fix.
- Do NOT print anything from a Secret, and do not read Secrets.
- Do NOT touch files outside those listed. No commit, push, PR or `--no-verify`.
- Do NOT run `make up` or any `kubectl`/`argocd` against a real cluster.
