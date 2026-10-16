# Bug: the hub-only rebuild never creates the `shopping-cart-identity` Application, so `hub-recover-all` cannot restore

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.43.2`
**Status:** OPEN
**Priority:** P2 — `hub-recover-all` cannot finish on a fresh hub; a manual apply (below) unblocks it
**Approval:** pending — filed by Claude during the operator's live run `20261016T012103Z`; the fix needs operator approval
**Severity:** high — the recovery path built in `0214f363` stops before the data restore on every fresh hub

## Symptom

Live run `20261016T012103Z` (2026-10-15). After the teardown and `hub-up`, `make hub-restore`
ended:

```text
[hub-restore] 5/9 Hub reconcile            FAIL
```

with:

```text
Error from server (NotFound): applications.argoproj.io "shopping-cart-identity" not found
kubectl command failed (1): kubectl --context k3d-k3d-cluster -n cicd patch application shopping-cart-identity ...
```

The `RESUME` restore then refused at Step 1/9, because its target check needs
`identity/deployment/postgres-keycloak`:

```text
Error from server (NotFound): deployments.apps "postgres-keycloak" not found
```

## Root cause

The `shopping-cart-identity` Application (Keycloak plus `postgres-keycloak`, sourced from
`shopping-cart-infra` `identity/keycloak`) is created in one place only: the inline manifest in
`bin/cluster-up` Step 10c (`bin/cluster-up:1039`). `services-git` deliberately excludes
`services/shopping-cart-identity`, and no ApplicationSet generates it.

The hub-only path is `bin/hub-up` (cluster, Vault, LDAP, ArgoCD), then `make observability`,
`platform-ops` and `bin/hub-restore`. None of them creates the Application.
`_hub_recovery_replay_identity_hook` (`scripts/plugins/hub_recovery.sh:136`) assumes it exists and
patches it. So on a fresh hub, nothing deploys Keycloak, and `hub_data_recover` cannot run.

Earlier recoveries passed because the hub they ran against still had the Application from an
earlier `cluster-up`.

## Workaround (used on run `20261016T012103Z`)

```bash
./scripts/k3d-manager keycloak_smoke_vault_preseed
# the exact manifest from bin/cluster-up Step 10c, extracted unchanged
kubectl --context k3d-k3d-cluster apply -f identity-app.yaml
# wait until deploy/postgres-keycloak and deploy/keycloak are available (~4 min)
RESUME=<run_id> ./scripts/k3d-manager hub_data_recover
```

The data restore brings back the Keycloak database (realm and users), so the realm import in
`bin/cluster-up` Step 10d is not needed on this path.

## Fix

Move the manifest out of the `bin/cluster-up` heredoc into a file, for example
`scripts/etc/argocd/applications/shopping-cart-identity.yaml`, and have both paths apply it:

- `bin/cluster-up` Step 10c applies the file instead of the heredoc. The behaviour does not change.
- `bin/hub-up` (or `_hub_recovery_reconcile`, before `_hub_recovery_replay_identity_hook`) runs
  `keycloak_smoke_vault_preseed`, applies the file, and waits for `deploy/postgres-keycloak` to be
  available, with the same timeout and diagnostics as Step 10c.

Then `hub_data_recover` Step 1 finds its target on a fresh hub.

## Files

- `bin/cluster-up`
- `bin/hub-up` or `scripts/plugins/hub_recovery.sh`
- `scripts/etc/argocd/applications/shopping-cart-identity.yaml` (new)
- BATS for the hub-up / reconcile path
- `docs/howto/hub-rebuild-from-gitops-vault.md`

## Definition of Done

- [ ] A test proves the hub-only path applies the identity Application. Check the test fails against
      the pre-fix source.
- [ ] `bin/cluster-up` still applies the identical manifest (diff the rendered object).
- [ ] Live: the 2026-10-29 rebuild drill
      (`docs/bugs/2026-10-15-hub-recover-all-checks-keychain-after-deleting-the-hub.md`) finishes
      `make hub-recover-all` with no manual apply.
- [ ] Commit message: `fix(hub-up): create the shopping-cart-identity Application on the hub-only path`

## Also missing on the hub-only path: the ArgoCD and Keycloak port-forward agents

After the restore, `argocd.3ai-talk.org` and `keycloak.3ai-talk.org` returned 502. The tunnel sends
them to `127.0.0.1:8080` and `127.0.0.1:8880`. The teardown (`bin/cluster-down`) unloads and
deletes `com.k3d-manager.argocd-port-forward` and `com.k3d-manager.keycloak-port-forward`. Only
`bin/cluster-up` and `bin/cluster-refresh` install them, and `make refresh` also attempts an ACG
login. The wrapper scripts under `~/.local/share/k3d-manager/k3s-aws/bin/` survived.

**Workaround (used):** the two plists were generated from the `bin/cluster-refresh` template and
bootstrapped with `launchctl bootstrap gui/$(id -u)`. All three public URLs then returned 200.

**Fix:** the hub-only path (`bin/hub-restore` Step 8 "Local agents") installs both agents, reusing
the `bin/cluster-refresh` plist block through a shared helper.
