# Bug: quay.io/minio is no longer anonymously pullable — repoint the data layer

**Filed:** 2026-09-25
**Work repo:** `shopping-cart-infra` (NOT k3d-manager)
**Branch (work repo):** `fix/minio-bitnamilegacy-registry` — create from `origin/main`
**Severity:** blocks `make up CLUSTER_PROVIDER=k3s-aws` at Step 10b on every fresh cluster

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
