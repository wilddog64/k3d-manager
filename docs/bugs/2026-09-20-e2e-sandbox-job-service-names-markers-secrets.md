# Tier 2 sandbox Job cannot run: wrong Service names, missing result markers, missing Secrets

**Filed:** 2026-09-20
**Branch:** `k3d-manager-v1.36.0`
**Component:** `scripts/plugins/e2e.sh` — `_e2e_sandbox_job_manifest()`, `e2e_verify_sandbox()`
**Implementation under test:** `ffeb9ba2` (Tier 2 `e2e_verify_sandbox`)
**Severity:** blocks the first live Tier 2 run entirely

## Summary

Tier 2 (`e2e_verify_sandbox`) is code-complete and structurally tested, but has never executed
against a live ACG sandbox. Three defects in the sandbox Job path will fail the first run. None
is detectable by the existing structural BATS suite, which asserts manifest *shape* rather than
whether the values resolve.

All three exist **only** in the Tier 2 path. The Tier 1 (vCluster) path is correct in every case.
The sandbox Job manifest was written as a near-copy of the Tier 1 manifest and diverged precisely
where Tier 2's substrate differs: Tier 1 deploys its own fixtures from `scripts/etc/e2e/`, where
the Services really are named `basket`, `order`, `payment`; Tier 2 runs against the real
ArgoCD-deployed application charts, where they are not.

## Defect 1 — Job env points at Service names that do not exist

`_e2e_sandbox_job_manifest()` sets four service URLs:

| `e2e.sh` line | Current value | Actual Service | Verdict |
|---|---|---|---|
| 226 | `http://product-catalog.shopping-cart-apps.svc:8082` | `product-catalog` | correct |
| 227 | `http://basket.shopping-cart-apps.svc:8083` | `basket-service` | **wrong host** |
| 229 | `http://order.shopping-cart-apps.svc:8081` | `order-service` | **wrong host** |
| 231 | `http://payment.shopping-cart-payment.svc:8084` | `payment-service` | **wrong host** |

Evidence — `k8s/base/service.yaml` in each application repo:

- `shopping-cart-basket`: `name: basket-service`, `port: 8083`
- `shopping-cart-order`: `name: order-service`, `port: 8081`
- `shopping-cart-payment`: `name: payment-service`, `port: 8084`
- `shopping-cart-product-catalog`: `name: product-catalog`, `port: 8082`

**All four ports are already correct.** Only the hostnames are wrong.

The same file already contradicts itself: `_e2e_sandbox_render_overrides()` at `e2e.sh:149-150`
uses the correct names —

```yaml
  BASKET_URL: http://basket-service.shopping-cart-apps:8083
  PAYMENT_URL: http://payment-service.shopping-cart-payment:8084
```

— so the ConfigMap handed to `order-service` is right while the Job's own env is wrong. This is
the strongest evidence the divergence is a copy artifact, not an intentional alias.

**Effect:** DNS resolution failure for 3 of 4 services. Every Stripe checkout flow fails on
connection error, producing a red run that says nothing about Stripe.

## Defect 2 — no `__E2E_RESULTS_BEGIN__` / `__E2E_RESULTS_END__` wrapper

The summary parser at `e2e.sh:636` extracts Playwright results by regex:

```python
m = re.search(r"__E2E_RESULTS_BEGIN__(.*)__E2E_RESULTS_END__", raw, re.S)
```

Tier 1's Job emits those markers (`e2e.sh:522`):

```sh
npx playwright test --project=api --project=flows; rc=$?; echo "__E2E_RESULTS_BEGIN__"; cat test-results/results.json 2>/dev/null || true; echo "__E2E_RESULTS_END__"; exit $rc
```

The Tier 2 Job does not (`e2e.sh:220-223`):

```sh
npx playwright test --project=flows --no-deps tests/flows/stripe-checkout-orchestrator.spec.ts
```

**Effect:** the regex never matches, so `passed`, `total`, `failed` and `duration` stay `None`
in the summary and the result event. Pass/fail attribution for Tier 2 is dead — the only signal
is the Job's exit code, with no per-test detail and nothing usable in Grafana.

## Defect 3 — neither Secret the Job mounts is ever created

The sandbox Job requires two Secrets in `${E2E_NAMESPACE}` (default `shopping-cart-apps`):

- `ghcr-pull-secret` — `imagePullSecrets`, `e2e.sh:214`
- `stripe-e2e` — `STRIPE_SECRET_KEY` from `secretKeyRef`, `e2e.sh:241`

`e2e_verify_sandbox()` (`e2e.sh:266-338`) creates neither. Its only namespace/secret operations
are `helm ... --create-namespace` for `argocd` and the `vault-backend` ClusterSecretStore.

Tier 1 creates `ghcr-pull-secret` explicitly at `e2e.sh:467-475`, including patching the
`default` ServiceAccount. Tier 2 has no equivalent.

`stripe-e2e` is worse: a repo-wide search finds **exactly one** reference — the `secretKeyRef`
that consumes it. There is no creation path, no ExternalSecret, and no documentation of an
operator step that would provision it.

**Effect:** `ImagePullBackOff` on the private GHCR image, then `CreateContainerConfigError` on
the missing `stripe-e2e`. The Job never starts, so defects 1 and 2 are not even reached.

The `sk_test` value exists in Keychain as `k3dm-stripe-sk-test` (see
`reference_stripe_sk_keychain_backup`); the fix must read it via env or stdin, never argv.

## Why the existing tests did not catch this

The Tier 2 structural BATS cases assert that the rendered manifest contains the expected keys,
env var names and invariants (no hub registration, no teardown). They do not — and offline
cannot — verify that a hostname resolves, that a marker-dependent parser finds its markers, or
that a referenced Secret exists in the cluster. All six mutation pairs were honest; they were
simply aimed at shape.

## Fix design

1. **Service names** — in `_e2e_sandbox_job_manifest()`, change the three hostnames to
   `basket-service`, `order-service`, `payment-service`. Leave all four ports unchanged. Leave
   `product-catalog` unchanged.
2. **Result markers** — wrap the Tier 2 command in the same
   `rc=$?; echo BEGIN; cat test-results/results.json; echo END; exit $rc` idiom Tier 1 uses,
   preserving the Playwright exit code so the Job's own status stays truthful.
3. **Secrets** — add a sandbox preflight step, modelled on `e2e.sh:462-487`, that ensures
   `${E2E_NAMESPACE}` exists and creates both Secrets before the Job is applied:
   - `ghcr-pull-secret` as a `docker-registry` Secret, same inputs as the Tier 1 path;
   - `stripe-e2e` with key `sk_test`, value read from Keychain item `k3dm-stripe-sk-test` via
     env or stdin. **Never** pass the key as a command-line argument (CLAUDE.md secret hygiene);
     if a new sensitive flag is introduced, register it in `_args_have_sensitive_flag`.
   Both must be idempotent (`--dry-run=client -o yaml | kubectl apply -f -`), and must `_warn` +
   fail loudly if the Keychain item is absent rather than creating an empty Secret.

## Required test cases

1. Rendered sandbox Job env contains `basket-service.`, `order-service.` and `payment-service.`
   hostnames, and contains none of the bare `basket.`, `order.`, `payment.` forms.
2. Rendered sandbox Job env retains ports 8081/8082/8083/8084 against the correct hosts.
3. Rendered sandbox Job command contains both result markers and preserves the Playwright exit
   code (asserting on the captured command string, not a whole-line `grep -F`).
4. The parser, fed a captured Tier 2 log containing the markers, yields non-null
   `passed`/`total`/`failed`.
5. The sandbox preflight creates `ghcr-pull-secret` and `stripe-e2e` in `${E2E_NAMESPACE}`
   before the Job is applied — assert call order from a stub call log.
6. The preflight is idempotent: a second invocation against existing Secrets exits 0 and does
   not error.
7. A missing Keychain item causes a loud failure, not an empty `stripe-e2e` Secret.
8. The Stripe key never appears in any captured command argv.

Every new assertion needs a real=PASS / mutated=FAIL pair. A green run is not evidence.

## Definition of Done

- [ ] All three defects fixed in `scripts/plugins/e2e.sh`
- [ ] 8 test cases above added and each mutation-verified
- [ ] `shellcheck -S warning` clean on `scripts/plugins/e2e.sh`
- [ ] `make test` counts and exit status from a run watched to completion
      (~960 cases, **~15 minutes** — it is not hung)
- [ ] `CHANGELOG.md` entry under `[Unreleased]` → `### Fixed`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with the commit SHA
- [ ] Commit pushed to `origin/k3d-manager-v1.36.0`, verified by `git rev-parse HEAD origin/k3d-manager-v1.36.0`

## Out of scope

- Running Tier 2 live. Provisioning the sandbox (`acg_restart`) and executing
  `e2e_verify_sandbox` are the operator's actions.
- Any change to the Tier 1 vCluster path — it is correct as written.
- The HTTP/2 protocol label and failure-rate panel
  (`docs/issues/2026-09-16-http2-failure-rate-tier2-dependency.md`), which remain gated on a
  Tier 2 run that publishes bounded labels.

## Before You Start

1. `git pull origin k3d-manager-v1.36.0` — work on branch `k3d-manager-v1.36.0`, never `main`.
2. Read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
3. Read these in full before editing:
   - `scripts/plugins/e2e.sh` — lines 1-20 (env defaults), 140-160
     (`_e2e_sandbox_render_overrides`), 200-260 (`_e2e_sandbox_job_manifest`),
     266-338 (`e2e_verify_sandbox`), 455-530 (the Tier 1 path you are modelling on),
     620-660 (the summary parser).
   - `scripts/tests/plugins/e2e.bats` — the existing sandbox cases live here (34 tests; the
     sandbox ones are at lines 52-135). Add the new cases to this file, not a new suite.
4. Note the Tier 1 path at `e2e.sh:462-487` is the model for secret provisioning. Do not change
   Tier 1.

## Rules

- `set -euo pipefail` semantics already apply; double-quote every expansion.
- `shellcheck -S warning scripts/plugins/e2e.sh` must exit 0. Paste the output.
- Run the focused BATS suite and paste the real output (`ok`/`not ok` counts).
- Run `make test` and paste the counts plus exit status. **It takes ~15 minutes — it is not
  hung.** Capture to a file and count with
  `awk '/^ok /{o++} /^not ok /{n++} END{print o+0, n+0}'`. Do not pipe `make` through `tail`.
- Every new assertion needs a real=PASS / mutated=FAIL pair. Mutate in a scratch copy, record
  which test caught it, then restore. A green run alone is not evidence.
- No inline comments in shell blocks. Minimal patch — no unsolicited refactors.
- The Stripe key must never appear in argv. Use env or stdin. If you add a sensitive flag,
  register it in `_args_have_sensitive_flag` in `scripts/lib/system.sh`.

## What NOT to Do

- Do NOT create a PR.
- Do NOT merge anything.
- Do NOT commit to `main` — only `k3d-manager-v1.36.0`.
- Do NOT force-push.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT `git add -A` — stage only the files listed in this spec.
- Do NOT edit `scripts/lib/foundation/` or `scripts/lib/acg/` — they are subtrees, fixed upstream.
- Do NOT touch the Tier 1 vCluster path.
- Do NOT run anything against a live cluster or ACG sandbox. This task is code + BATS only.
- Do NOT modify files outside: `scripts/plugins/e2e.sh`, `scripts/tests/plugins/e2e.bats`,
  `CHANGELOG.md`, `memory-bank/activeContext.md`, `memory-bank/progress.md`.

## Commit message (exact)

```
fix(e2e): correct Tier 2 sandbox Service names, result markers and Secret provisioning

The Tier 2 sandbox Job manifest was written as a near-copy of the Tier 1 manifest and
diverged where the substrates differ. Tier 1 deploys its own fixtures where the Services
really are named basket/order/payment; Tier 2 runs against the ArgoCD-deployed charts where
they are basket-service/order-service/payment-service. Three defects followed:

- Job env pointed at three Service names that do not resolve (ports were already correct).
- The Job command omitted the __E2E_RESULTS_BEGIN__/__E2E_RESULTS_END__ wrapper the summary
  parser regexes for, so passed/total/failed were always None.
- Neither ghcr-pull-secret nor stripe-e2e was ever created, so the Job could not start.

Adds a sandbox preflight modelled on the Tier 1 path that ensures the namespace and both
Secrets idempotently, reading the Stripe test key from Keychain via stdin so it never
reaches argv, and failing loudly rather than creating an empty Secret.
```

## If you cannot commit

`.git` writes have been denied to you in this workspace three times
(`fatal: Unable to create '.git/index.lock': Operation not permitted`). If that happens
again: **do not fabricate a SHA and do not claim done.** Leave the changes in the working
tree, say plainly that the commit was blocked, and list exactly which files you modified.
Claude will commit on your behalf.
