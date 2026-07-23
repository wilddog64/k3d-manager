# Bugfix: v1.17.0 — remove dead `_argocd_configure_post_deploy`

**Branch:** `k3d-manager-v1.17.0`
**Files:** `scripts/plugins/argocd.sh`

---

## Problem

`_argocd_configure_post_deploy` (`scripts/plugins/argocd.sh:576-615`) has **zero callers
repo-wide** (`grep -rn '_argocd_configure_post_deploy' scripts/ bin/` returns only the
definition). It has been orphaned since `aef115a0`/`e013d23b`. The live deploy path is
`deploy_argocd → _argocd_helm_deploy_release → … → deploy_argocd_bootstrap`, and after the
Round 2 fix (`9ec7469b`) `deploy_argocd_bootstrap` already deploys image-updater + AppProject +
ApplicationSets. Nothing inside the dead function runs.

**Root cause:** dead code left behind after the deploy flow was refactored. Owner decision
(2026-07-23): **delete outright.** A live-hub check confirmed the two capabilities that live only
inside this function are unused on the running hub — no argocd Istio VirtualService in `cicd`
(the UI is reached by port-forward on `localhost:8080`) and no ESO/Vault-backed argocd admin
(admin auth is `argocd-initial-admin-secret`).

---

## Reproduction

```bash
grep -rn '_argocd_configure_post_deploy' scripts/ bin/    # only the definition line — no callers
```

---

## Fix

### Change 1 — `scripts/plugins/argocd.sh`: delete the function (and its single leading blank line)

Delete lines **575–615**: the blank line at 575 plus the entire `_argocd_configure_post_deploy`
function (576–615). Result: `_argocd_configure_vault_eso`'s closing `}` (line 574) is followed by
exactly one blank line, then `function _argocd_seed_vault_admin_secret() {`.

**Exact old block (lines 575–616 — leading blank, full function, trailing blank):**

```bash

function _argocd_configure_post_deploy() {
   local enable_vault="$1"
   local enable_ldap="$2"
   local skip_istio="$3"
   local enable_bootstrap="$4"
   local skip_appproject="$5"
   local skip_applicationsets="$6"

   if (( enable_vault )); then
      _argocd_configure_vault_eso "$enable_ldap"
   fi

   if (( ! skip_istio )); then
      _info "[argocd] Creating Istio VirtualService"
      envsubst < "$ARGOCD_CONFIG_DIR/virtualservice.yaml.tmpl" | _kubectl apply -f - >/dev/null
      _info "[argocd] Argo CD UI accessible at: https://$ARGOCD_VIRTUALSERVICE_HOST"
   fi

   if (( enable_bootstrap )); then
      _info "[argocd] Deploying GitOps bootstrap resources"
      _argocd_deploy_image_updater
      if (( ! skip_appproject )); then
         _argocd_deploy_appproject
      fi
      if (( ! skip_applicationsets )); then
         _argocd_deploy_applicationsets
      fi
      _info "[argocd] Bootstrap deployment complete!"
      _info "[argocd] View AppProjects: kubectl -n $ARGOCD_NAMESPACE get appproject"
      _info "[argocd] View ApplicationSets: kubectl -n $ARGOCD_NAMESPACE get applicationset"
      _info "[argocd] View Applications: kubectl -n $ARGOCD_NAMESPACE get application"
   fi

   _info "[argocd] Deployment complete!"
   if (( enable_vault )); then
      _info "[argocd] Retrieve admin password: kubectl -n $ARGOCD_NAMESPACE get secret $ARGOCD_ADMIN_SECRET_NAME -o jsonpath='{.data.password}' | base64 -d"
   else
      _info "[argocd] Retrieve initial admin password: kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
   fi
}

```

**Exact new block (single blank line — collapses the two surrounding blanks into one separator):**

```bash

```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/plugins/argocd.sh` | delete the orphaned `_argocd_configure_post_deploy` function (40 lines) |

---

## Rules

- Delete ONLY `_argocd_configure_post_deploy`. Do NOT touch `_argocd_configure_vault_eso`,
  `_argocd_seed_vault_admin_secret`, `_argocd_deploy_image_updater`, `deploy_argocd_bootstrap`,
  the `ARGOCD_VIRTUALSERVICE_HOST` variable (still used by `values.yaml.tmpl` + argocd-cm render),
  or any template file.
- `shellcheck -S warning scripts/plugins/argocd.sh` — zero new warnings.
- `bash -n scripts/plugins/argocd.sh` — clean.
- `bats scripts/tests/plugins/argocd_servicemonitors_ensure.bats` — still 3/3 (unaffected).
- Run `_agent_audit` before reporting done.

---

## Definition of Done

- [ ] `grep -c '_argocd_configure_post_deploy' scripts/plugins/argocd.sh` → **0** (disappearance gate)
- [ ] Exactly one blank line separates `_argocd_configure_vault_eso`'s `}` from `function _argocd_seed_vault_admin_secret()`
- [ ] `shellcheck -S warning scripts/plugins/argocd.sh` passes; `bash -n` clean
- [ ] `bats scripts/tests/plugins/argocd_servicemonitors_ensure.bats` → 3/3
- [ ] `git show --stat` shows exactly one file changed
- [ ] Committed and pushed to `k3d-manager-v1.17.0`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
refactor(argocd): remove dead _argocd_configure_post_deploy
```

---

## Follow-up — NOT in this spec's scope (newly-orphaned cascade)

Deleting the wrapper makes these provably dead (they were reachable ONLY through it). Do NOT
touch them here — they need their own owner decision (some may be intended for a future
ESO-backed / mesh-ingress argocd, and their sub-helpers may have other callers to audit):

- `_argocd_configure_vault_eso` (argocd.sh:547) — sole caller was the deleted wrapper
- `scripts/etc/argocd/virtualservice.yaml.tmpl` — sole reference was the deleted wrapper (line 590)
- transitive callees to re-audit if the above are later removed: `_argocd_setup_vault_policies`,
  `_argocd_seed_vault_admin_secret`, and the `secretstore.yaml.tmpl` / `externalsecret-*.yaml.tmpl` templates

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT delete or edit `_argocd_configure_vault_eso` or any template in this spec
- Do NOT modify any file other than `scripts/plugins/argocd.sh`
- Do NOT commit to `main` — work on `k3d-manager-v1.17.0`
