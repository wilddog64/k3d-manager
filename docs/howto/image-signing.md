# How-To: Image signing & admission verification (cosign + Kyverno)

This is the cluster-side half of the CVE-loop image-signing work
(`docs/plans/v1.27.0-image-signing-cve-loop-closure.md`). It covers the signing
key material, the CI signing that produces signatures, and the Kyverno
admission policy that verifies them. The staged rollout is **Audit → Enforce**
(decision D2): never flip to blocking on a live fleet before Audit is clean.

## The three latches

```
 BUILD (shopping-cart CI)      PROMOTE (k3d-manager)        ADMIT (app cluster)
   cosign sign --by-digest  ->  cosign verify before pin ->  Kyverno verifyImages
```

- **Build** — each first-party image is signed by digest with the Vault-held
  cosign key, delivered to CI as the `COSIGN_KEY` / `COSIGN_PASSWORD` GH secrets
  (runners cannot reach Vault). Done in the publish workflows (Stage C).
- **Admit** — a Kyverno `ClusterPolicy` (`verify-first-party-images`) requires a
  valid cosign signature by our public key for `ghcr.io/wilddog64/*` images in
  the app namespaces. This how-to.
- **Promote** — the CVE promoter runs `cosign verify` on a candidate digest
  before pinning it (follow-up slice; not yet wired).

## Key material (prerequisite)

`signing_init` is idempotent — it seeds the cosign key pair into Vault
`secret/cosign/signing` (`cosign.key` / `cosign.password` / `cosign.pub`), backs
the private key + password up to the macOS Keychain (`k3d-manager-signing`), and
projects `cosign.pub` into the admission namespace via ESO as the
`cosign-public-key` Secret.

```bash
./scripts/k3d-manager signing_init      # seed key + policy + ESO pub secret (idempotent)
./scripts/k3d-manager signing_status    # vault_key / keychain_backup / eso_public_secret
```

> **CI secret hygiene.** Seed `COSIGN_KEY` from the true PEM **through a file**,
> never `--body "$(security -w …)"`: macOS `security find-generic-password -w`
> emits **hex** for any value containing a newline (every PEM), which cosign
> rejects as `invalid pem block`. Recover the bytes with `xxd -r -p`, or pull
> `cosign.key` from Vault. See
> `docs/bugs/2026-08-28-stage-c-cosign-signing-fails-post-merge.md`.

## Admission verification — `deploy_image_signing`

Run this **against the app cluster context** (where the shopping-cart pods are
admitted — the ACG/hostinger app clusters), not the laptop hub. The hub runs
ArgoCD/Vault and has no first-party app namespaces, so a policy there has
nothing to verify.

```bash
# default: install Kyverno (pinned chart) + apply the policy in AUDIT
./scripts/k3d-manager deploy_image_signing --audit
```

What it does:

1. `signing_init` (idempotent) — ensures the key + the `cosign-public-key` ESO
   Secret exist.
2. `_signing_install_kyverno` — `helm upgrade --install` of `kyverno/kyverno`
   pinned to `SIGNING_KYVERNO_HELM_CHART_VERSION` (A08 — no floating latest).
3. `_signing_apply_cluster_policy` — reads `cosign.pub` from the in-cluster ESO
   Secret, injects it into `cluster-policy-verify-images.yaml.tmpl`, and applies
   the `ClusterPolicy`. On key rotation, re-run to refresh the inlined key.

### Scope boundary (critical)

The policy matches **Pods in `shopping-cart-apps` and `shopping-cart-payment`
only**, and only images matching `ghcr.io/wilddog64/*`. Upstream images
(postgres, redis, rabbitmq, argocd, `alpine/k8s`, …) are **not** signed and are
deliberately left untouched — an unscoped policy would block the whole platform.
Hub/system namespaces are never matched.

### Audit → Enforce

Audit reports would-be-blocks without blocking:

```bash
kubectl get clusterpolicyreports -A                    # policy report summary
kubectl get policyreports -n shopping-cart-apps        # per-namespace detail
```

Only after the reports show **zero** would-be-blocks for the current first-party
images do you flip to Enforce — and it is gated behind an explicit confirmation:

```bash
SIGNING_ALLOW_ENFORCE=1 ./scripts/k3d-manager deploy_image_signing --enforce
```

Enforce rejects unsigned first-party pods in the app namespaces. The admission
webhook is `failurePolicy: Ignore` (fail-open) during Audit; revisit that choice
deliberately for Enforce on a solo-operated fleet.

## Configuration

| Env Var | Default | Description |
|---|---|---|
| `SIGNING_KYVERNO_HELM_CHART_VERSION` | `3.9.0` | Pinned Kyverno chart (A08) |
| `SIGNING_ADMISSION_NAMESPACE` | `kyverno` | Namespace for Kyverno + the ESO pub Secret |
| `SIGNING_PUB_SECRET_NAME` | `cosign-public-key` | ESO-projected Secret holding `cosign.pub` |
| `SIGNING_POLICY_NAME` | `verify-first-party-images` | ClusterPolicy name |
| `SIGNING_IMAGE_REFERENCES` | `ghcr.io/wilddog64/*` | Images the policy verifies |
| `SIGNING_VALIDATION_FAILURE_ACTION` | `Audit` | `Audit` or `Enforce` (Enforce also needs `SIGNING_ALLOW_ENFORCE=1`) |
| `SIGNING_WEBHOOK_FAILURE_POLICY` | `Ignore` | Admission webhook failure policy |

## Promoter verify gate (the third latch)

The Hub CVE promoter (`scripts/etc/argocd/platform-ops/app-cve-scan.sh`, CronJob
`app-cve-scan`) runs `cosign verify --key <our pub>` on a clean `sha-*` candidate
digest **before** it pins that digest into the ArgoCD Application. An unverifiable
candidate is not a promotable candidate: the promoter skips it, notifies
(`App CVE Promotion Blocked (unsigned)`), and moves on — **fail-closed**. This keeps
the promoter and Kyverno admission agreeing on what "signed" means (key-based,
`--insecure-ignore-tlog=true`, mirroring the ClusterPolicy's `rekor.ignoreTlog: true`)
so a promotion can never dead-end at admission on an unsigned image.

The public key reaches the CronJob via an ESO `ExternalSecret`
(`cosign-pub-externalsecret.yaml`) projecting Hub Vault `cosign/signing` → Secret
`platform-ops/cosign-public-key`, mounted read-only at `/cosign`. `cosign` is
downloaded (pinned `COSIGN_VERSION`) at runtime the same way `kubectl` is.

| Env Var | Default | Description |
|---|---|---|
| `COSIGN_VERIFY` | `1` (CronJob) | Master switch for the promoter verify gate |
| `COSIGN_VERSION` | `v2.4.1` | Pinned cosign release (matches CI signer; A08) |
| `COSIGN_PUBLIC_KEY_FILE` | `/cosign/cosign.pub` | ESO-projected public key path |
| `COSIGN_VERIFY_FLAGS` | `--insecure-ignore-tlog=true` | Mirrors the Kyverno policy's `rekor.ignoreTlog` |

## Not yet done (follow-up slice)

- **Attestation.** Stage C signs but does not `cosign attest` (Trivy vuln + SBOM)
  yet, so both the policy and the promoter gate are **signature-only**. Add
  `cosign attest` in CI, then tighten each verify to require a passing vuln
  attestation (`verify-attestation --type vuln`).
- **Codify app-cluster wiring.** Fold the hand-run hostinger steps (app Vault
  cosign.pub seed/grant, kyverno-ns ghcr imagePullSecret ES) into `signing.sh`.
