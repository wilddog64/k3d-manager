# Kyverno verifyImages 401 on private ghcr — Pod-path credential resolution

**Filed:** 2026-08-30
**Branch:** `k3d-manager-v1.27.0`
**Component:** `scripts/plugins/signing.sh`, `scripts/etc/signing/cluster-policy-verify-images.yaml.tmpl`
**Status:** ROOT-CAUSED + fixed live (Audit) on the app cluster (hostinger). Template codified.

## Symptom

Stage D Audit on the app cluster: the `verify-first-party-images` ClusterPolicy reports
`fail` on first-party pods with:

```
GET https://ghcr.io/token?scope=repository%3Awilddog64%2Fshopping-cart-basket%3Apull&service=ghcr.io: UNAUTHORIZED: authentication required
```

The same image at the same instant is reported `pass` under the **autogen** (Deployment)
rule and `fail` under the direct **Pod** rule.

## Root cause (NOT the credential)

Live diagnosis on `ubuntu-hostinger`, Kyverno `v1.19.0` (helm-managed, chart pinned 3.9.0):

- `--imagePullSecrets=ghcr-pull-secret` **is** set on the admission controller.
- `kyverno/ghcr-pull-secret` and `shopping-cart-apps/ghcr-pull-secret` are **byte-identical**
  (same sha256). The token is valid — the app pods pull with it and the Deployment/autogen
  verify path succeeds with it.
- The failing log line shows `namespace=` **empty** while `new.namespace=shopping-cart-apps`,
  `new.kind=Pod`, `new.name=` **empty**.

Kyverno's cosign verifier builds its registry keychain **only from secrets resolved against the
admitted object's `metadata.namespace`** (pod-spec `imagePullSecrets` + ServiceAccount). For a
Pod created by a ReplicaSet (`generateName`, no name/namespace on the object at CREATE), that
lookup resolves in the empty namespace and finds nothing. The cosign path does **not** fall back
to the global `--imagePullSecrets` flag, nor to a mounted `DOCKER_CONFIG` DefaultKeychain (both
tested — see below). Workload controllers (Deployment/StatefulSet/…) carry a populated
`metadata.namespace`, so their credential resolution succeeds — hence the autogen path passes.

## Remediation tree (executed live, in order)

1. **Restart admission controller** (force keychain reload) → still 401. Rules out stale/boot-order keychain.
2. **Resource creds + DefaultKeychain**: default SA in both app ns already carried
   `ghcr-pull-secret`; app SAs and pod-spec `imagePullSecrets` present; also mounted the
   dockerconfig as `DOCKER_CONFIG` on the admission controller → **still 401**. Proves the cosign
   path ignores every credential source except object-namespace resolution.
3. **Gate at workload-controller kinds instead of `Pod`** → **verifies clean, 401 eliminated.**
   `basket` + `order` verify `verifiedCount=1`; `product-catalog` now surfaces a *genuine*
   `no signatures found` (a real Audit finding, not auth — see below).

## Fix

`cluster-policy-verify-images.yaml.tmpl`: match `Deployment, StatefulSet, DaemonSet, Job,
CronJob` (the paths whose object namespace is populated) instead of `Pod`. Kyverno extracts
images from the pod template of each matched controller and verifies with resolvable creds.

### Trade-off (documented)

Bare Pods and directly-created ReplicaSets are no longer matched — a Pod started outside a
controller with an unsigned first-party image would not be verified. Acceptable: every app
workload in `shopping-cart-apps`/`-payment` is a controller, and the CVE-loop threat is the
deploy pipeline (Deployments), not hand-run pods. Revisit adding `Pod` back only if a Kyverno
release fixes the `generateName` empty-namespace credential resolution.

## Separate follow-up (surfaced by the fix, NOT this bug)

`product-catalog` deployed digest
`ghcr.io/wilddog64/shopping-cart-product-catalog@sha256:53e66832…` returns **no signatures
found**. Either that digest predates signing or was never signed. Must be re-signed / re-promoted
to a signed digest before `--enforce`, else Enforce blocks product-catalog rollouts.

## Enforce gate (still blocked)

Do NOT flip `--enforce` until: (a) this template fix is applied on the app cluster via
`deploy_image_signing --app-cluster`, (b) all first-party deployed digests report signed
(product-catalog resolved), (c) Audit shows zero would-be-blocks.
