# app-cve-scan git-persist clones into a non-empty dir → clone always fails

**Filed:** 2026-08-25 (Claude, live-verified on hub `k3d-k3d-cluster`)
**File:** `scripts/etc/argocd/platform-ops/app-cve-scan.sh` — `_git_persist_promotion()` (lines ~313-364)
**Severity:** medium — every CVE promotion is **live-patch-only**; the fixed image pin is
never written back to git, so ArgoCD reverts it on the next sync from the source branch.

## Observed

After unblocking the `app-cve-scan` CronJob (the missing `platform-ops-app-rebuild` secret —
see `docs/issues/2026-08-24-cve-remediation-panels-empty.md`), a manual run promoted two
services and logged:

```
PROMOTION shopping-cart-payment: persisted to git k3d-manager-v1.27.0@
  GITWRITE shopping-cart-payment: clone of wilddog64/k3d-manager@k3d-manager-v1.27.0 failed
PROMOTION shopping-cart-product-catalog: persisted to git k3d-manager-v1.27.0@
  GITWRITE shopping-cart-product-catalog: clone of wilddog64/k3d-manager@k3d-manager-v1.27.0 failed
```

## Ruled out (verified, not assumed)

- **Token invalid** — NO. `platform-ops-git-writer/git-token` (`gho_…`, scope `repo`) reads
  `repos/wilddog64/k3d-manager` (200) and branch `k3d-manager-v1.27.0` (200); identity `wilddog64`.
- **Egress netpol** — NO. `kubectl -n platform-ops get netpol` → none.
- **Missing git / CA in the scan image** — NO. `aquasec/trivy:0.63.0` ships `git 2.47.2`
  and `/etc/ssl/certs/ca-certificates.crt` (verified with a throwaway pod).

## Root cause

`_git_persist_promotion()` writes its GIT_ASKPASS helper **into the same directory it then
asks `git clone` to populate**:

```sh
_p_work="$(mktemp -d)"                 # empty dir
_p_askpass="${_p_work}/git-askpass"    # helper written INTO _p_work
cat > "${_p_askpass}" <<'ASKPASS' ...  # _p_work now contains a file
git clone --depth 1 --branch "${_p_branch}" \
    "https://github.com/${MANAGER_REPO}.git" "${_p_work}"   # dest is non-empty → fatal
```

`git clone <url> <dir>` refuses when `<dir>` exists and is not empty
(`fatal: destination path '…' already exists and is not an empty directory`). Because the
askpass file lives in `_p_work`, the clone fails **every time, independent of credentials** —
git-persist has never succeeded.

## Fix (proposed — not yet applied)

Put the askpass helper **outside** the clone destination. Minimal patch: give the clone its
own subdir, keep the helper in the parent.

```sh
_p_work="$(mktemp -d)"
_p_askpass="${_p_work}/git-askpass"        # stays in parent
_p_repo="${_p_work}/repo"                  # clone target — separate, empty
...
git clone --depth 1 --branch "${_p_branch}" \
    "https://github.com/${MANAGER_REPO}.git" "${_p_repo}"
# then operate on ${_p_repo}/${_p_kfile}, commit + push from ${_p_repo}
```

Update the three later references (`${_p_work}/${_p_kfile}`, `git -C "${_p_work}"`,
kustomization path) to `${_p_repo}`. Keep `rm -rf "${_p_work}"` (removes both).

## Verification after fix

Trigger a manual run (`kubectl -n platform-ops create job cve-manual-<ts> --from=cronjob/app-cve-scan`),
confirm the log shows `GITWRITE <svc>: committed <name>@<digest> to <branch> (<sha>)` and that
`services/<svc>/kustomization.yaml` on the branch gains the pinned digest.
