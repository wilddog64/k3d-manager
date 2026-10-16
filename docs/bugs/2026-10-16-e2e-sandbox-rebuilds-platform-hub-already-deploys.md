# Bug: e2e-sandbox rebuilds a platform the hub already deploys to the sandbox

**Status:** OPEN — reproduced 2026-10-16; design a′ specced in `docs/plans/v1.43.4-e2e-sandbox-hub-stripe-profile.md`, dispatched to Codex 2026-10-16
**Priority:** P2
**Filed:** 2026-10-16
**Detected by:** live run (operator's `make e2e-sandbox`, verified by Claude)
**Affected:** `make e2e-sandbox` (Tier 2), `scripts/plugins/e2e.sh` `e2e_verify_sandbox`
**Branch:** `k3d-manager-v1.43.4` (proposed, next to the other two e2e-sandbox bugs)
**Approval:** explicit 2026-10-16 "let's do a`" (operator) — option (a′) below
**Related:** `docs/bugs/2026-10-15-e2e-sandbox-argocd-crd-helm-ownership-conflict.md` (same class,
fixed in v1.43.3), `docs/bugs/2026-10-13-e2e-sandbox-does-not-provision-missing-acg-cluster.md`

## Observed failure

Run `1792169905-3394` at 2026-10-16T16:58Z, commit `b4a2bfff`, log
`~/.k3dm/e2e/make-e2e-sandbox-20261016T165825Z.log`. It passed the new `checking-argocd` phase
(`reusing cicd/argocd-ubuntu-k3s-server`), then failed at `configuring-vault`:

```text
INFO: [acg-up] vault-bridge Service applied (DNS: vault-bridge.secrets.svc.cluster.local:8201)
env: ‘vault’: No such file or directory
ERROR: failed to execute [redacted command containing secrets]: 127
```

## Cause

Tier 2 was written when the sandbox was a bare cluster. `cluster-up` (k3s-aws) now registers the
sandbox with the hub, and the hub's app-cluster ApplicationSets deploy the whole platform to it.
Read-only state at 2026-10-16 ~17:00Z:

- Hub `cicd` has 12 `ubuntu-k3s-*` Applications (istio, data layer, ESO, platform, the four
  shopping-cart services, frontend, namespace), all Synced and Healthy. `shopping-cart-apps` on the
  sandbox runs basket, frontend, order and product-catalog.
- The sandbox's ClusterSecretStore `vault-backend` is Valid and Ready, using **`tokenSecretRef`**
  (`secrets/vault-token`), the same auth the e2e manifest applies.

Against that, `e2e_verify_sandbox` repeats setup that is now wrong:

1. **`_e2e_sandbox_configure_vault_token_review` is unused and harmful.**
   - It configures `auth/kubernetes-ubuntu-k3s` on the hub Vault, but no store uses Kubernetes
     auth.
   - It needs a local `vault` CLI (absent, hence 127) and `HUB_VAULT_TOKEN`, which defaults to empty.
   - It sets `kubernetes_host=https://kubernetes.default.svc:443`, which the hub Vault cannot reach.
   - It leaves a live ServiceAccount token file in `$TMPDIR` when `vault write` fails: the
     `rm -f` after it never runs because `_run_command` exits through `_err`.
2. **`applying-appsets` would create a second controller.** It renders the four ApplicationSets
   into the sandbox's own Argo CD, aimed at the in-cluster registration it creates. The hub already
   manages the same resources, so two Argo CDs would fight over them. Its order/payment overrides
   would be reverted by the hub's self-heal.
   This run never reached that step. Fixing item 1 alone would expose it.
3. The run did leave one harmless change: Secret `cicd/ubuntu-k3s` on the sandbox (an in-cluster
   cluster registration nothing selects). It dies with the sandbox.

Test side note: the BATS suite also leaves many 0-byte `e2e-sandbox-token.*` files in the real
`$TMPDIR`. The tests don't redirect `mktemp`.

## Expected

Tier 2 adds only what is specific to the Stripe e2e run on top of what `cluster-up` and the hub
already deploy:

- check the hub's `ubuntu-k3s-*` Applications are Synced and Healthy;
- provision the Stripe test secret;
- apply the order/payment Stripe overrides in a way the hub does not revert;
- run the Playwright job.

No Vault configuration, no Argo CD registration, and no appset apply.

## Design question (operator)

How should the sandbox-only order/payment overrides reach the cluster now that the hub owns those
Deployments?

- (a) Through the hub: an e2e values overlay selected for `ubuntu-k3s` only.
- (b) Pause hub self-heal for the two Applications during the run, then resume (`ignoreDifferences`
  and `RespectIgnoreDifferences`).
- (c) Drop the overrides, if the hub's sandbox values already enable Stripe test mode.

Claude's recommendation: check (c) first, otherwise (a). Option (b) leaves state that a crashed run
would never restore.

### (c) checked 2026-10-16: not viable

Live sandbox (`ubuntu-k3s`, read-only) against what the e2e overrides set:

| Setting | Hub deploys | e2e needs |
|---|---|---|
| `payment.gateway.default` | `mock` | `stripe` |
| `mock.gateway.enabled` | `true` | `false` |
| order `BASKET_URL` / `PAYMENT_URL` | absent | in-cluster service URLs |
| payment `oauth2.jwk-set-uri` | `keycloak.identity.svc` (no `identity` namespace on the sandbox) | `keycloak.3ai-talk.org` |

The last two rows are wrong on the sandbox whatever the mode; fix them in the hub's base values for
`ubuntu-k3s`, not in the e2e overlay.

## Decision: (a′) — hub overlay switched on by a cluster label, only during a run

Chosen over (a) "always Stripe on the sandbox": e2e runs rarely, so the sandbox keeps the mock
gateway between runs, the Stripe key stays ephemeral (Keychain → `stripe-e2e` during the run, no
Vault/ESO change), and an idle sandbox does not depend on Stripe.

Shape, and the guards the spec must carry:

1. **One ApplicationSet, label-selected values.** The order/payment sets pick an extra values file
   from the cluster label `k3dm.k3d.io/e2e-profile`, defaulting to `none` (an empty
   `values-none.yaml`) so an unlabelled cluster renders. Not two ApplicationSets: both would claim
   the same Application names and Argo CD would delete and recreate them on each flip.
2. **Run flow in `e2e_verify_sandbox`:** label the hub's `ubuntu-k3s` registration Secret
   `e2e-profile=stripe` → wait (bounded) until the sandbox ConfigMap shows
   `payment.gateway.default=stripe` → `rollout restart` + `rollout status` order and payment →
   Playwright. Restarting before the sync lands would run on the old config.
3. **Exit trap removes the label** on success and failure, then waits for the mock values to return
   (best effort, logged).
4. **`cluster-up` registers the sandbox without the label**, so a label left by a crash cannot carry
   into a rebuilt sandbox (where payment would start in Stripe mode with no key). Verify the
   registration path overwrites labels; add the removal if it does not.
5. **Delete** `_e2e_sandbox_configure_vault_token_review`, the `applying-appsets` step and the
   in-cluster registration from `e2e_verify_sandbox` (items 1–2 of Cause). Keep the `checking-argocd`
   phase, reworded to check the hub's `ubuntu-k3s-*` Applications are Synced and Healthy.
6. New hub coupling: the run needs the hub context to set the label. A down hub fails the run early
   with a clear message.
7. Live proof only after `make appsets-reapply` on the release branch.

## Workaround

None for Tier 2. Tier 1 (vCluster) is unaffected.
