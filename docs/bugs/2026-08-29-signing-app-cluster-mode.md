# `deploy_image_signing --app-cluster` — deploy the verifyImages gate without hub Vault

**Filed:** 2026-08-29
**Area:** `scripts/plugins/signing.sh` — `deploy_image_signing`, `_signing_install_kyverno`
**Type:** enhancement / implementation gap
**Part of:** `docs/plans/v1.27.0-image-signing-cve-loop-closure.md` (Stage D / rollout Stage 2)
**Related:** `docs/bugs/2026-07-07-app-cluster-vault-portability.md` (Vault endpoint = the open seam)

## Problem

Stage D rollout requires `deploy_image_signing --audit` on the **app cluster**
(shopping-cart namespaces on hostinger / ACG), NOT the hub. But `deploy_image_signing`
calls `signing_init → _vault_login` unconditionally, and `_vault_login` reads the
`vault-root` secret and execs the Vault pod **in the current kube context**. Vault is
hub-only (`project_infra_placement`), so running the command against the app-cluster
context aborts in `signing_init` before Kyverno ever installs.

The app cluster does not need the hub Vault steps at all:
- the cosign **private** key seed, Vault policy, and ESO read-grant already ran on the hub
  in Stage C;
- the app cluster gets the cosign **public** key through its existing ESO
  `ClusterSecretStore vault-backend` (Valid/Ready on hostinger), via the
  `externalsecret-cosign-pub.yaml.tmpl` ExternalSecret.

So the app-cluster side is only: install Kyverno, apply the pub-key ExternalSecret, wait
for ESO to populate the secret, apply the ClusterPolicy.

## Fix

### 1. `--app-cluster` flag (alias `--skip-vault-init`)
Add to the `deploy_image_signing` arg parser. Sets `app_cluster=1`. Update `--help`.

### 2. Branch `deploy_image_signing`
- When `app_cluster=1`: skip `signing_init` (hub Vault) entirely; emit an `_info`
  breadcrumb naming the ESO store the public key arrives through.
- Otherwise: unchanged — `signing_init` as today (hub path).

### 3. Ordering (app-cluster path)
The ExternalSecret targets the `${SIGNING_ADMISSION_NAMESPACE}` (kyverno) namespace, which
does not exist on a fresh app cluster. So for `app_cluster=1`:
1. `_signing_install_kyverno` (chart `--create-namespace` creates the kyverno ns) + wait.
2. `_signing_apply_pub_externalsecret` (ExternalSecret now lands in the existing ns).
3. `_signing_wait_pub_secret` (new helper) — poll until ESO populates
   `${SIGNING_ADMISSION_NAMESPACE}/${SIGNING_PUB_SECRET_NAME}` `.data.cosign\.pub`.
4. `_signing_apply_cluster_policy` (reads that secret, renders the key into the policy).

The hub path (`app_cluster=0`) is left VERBATIM — `signing_init` already applies the
ExternalSecret, and the pre-existing hub kyverno ns makes ordering a non-issue there.

### 4. `_signing_wait_pub_secret` (new private helper)
Poll `SIGNING_PUB_SECRET_WAIT_TRIES` (default 30) × 5s for a non-empty
`.data.cosign\.pub`; `_err` + return 1 on timeout.

### 5. Kyverno resource knob for constrained single-node app clusters
Kyverno 3.9.0 defaults to 3 admission-controller replicas — too heavy for the 2-CPU
hostinger node (requests already ~80%). Add optional `SIGNING_KYVERNO_HELM_SET`
(space-separated `key=value`) appended as `--set key=value` args in
`_signing_install_kyverno`. Live run exports e.g.
`admissionController.replicas=1 backgroundController.replicas=1
cleanupController.replicas=1 reportsController.replicas=1`. Default empty → hub behavior
unchanged.

## Safety
- Audit keeps `SIGNING_WEBHOOK_FAILURE_POLICY=Ignore` (fail-open): even an unhealthy
  Kyverno cannot block pod admission on the live payment cluster.
- No `--enforce` in this slice. Enforce stays gated behind `SIGNING_ALLOW_ENFORCE=1` and a
  clean Audit PolicyReport (D2).
- Additive only: hub path and every existing flag unchanged; new env vars default to
  prior behavior.

## Constraints (repo rules)
- Minimal patch; keep `${var}` quoting, `_`-prefixed privates, LF, `set -euo pipefail`,
  no inline comments beyond `_info`/`_warn`.
- Do NOT touch `scripts/lib/` subtrees.

## BATS (`scripts/tests/plugins/signing.bats` — extend; stubbed helm/kubectl harness)
- `deploy_image_signing --help` mentions `--app-cluster`.
- `deploy_image_signing --bogus` still errors "Unknown option" (unchanged).
- `_signing_install_kyverno` appends `--set k=v` for each `SIGNING_KYVERNO_HELM_SET` entry.
- `_signing_install_kyverno` with empty `SIGNING_KYVERNO_HELM_SET` emits no `--set`
  (hub behavior unchanged).

## Live verification — CLAUDE ONLY (hostinger app cluster)
1. `kubectl config` context = `ubuntu-hostinger`; confirm CSS `vault-backend` Valid.
2. `SIGNING_KYVERNO_HELM_SET='admissionController.replicas=1 ...' deploy_image_signing
   --audit --app-cluster` (context ubuntu-hostinger).
3. Kyverno pods schedule (no FailedScheduling) and become Ready; ExternalSecret
   `SecretSynced`; `cosign-public-key` secret present with `cosign.pub`.
4. ClusterPolicy `verify-first-party-images` applied, `failureAction: Audit`.
5. Inspect PolicyReports in shopping-cart-apps / shopping-cart-payment for would-be-blocks;
   record the count. STOP before `--enforce`.
6. Rollback lever if the node cannot schedule Kyverno: `helm uninstall kyverno -n kyverno`
   + delete the ClusterPolicy (fail-open Audit means no workload impact meanwhile).

## Discovered live prerequisites (2026-08-29, hostinger) — the portability seam in full

The app cluster runs its **own** Vault (`vault-0` in `secrets`, bridged to the hub via
`vault-bridge`, NOT a KV replica). So the pub-key ExternalSecret's
`ClusterSecretStore vault-backend` reads the **app-cluster** Vault, where the cosign
material and the ESO read-grant did NOT exist. Two one-time app-Vault provisioning steps
are required and are currently manual (candidates to codify into a `signing`-owned helper):

1. **Seed the public key into the app-cluster Vault:** `vault kv put secret/cosign/signing
   cosign.pub=<PEM>` on the app-cluster Vault (public key ONLY — the private key stays
   hub-side; least privilege). Read the PEM from the hub Vault
   (`vault kv get -field=cosign.pub secret/cosign/signing`).
2. **Grant the app-cluster ESO role read:** the CSS uses Vault role `eso-app-cluster`
   (auth mount `kubernetes-ubuntu-hostinger`, policy `app-cluster-reader`). Add
   `secret/data/cosign/*` (read) + `secret/metadata/cosign/*` (read,list) to
   `app-cluster-reader` (extend the existing policy — do NOT partial-write the role, which
   resets omitted fields). Root token via stdin, never argv.

Then the ExternalSecret goes `SecretSynced` and `_signing_wait_pub_secret` succeeds.

**Follow-on finding (registry auth):** even with the policy live, Kyverno cannot verify the
private `ghcr.io/wilddog64/*` images — 401 UNAUTHORIZED — so it reports them `unverified`.
See `docs/issues/2026-08-29-kyverno-verifyimages-ghcr-registry-auth.md`. Kyverno needs
ghcr pull creds (`--imagePullSecrets`) before Enforce is safe. Signatures are known-good
(Stage C). This is the next Stage D increment.

## Live status (2026-08-29)
- `--app-cluster` flag + Kyverno reorder + `_signing_wait_pub_secret` + `SIGNING_KYVERNO_HELM_SET`: shipped (`ec746ade`).
- Kyverno 1.19 field-name fix (`ignoreTlog`/`ignoreSCT`): shipped (`bbbacfe0`).
- Live on hostinger: Kyverno 4/4 Running (1 replica each, node scheduled fine), pub key seeded + ESO grant applied, `cosign-public-key` SecretSynced, `verify-first-party-images` ClusterPolicy Ready (Audit). **Blocked on registry-auth finding before Enforce.**
