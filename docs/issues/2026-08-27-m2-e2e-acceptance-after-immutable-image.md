# M2 E2E acceptance after immutable image build

## What was attempted

Ran the remote E2E flow on `m2-air.local` with:

```text
E2E_IMAGE_TAG=sha-0c2505bbdc09b4ad12e5ea251ce9a8eeb7975e00
E2E_M2_SSH_HOST=m2-air.local
E2E_M2_PUBLISH_BACK_HOST=cliang@m4-air.local
E2E_M2_PUBLISH_BACK_KEY=~/.ssh/e2e-m4-publisher
make e2e-remote RUNNER=m2
```

The job created the vCluster and launched:

```text
INFO: [e2e] Launching Playwright Job e2e-run-1787838531-2562 (image ghcr.io/wilddog64/shopping-cart-e2e-tests:sha-0c2505bbdc09b4ad12e5ea251ce9a8eeb7975e00)
job.batch/e2e-run-1787838531-2562 created
```

The result artifact reported:

```text
"exit_code": 1,
"failed": 31,
"passed": 26,
"skipped": 45,
"project": "api+flows",
"result": "fail",
"runner": "m2",
"total": 102
```

## Findings

- Product-catalog API tests passed.
- Basket tests passed until response-shape assertions in update/remove flows.
- Order and payment suites still fail broadly; the log includes `orders is not iterable` and
  undefined/non-numeric response values.
- Stripe flow tests are skipped as designed without the Stripe/OAuth environment.
- M4 publication was unavailable for this run, so the result remained a
  `publication_pending` artifact; the full JSON and log remain on M2 under
  `~/.k3dm/e2e/1787838531-2562.{json,log}`.

## Follow-up

Inspect the deployed basket/order/payment API envelopes and ensure the E2E image's client mappings
match the release images. Confirm payment is included in the vCluster substrate before treating the
M2 migration as accepted. Do not classify this run as an M2 capacity or image-tag failure.
