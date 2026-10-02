# Bug: the `rabbitmq` Service's link env var crash-loops product-catalog in the e2e substrate

**Status:** FIXED (c7fa36e4)
**Branch:** `k3d-manager-v1.40.0`
**Files:** `scripts/etc/e2e/{postgres,redis,rabbitmq,product-catalog,basket,order,keycloak,payment,seed-job}.yaml`
**Tests:** `scripts/tests/plugins/e2e.bats`
**Introduced by:** `034d9513 feat(e2e): add a RabbitMQ broker to the Tier 1 substrate` (2026-10-02)

## Symptom

Each `make e2e` run since `034d9513` has failed in `deploying-substrate`. Runs `1790959569-5392` and
`1790961003-14944` both failed with
`rollout status deployment/product-catalog --timeout=300s failed`. The new substrate diagnostics
(`~/.k3dm/e2e/1790961003-14944.substrate.txt`) show product-catalog in `CrashLoopBackOff` with:

```
pydantic_core._pydantic_core.ValidationError: 1 validation error for Settings
RABBITMQ_PORT
  Input should be a valid integer, unable to parse string as an integer [type=int_parsing, input_value='tcp://10.43.196.6:5672', input_type=str]
```

## Root cause

Kubernetes injects Docker-link-style environment variables into every pod by default, one set
per Service in the namespace: `<SVC>_PORT=tcp://<ip>:<port>`, `<SVC>_SERVICE_HOST`, and so on.
Adding a Service named `rabbitmq` therefore put `RABBITMQ_PORT=tcp://…` into every pod.
product-catalog's pydantic `Settings` reads `RABBITMQ_PORT` as an `int`, and its manifest does
not set that variable, so the injected string wins and the app fails at import.

payment avoids this only because it sets `RABBITMQ_PORT: "5672"` explicitly. The `postgres`,
`redis` and `keycloak` Services inject the same kind of variables, so the next app setting that
happens to share one of their names would break the same way. The seed job's
`DeadlineExceeded` is a knock-on effect: it waits for product-catalog.

## Fix

Turn off service-link injection in **every** substrate pod spec. Nothing in the substrate depends
on it: each service is reached by its DNS name through explicit env.

In each of the 9 files, insert `enableServiceLinks: false` as the first key of the pod spec,
which is the `    spec:` line nested under `template:`. Do not touch the Deployment- or Job-level
`spec:` at column 0. All nine files share the same layout:

Old:
```yaml
    spec:
      containers:
```
(or `      initContainers:` in order.yaml, payment.yaml and seed-job.yaml)

New:
```yaml
    spec:
      enableServiceLinks: false
      containers:
```
(or `      initContainers:`, respectively)

## Test (append to `scripts/tests/plugins/e2e.bats`, next to the other substrate tests)

```bash
@test "every substrate pod spec disables service links" {
  command -v kubectl >/dev/null 2>&1 || skip "kubectl not installed"
  run env kubectl kustomize "${BATS_TEST_DIRNAME}/../../etc/e2e"
  [ "$status" -eq 0 ]
  local workloads links
  workloads="$(grep -cE '^kind: (Deployment|Job)$' <<<"$output" || true)"
  links="$(grep -cE '^      enableServiceLinks: false$' <<<"$output" || true)"
  [ "$workloads" -eq 9 ]
  [ "$links" -eq "$workloads" ]
}
```

**Mutation check (must report):** remove the line from `product-catalog.yaml` only. The test
must go red (8 ≠ 9). Restore it, and the test is green.

## Rules

- `bats scripts/tests/plugins/e2e.bats`: all green; paste the summary line.
- `kubectl kustomize scripts/etc/e2e >/dev/null`: exits 0.
- YAML only. Do not change env vars, image tags or probes.

## Definition of Done

- [ ] `enableServiceLinks: false` in all 9 pod specs
- [ ] Test added and green; mutation result reported
- [ ] Status line set to `FIXED (<short sha>)`
- [ ] Commit message: `fix(e2e): disable service-link env injection in the substrate pods`
- [ ] Pushed to `origin/k3d-manager-v1.40.0`; report `git rev-parse origin/k3d-manager-v1.40.0`

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files other than the 9 manifests, `e2e.bats`, and this doc
- Do NOT work around the bug by adding `RABBITMQ_PORT` to product-catalog. That fixes one name
  and leaves the trap in place.
- Do NOT commit to `main`
