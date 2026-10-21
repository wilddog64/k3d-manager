# Bug: Hermes does not expose MinIO image-upload hook status

**Filed:** 2026-10-21 (Codex, after the operator could not locate the MinIO KubeJobFailed resolution notification)
**Status:** OPEN — observability gap confirmed by code review and live Hermes screenshot
**Priority:** P3 — MinIO may be healthy, but operators cannot determine whether the product-image PostSync upload succeeded from the current health view
**Severity:** low
**Type:** Observability bug (no known current MinIO service failure)
**Approval:** pending — implementation/dispatch not yet authorized
**Branch:** `k3d-manager-v1.43.5`
**Release:** TBD — assign during triage
**Component:** `scripts/lib/webhook/smoke.py` data-layer check; `scripts/lib/hermes/sensors.py` Hermes findings; related tests and dashboard presentation

## Symptom

The webhook's `Data layer` check reports only the readiness of four StatefulSets, including MinIO.
Hermes exposes that aggregate as `data_layer` (for example, `4/4 ready`) and separately reports
whether failed Jobs are superseded. Neither view identifies the `minio-image-upload` PostSync hook's
last outcome. After the uploader fix deployed, the operator could confirm the Argo CD revision and
general data-layer health, but could not find the specific historical `KubeJobFailed` resolution
notification. A notification for `ubuntu-k3s/trivy-system` was unrelated and could not establish MinIO
status.

The MinIO uploader fix itself is deployed and verified in
`docs/bugs/2026-10-18-minio-image-upload-hook-installs-pillow-at-runtime.md`; this record tracks only
the missing operational visibility.

## Expected behavior

Hermes should expose a distinct MinIO image-upload finding, separate from StatefulSet readiness, that
states the last known hook outcome and when it occurred. It should distinguish a successful upload,
a failed upload (with a bounded, sanitized reason), and unavailable/unknown evidence. A failed hook
must produce a corresponding alert that can be observed resolving after a later successful run.

The implementation may use a durable status source appropriate to the existing hook lifecycle; it
must not assume a successful Job remains queryable because `HookSucceeded` cleanup deletes it.

## Acceptance

```yaml
must:
  - id: M1
    text: Hermes presents MinIO image-upload status separately from the aggregate data-layer StatefulSet readiness result.
  - id: M2
    text: The status identifies the latest known success or failure and its timestamp; failure detail is bounded and contains no credentials or secret values.
  - id: M3
    text: If no run or a reliable status source is unavailable, Hermes reports unknown rather than inferring success from MinIO pod readiness.
  - id: M4
    text: A failed upload is alertable, and a subsequent successful upload clears the alert condition.
must_not:
  - id: N1
    text: MinIO StatefulSet readiness alone must not be reported as image-upload success.
  - id: N2
    text: The solution must not require retaining successful hook Jobs contrary to the existing HookSucceeded cleanup policy unless that lifecycle change is separately justified and approved.
  - id: N3
    text: Status output must not expose MinIO credentials, signed URLs, or unbounded pod/job logs.
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N3]
    kind: offline
    text: focused tests cover success, failure, unknown/no-run, timestamp, and sanitized bounded evidence; a ready MinIO StatefulSet with no upload result must not pass the upload sensor.
  - id: E2
    proves: [M1, M2, M3, M4]
    kind: live
    text: Hermes shows the actual MinIO upload result and timestamp after a data-layer sync; a controlled or naturally occurring failed run is visible as failed, and a later successful run returns the finding/alert to healthy/resolved.
interface:
  - webhook service health payload
  - Hermes findings/status dashboard
  - Alertmanager rule and notification state
```

## Investigation evidence

- `scripts/lib/webhook/smoke.py` currently sets the `Data layer` result from readiness of `postgresql-orders`, `postgresql-payment`, `postgresql-products`, and `minio` StatefulSets.
- `scripts/lib/hermes/sensors.py:data_layer` consumes that aggregate check; it does not inspect the image-upload hook result.
- The uploader Job has `HookSucceeded` cleanup, so a successful Job may no longer exist when an operator checks after sync.
- The operator supplied screenshots showing Argo CD Synced/Healthy and Hermes `data_layer 4/4 ready`; these establish general data-layer health, not the upload result itself.

## Scope notes

- Keep this distinct from the fixed runtime-Pillow/network-dependency bug.
- Do not alter MinIO bucket contents, uploader behavior, or hook deletion policy as part of an observability-only fix without renewed approval.
- Before dispatch, choose the durable status source and alert semantics; no implementation has been authorized yet.
