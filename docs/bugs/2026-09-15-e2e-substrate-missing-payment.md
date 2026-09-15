# Bug: e2e runs payment tests, but the Tier 1 substrate never deploys payment

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-15
**Status:** OPEN
**Files:** `scripts/etc/e2e/payment.yaml` (new), `scripts/etc/e2e/kustomization.yaml`, `scripts/etc/e2e/postgres.yaml` (initdb), `scripts/plugins/e2e.sh`, `scripts/tests/plugins/e2e.bats`, `CHANGELOG.md`
**Depends on:** `docs/bugs/2026-09-15-e2e-m2-runner-checkout-drift.md`, so the runner actually executes this substrate

## Evidence (run `1789481773-13798`, 2026-09-15)

- `scripts/etc/e2e/kustomization.yaml` deploys postgres, redis, product-catalog, basket, and order only.
- The Playwright Job (`_e2e_job_manifest`) runs `--project=api --project=flows`. That includes `tests/api/payments.spec.ts` and `tests/flows/payment-flow.spec.ts` from `shopping-cart-e2e-tests`.
- The Job sets no `PAYMENT_URL`, so the tests default to `http://localhost:8084` and fail with `connect ECONNREFUSED ::1:8084` (9 failures in `api/payments.spec.ts`).

## Decision (operator, 2026-09-15)

**Deploy payment** into the substrate, so payment is really tested. Do not skip the payment tests.

## Fix

1. **Read the contract first:**
   - `shopping-cart-payment` origin/main: `k8s/base/deployment.yaml`, `k8s/base/configmap.yaml`, `Dockerfile`, and `src/main/resources/application*.yml`.
   - Required env, DB name, and whether RabbitMQ is required at startup (e.g. health or a listener that fails without a broker).
2. **`scripts/etc/e2e/payment.yaml`** — Deployment + Service `payment`, port `8084`, following `order.yaml`'s shape:
   - labels;
   - `wait-for-postgres` initContainer;
   - readiness probe on the service's health path.

   Env:
   - `SERVER_PORT=8084`, DB on the in-substrate `postgres`, DB name `payments`, user `postgres`, password from `e2e-datastore-credentials/postgres-password`, `DB_SSLMODE=disable`;
   - Vault and OAuth2 disabled using the payment service's own variable names;
   - mock gateway enabled (`PAYMENT_GATEWAY_DEFAULT` = the mock value, `MOCK_GATEWAY_ENABLED=true`);
   - `STRIPE_ENABLED=false`, `PAYPAL_ENABLED=false`;
   - `ENCRYPTION_KEY` from `e2e-datastore-credentials/payment-encryption-key`.
3. **RabbitMQ** — only if step 1 shows payment needs a broker to start: add `rabbitmq.yaml` with a pinned `rabbitmq:<x.y.z>-alpine` tag, credentials from `e2e-datastore-credentials`, and payment's `RABBITMQ_*` env pointing at it. If not needed, set whatever disables it and note that in the commit body.
4. **`postgres.yaml` initdb** — also create database `payments`.
5. **`kustomization.yaml`** — add `payment.yaml` (and `rabbitmq.yaml` if added) to `resources`. Add an `images:` entry `shopping-cart-payment` → `ghcr.io/wilddog64/shopping-cart-payment`, `newTag` = the tag in the payment repo's latest `ci: update shopping-cart-payment to sha-…` commit on origin/main (currently `sha-ecdb421f25849fb88a20a7a8d71d5a215ecf8326`).
6. **`e2e.sh`:**
   - `_e2e_provision_datastore_secret` adds `payment-encryption-key` (random, generated like the existing password, never logged) and RabbitMQ creds if step 3 applies;
   - the rollout wait list includes `payment` (and `rabbitmq`);
   - `_e2e_job_manifest` adds `PAYMENT_URL=http://payment.${E2E_NAMESPACE}.svc:8084`.

## Tests (`e2e.bats`)

- The job manifest contains `PAYMENT_URL` with `payment.` and `:8084`.
- The kustomization resources include `payment.yaml`; the images include `shopping-cart-payment` with a `sha-` tag.
- `_e2e_substrate_images` lists the payment image.
- The datastore secret includes `payment-encryption-key`, and the generated value is never echoed.
- The rollout wait covers payment.
- `kubectl kustomize scripts/etc/e2e` renders (offline) and contains `name: payment`.
- `shellcheck -S warning` stays clean.

## Acceptance (operator or Claude, live, one agent on the M2)

`make e2e-remote RUNNER=m2` shows no `ECONNREFUSED …:8084` failures.

## What NOT to do

- Do not skip or delete payment tests in `shopping-cart-e2e-tests`.
- Do not enable Stripe or PayPal, and do not reference any real key.
- Do not use a floating image tag.
- Do not run a live dispatch from the implementation agent.
- Do not edit `scripts/lib/foundation/` or `scripts/lib/acg/`.
- No PR, no merge, no `main` commit, no force-push, no `--no-verify`. No `git add -A`, no `git stash`.
