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

## Follow-up 1 — unsigned deployed digests (RESOLVED 2026-08-30, `ce4374ff`)

Auditing all five first-party deployed images (not just basket+order) surfaced **two** with
`no signatures found` — both 2026-08-26 builds that predate working signing CI:

| service         | old (unsigned) digest | new (signed) digest |
|-----------------|-----------------------|---------------------|
| product-catalog | `sha256:53e66832…`    | `sha256:3db7b8da…`  |
| payment         | `sha256:95f2680c…`    | `sha256:3b5f478c…`  |

Both re-pinned to the current signed release digests (2026-08-28 builds; cosign-verified against
the public key; multi-arch amd64+arm64 index) in
`services/shopping-cart-{product-catalog,payment}/kustomization.yaml`. ArgoCD (hub `cicd`) synced
both; the new pods run the signed digests and their PolicyReports now show `pass`.

## Follow-up 2 — frontend fails even at controller level (dedicated-SA requirement)

**RESOLVED 2026-08-30.** Verifying the remaining service (`frontend`) at the Deployment level
still 401'd, while `basket`/`order` (also tag-based) passed. The empty `namespace=` symptom
recurs in the log for `new.kind=Deployment new.name=frontend`. Isolation: re-triggering a
**passing** service (`basket`) via the identical `kubectl annotate` UPDATE still passed — so the
trigger method is not the cause; the workload wiring is.

**Refined root cause:** Kyverno's cosign verifier resolves the registry keychain from the
workload's **dedicated named ServiceAccount's `imagePullSecrets`**. The passing four services each
run as a dedicated SA (`basket-service`, `order-service`, `product-catalog`, `payment-service`)
carrying `ghcr-pull-secret`. `frontend` alone ran as the **`default` SA** with the secret only on
the **pod-template `imagePullSecrets`** — a source the cosign path does **not** resolve (even
though the `default` SA also carried it). So verifyImages needs **two** conditions to authenticate
to private ghcr: (1) match controllers, not `Pod`; (2) the workload runs as a dedicated
(non-`default`) SA whose `imagePullSecrets` carry the ghcr cred.

**Fix:** `services/shopping-cart-frontend/` — add a dedicated `frontend` ServiceAccount with
`imagePullSecrets: [ghcr-pull-secret]` and point the Deployment at it (replacing the pod-template
`imagePullSecrets` patch), mirroring the other four services.

## Policy re-apply (done)

The live policy was a hand-patch. Re-applied durably from the committed template via
`deploy_image_signing --app-cluster --audit` (helm rev 5, values preserved via
`SIGNING_KYVERNO_HELM_SET`; ESO cosign.pub re-synced; ClusterPolicy applied from the template —
match kinds `[Deployment,StatefulSet,DaemonSet,Job,CronJob]`, Audit). The stray `ghcr-docker`
volume left on the admission controller by the Step-2 experiment was removed.

## Enforce gate

Do NOT flip `--enforce` until all first-party services report `pass` in Audit. As of
2026-08-30 the four passing (basket, order, product-catalog, payment) + frontend (after the
dedicated-SA fix syncs) cover all five. Confirm zero `fail` in the PolicyReports across
`shopping-cart-apps` + `shopping-cart-payment`, then `SIGNING_ALLOW_ENFORCE=1
deploy_image_signing --enforce --app-cluster`.
