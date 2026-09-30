# Bug: quay.io/minio is no longer anonymously pullable — repoint the data layer

**Filed:** 2026-09-25
**Work repo:** `shopping-cart-infra` (NOT k3d-manager)
**Branch (work repo):** `fix/minio-bitnamilegacy-registry` — create from `origin/main`
**Severity:** blocks `make up CLUSTER_PROVIDER=k3s-aws` at Step 10b on every fresh cluster
**Status:** FIXED and verified live 2026-09-30 — `shopping-cart-infra` `f909906` (#102). Follow-up: CVEs in the sunset image, see the end of this doc.

## Symptom

`minio-0` never starts; the `<cluster>-data-layer` ArgoCD Application stays `OutOfSync` /
`Progressing` with `operationState.phase: Running`, message
`waiting for healthy state of apps/StatefulSet/minio`. `cluster-up` then fails:

```
ERROR: [acg-up] data-layer ArgoCD Application did not reach Synced after force-sync + 180s retry
```

```
Failed to pull image "quay.io/minio/minio:RELEASE.2024-11-07T00-52-20Z":
  failed to resolve reference: unexpected status from HEAD request to
  https://quay.io/v2/minio/minio/manifests/RELEASE.2024-11-07T00-52-20Z: 401 UNAUTHORIZED
```

All six other StatefulSets in `shopping-cart-data` are healthy. Only MinIO is affected.

## Root cause

`quay.io/minio/minio` and `quay.io/minio/mc` now require authentication for **every** tag. This is
a repository-level gate, not a missing tag, and not a network or node-credential problem:

| probe | result |
|---|---|
| `quay.io/minio/minio:RELEASE.2024-11-07T00-52-20Z` (anon pull token) | 401 |
| `quay.io/minio/minio:latest` | 401 |
| `quay.io/minio/minio:RELEASE.2022-01-08T03-11-54Z` | 401 |
| `quay.io/minio/mc:latest` | 401 |
| `quay.io/prometheus/busybox:latest` (control) | **200** |
| `ghcr.io/minio/minio:latest` | 403 |
| `docker.io/minio/minio` | does not exist |

**A GHCR mirror is not possible** — mirroring requires pulling the source first, and we have no
credentials for it. The only public source carrying the *same* upstream releases is Bitnami's
legacy repository:

| replacement | current pin | same upstream release |
|---|---|---|
| `docker.io/bitnamilegacy/minio:2024.11.7-debian-12-r1` | `quay.io/minio/minio:RELEASE.2024-11-07T00-52-20Z` | yes — MinIO 2024-11-07 |
| `docker.io/bitnamilegacy/minio-client:2024.11.5-debian-12-r1` | `quay.io/minio/mc:RELEASE.2024-11-05T11-29-45Z` | yes — mc 2024-11-05 |

Both return 200 anonymously (verified 2026-09-25).

## Why this is a port, not a tag swap

The Bitnami images have a different layout. Verified from the image configs:

| | quay.io/minio | bitnamilegacy/minio |
|---|---|---|
| `User` | 1000 | **1001** |
| `Entrypoint` | none | `/opt/bitnami/scripts/minio/entrypoint.sh` |
| `Cmd` | none | `/opt/bitnami/scripts/minio/run.sh` |
| data dir | `/data` (via args) | **`/bitnami/minio/data`** |
| `mc` binary | `/usr/bin/mc` | **`/opt/bitnami/minio-client/bin/mc`** (also on `PATH`) |

Consequences you MUST handle:

- The existing `args: [server, /data, --console-address, ":9001"]` must be **removed**. Bitnami's
  entrypoint runs its own `run.sh`; passing those args replaces it and the container fails because
  `server` is not an executable.
- `runAsUser` / `fsGroup` must become `1001`, or the PVC is not writable.
- The volume mount path must become `/bitnami/minio/data`.
- Bitnami defaults are API `9000` and console `9001`, which already match the Service and probes —
  do not add port env vars.
- `envFrom: secretRef: minio-credentials` works unchanged: the secret already exposes
  `MINIO_ROOT_USER` and `MINIO_ROOT_PASSWORD`, which is exactly what the Bitnami image reads.
  **Do not touch `secret.yaml`.**
- Health endpoints `/minio/health/live` and `/minio/health/ready` are served by MinIO itself and
  remain correct. Do not change the probes.
- `readOnlyRootFilesystem` must stay `false` — Bitnami writes under `/opt/bitnami`.

## Before You Start

1. Read `memory-bank/activeContext.md` in k3d-manager for the 2026-09-25 entries on this failure.
2. `git -C <shopping-cart-infra> fetch origin`
3. `git -C <shopping-cart-infra> checkout -b fix/minio-bitnamilegacy-registry origin/main`
4. Read all three target files in full before editing:
   - `data-layer/minio/statefulset.yaml`
   - `data-layer/minio/bucket-init-job.yaml`
   - `data-layer/minio/image-upload-job.yaml`

Target files are **exactly those three**. Do not touch `secret.yaml`, `service.yaml` or
`image-upload-configmap.yaml`.

## Change 1 — `data-layer/minio/statefulset.yaml`

Replace:

```yaml
      securityContext:
        fsGroup: 1000
        runAsUser: 1000
        runAsNonRoot: true
      containers:
        - name: minio
          image: quay.io/minio/minio:RELEASE.2024-11-07T00-52-20Z
          imagePullPolicy: IfNotPresent
          args:
            - server
            - /data
            - --console-address
            - ":9001"
          ports:
```

with:

```yaml
      securityContext:
        fsGroup: 1001
        runAsUser: 1001
        runAsNonRoot: true
      containers:
        - name: minio
          image: docker.io/bitnamilegacy/minio:2024.11.7-debian-12-r1
          imagePullPolicy: IfNotPresent
          ports:
```

Replace:

```yaml
          volumeMounts:
            - name: data
              mountPath: /data
```

with:

```yaml
          volumeMounts:
            - name: data
              mountPath: /bitnami/minio/data
```

## Change 2 — `data-layer/minio/bucket-init-job.yaml`

Replace:

```yaml
          image: quay.io/minio/mc:RELEASE.2024-11-05T11-29-45Z
```

with:

```yaml
          image: docker.io/bitnamilegacy/minio-client:2024.11.5-debian-12-r1
```

The job sets `command: [sh, -c, ...]`, which overrides the Bitnami entrypoint, and `mc` is on
`PATH` in this image — so the script body needs no change. Leave `MC_CONFIG_DIR=/tmp/.mc` exactly
as it is; it is load-bearing (the image runs as non-root and cannot write `/root/.mc` — see
`docs/bugs/2026-05-23-minio-bucket-init-mc-config-dir.md`).

## Change 3 — `data-layer/minio/image-upload-job.yaml`

Replace:

```yaml
        - name: copy-mc
          image: quay.io/minio/mc:RELEASE.2024-11-05T11-29-45Z
          imagePullPolicy: IfNotPresent
          command:
            - sh
            - -c
            - cp /usr/bin/mc /shared/mc
```

with:

```yaml
        - name: copy-mc
          image: docker.io/bitnamilegacy/minio-client:2024.11.5-debian-12-r1
          imagePullPolicy: IfNotPresent
          command:
            - sh
            - -c
            - cp /opt/bitnami/minio-client/bin/mc /shared/mc
```

Do not change the `uploader` container — `python:3.12-slim` is unaffected.

## Rules

- No other file may change. No refactors, no reformatting, no comment churn.
- LF line endings. Preserve existing indentation exactly (2-space YAML, as in the files).
- Keep image references pinned to the exact tags given above. Never `latest`.
- Run `python3 -c "import yaml,sys;[list(yaml.safe_load_all(open(f))) for f in sys.argv[1:]]"` over
  all three files and paste the result — it must exit 0.
- Confirm no `quay.io/minio` reference survives under `data-layer/`:
  `grep -rn 'quay.io/minio' data-layer/ || echo NONE` — must print `NONE`.
- Confirm the removed args are gone: `grep -n 'console-address' data-layer/minio/statefulset.yaml`
  must produce no output.

## Definition of Done

- [ ] Branch `fix/minio-bitnamilegacy-registry` created from `origin/main` in `shopping-cart-infra`
- [ ] The three changes above applied, and nothing else
- [ ] YAML parses; the two grep gates above produce the stated output — paste all three
- [ ] `CHANGELOG.md` gains an `### Fixed` entry under `[Unreleased]` naming the registry gate as
      the cause and both replacement images
- [ ] A bug doc at `docs/bugs/2026-09-25-minio-quay-registry-gated.md` in `shopping-cart-infra`
      recording the 401 evidence table, why a GHCR mirror is impossible, and the layout deltas
- [ ] Commit message exactly:
      `fix(data-layer): repoint MinIO to bitnamilegacy after quay gated anonymous pulls`
- [ ] `git push origin fix/minio-bitnamilegacy-registry` — do NOT report done until the push
      succeeds; verify with `git rev-parse origin/fix/minio-bitnamilegacy-registry`
- [ ] Report the commit SHA and paste `git show --stat <sha>`

## What NOT to Do

- Do NOT create a pull request.
- Do NOT merge anything.
- Do NOT commit to `main`, and do NOT force-push anything.
- Do NOT use `--no-verify`.
- Do NOT modify files outside the three listed targets.
- Do NOT edit `secret.yaml` — the env var names already match Bitnami.
- Do NOT change probe paths, ports, resources, or the PVC size/storageClass.
- Do NOT apply anything to a live cluster. No `kubectl`, no `argocd`. ArgoCD will pick this up.
- Do NOT attempt to log in to quay.io or add a pull secret.

## Follow-up (NOT part of this task)

`bitnamilegacy` is itself a sunset repository and will not receive updates. Once this is green, the
durable fix is to mirror both pinned images into `ghcr.io/wilddog64/` — which *is* possible because
bitnamilegacy is public — so a second upstream gate cannot break provisioning again. That needs a
GHCR push credential and is the owner's call.

---

## Recurrence and completion brief (2026-09-30, Claude)

**Still live.** `shopping-cart-infra` `main` (`00d0d8a`) still pins `quay.io/minio/minio` and
`quay.io/minio/mc`. The fix branch `fix/minio-bitnamilegacy-registry` (`e9d545dc`) was never merged and
is 2 commits behind `main`. Hostinger keeps running MinIO from the node's image cache, but Trivy must
pull the image to scan it, so `trivy-system/scan-vulnerabilityreport-5fb89fd85c` (container `minio`)
fails every hour with `GET https://quay.io/v2/minio/minio/manifests/RELEASE.2024-11-07T00-52-20Z:
UNAUTHORIZED`. That is the `KubeJobFailed on ubuntu-hostinger` email the operator receives, which fires
and then resolves as the failed Job is cleaned up.

### Codex brief — finish and land the port, safely for a cluster that already has data

**Repo:** `shopping-cart-infra`. **Branch:** `fix/minio-bitnamilegacy-registry`. Merge `origin/main`
into it; do not rebase or force-push.

**The existing branch is written for a fresh cluster. Fix this before it can land:** it changes
`runAsUser`/`fsGroup` from 1000 to 1001 and the data mount to `/bitnami/minio/data`. Hostinger has an
existing MinIO PVC (product images) written as UID 1000 on **local-path** storage, and local-path does
not apply `fsGroup` ownership changes. As written, MinIO could lose access to its own data.
Pick one and say which:
- **(preferred)** keep `runAsUser: 1000` / `fsGroup: 1000`. Bitnami images are built to run as an
  arbitrary non-root UID; confirm from the image's docs or entrypoint that `/opt/bitnami/minio` and the
  data dir work as 1000. If they don't, use the next option.
- an `initContainer` (pinned busybox, runs as root, only `chown -R 1001:1001` on the data mount, and
  only when the top-level owner is not already 1001), so the data carries over.

The mount path change is safe (same PVC, new path), but confirm Bitnami's data dir is exactly
`/bitnami/minio/data` and that existing buckets appear there unchanged.

**Tests / proof (paste output):**
- `kubectl kustomize` (or the repo's render target) of `data-layer/` renders cleanly;
- no `quay.io/minio` reference remains: `git grep -n 'quay.io/minio' -- data-layer` → nothing;
- the chosen ownership approach, with the evidence for it (image docs or entrypoint lines).

**Do not:** log in to quay.io or add a pull secret; touch `secret.yaml`, `service.yaml`,
`image-upload-configmap.yaml`; merge to `main` yourself. Open a PR and stop.

**Operator acceptance after merge (live, hostinger):** `minio-0` Running; the storefront still shows
product images; `kubectl -n trivy-system get vulnerabilityreports | grep minio` shows a report; no new
`KubeJobFailed` email for `scan-vulnerabilityreport-*` within 2 h.

## Verification of `shopping-cart-infra` `e8c0b8d9` (Claude, 2026-09-30) — changes requested

Verified independently. Branch tip `e8c0b8d9`; `origin/main` merged in `40fd1df` (merge commit, no
rebase or force-push). Scope: `data-layer/minio/{statefulset,bucket-init-job,image-upload-job}.yaml`,
`CHANGELOG.md`, the bug doc. The repo's CI gates at CI's pinned versions, run by Claude: yamllint clean;
kubeconform 1.34.0 `-strict` 6 valid / 0 invalid; every `kustomize build` overlay passes;
`git grep quay.io/minio -- data-layer` returns nothing. Bitnami `mc` path and `MC_CONFIG_DIR=/tmp/.mc`
are correct.

Codex chose the brief's second option (keep Bitnami's UID 1001, re-own the existing data with a root
`initContainer`). **Two changes are needed before merge:**

1. **The ownership fix can fail partway and then never retry.** The init container drops every
   capability except `CHOWN`. Without `DAC_READ_SEARCH`, root cannot enter a directory that denies
   "others", so `chown -R` stops there and exits 1: the pod shows `Init:Error`. On retry, the top-level
   directory is already 1001 (chown touched it first), so `stat -c '%u' … != 1001` skips the fix, and
   MinIO starts with part of its data still owned by 1000. Reproduced with `setpriv` and the same
   capability set (exit 1; a `0700` dir left owned by 1000). Fix, verified the same way (repairs the
   partial state; the second run is a no-op):
   ```yaml
   command: ["sh", "-c", "if [ -n \"$(find /bitnami/minio/data ! -user 1001 | head -n 1)\" ]; then chown -R 1001:1001 /bitnami/minio/data; fi"]
   capabilities: { drop: [ALL], add: [CHOWN, DAC_READ_SEARCH] }
   ```
2. **No recorded rationale.** The brief asked which ownership option was chosen and why UID 1000 was not
   kept, with evidence. The commit body is empty, and the branch's bug doc still describes the original
   fresh-cluster change with no mention of the init container. Add a short section: the decision, the
   evidence (Bitnami entrypoint or docs on arbitrary UIDs), and the ownership migration.

Then the operator's post-merge checks in the brief apply unchanged.

## Re-verification of `shopping-cart-infra` `36ea68e9` (Claude, 2026-09-30) — ready to merge

`36ea68e9` makes exactly the two requested changes, and nothing else (`statefulset.yaml`, the bug doc):
the init container checks the whole tree with `find /bitnami/minio/data ! -user 1001 | head -n 1`, and
adds `DAC_READ_SEARCH` beside `CHOWN` (still `drop: [ALL]`). The bug doc now records the decision and
evidence: Bitnami requires writability by UID 1001 at `/bitnami/minio/data`; local-path ignores `fsGroup`.

Proof, run by Claude: the **committed** script extracted from the manifest, run under **busybox 1.36.1**
(`sh`, `find`, `head`, `chown`; the image is `busybox:1.36`) as root with exactly `CHOWN` +
`DAC_READ_SEARCH`, on UID-1000 data containing a `0700` directory:
- fresh data → exit 0, 0 files not owned by 1001;
- the partial state that broke `e8c0b8d9` (top level already 1001) → exit 0, 0 remaining;
- already migrated → exit 0, no-op;
- control, the old `CHOWN`-only set → `Permission denied`, exit 1, 1 remaining.

CI gates at CI's pinned versions: yamllint clean; kubeconform 6 valid / 0 invalid; every kustomize
overlay builds; no `quay.io/minio` references. **Ready to merge.** After merge, run the operator checks
in the completion brief above.

**PR:** Codex pushed the branch but did not open a PR. Claude opened
https://github.com/wilddog64/shopping-cart-infra/pull/102 (head `36ea68e9`) on 2026-09-30 for the operator to review and merge.

**Merged 2026-09-30 02:25Z** as `shopping-cart-infra` `f909906` (#102, squash, admin bypass run by
Codex). Claude checked that `main`'s tree is identical to the verified head `36ea68e9`. Open items:
the operator confirms `enforce_admins` is back to `true`, then runs the four post-merge checks on hostinger.

**Live on hostinger (operator, 2026-09-30):** `minio-0` 1/1 Running, 0 restarts, image
`docker.io/bitnamilegacy/minio:2024.11.7-debian-12-r1`. The ownership migration completed: the
`product-images` bucket and its objects (`bag.jpg`, `cable.jpg`, `charger.jpg`, …) are present under
`/bitnami/minio/data`, and `find /bitnami/minio/data ! -user 1001` returns nothing. Remaining: a Trivy
`VulnerabilityReport` for minio, and 2 h without a `KubeJobFailed` email.

**Branch protection after the bypass (Codex report, 2026-09-30):** `enforce_admins: true`, required
approvals 1, dismiss stale reviews true, code-owner reviews false. **Confirmed by the operator** with
`gh api repos/wilddog64/shopping-cart-infra/branches/main/protection`: `enforce_admins: true`, approvals 1.

## Closed 2026-09-30 — fixed and verified live

Trivy now scans MinIO successfully on hostinger: `shopping-cart-data/statefulset-minio-minio`
(`bitnamilegacy/minio:2024.11.7-debian-12-r1`) and `statefulset-minio-fix-data-ownership`
(`busybox:1.36`, 0 findings), both created after the 02:25Z merge. The hourly failing scan Job, the
source of the `KubeJobFailed on ubuntu-hostinger` emails, is gone.

**Follow-up (security debt, not a regression):** the scan reports **12 CRITICAL / 80 HIGH** findings in
`bitnamilegacy/minio:2024.11.7-debian-12-r1`. That is the same MinIO release as before, in a sunset
repository that gets no patches; the findings were invisible only because the scan had been failing.
The durable fix is still the one in "Follow-up" above: move to a maintained MinIO build (or mirror a
patched one into `ghcr.io/wilddog64/`). Owner's call; file it as its own bug when scheduled.
