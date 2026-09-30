# Bug: the Keycloak reconcile hook 404s on its own browser flow right after the partial import

**Branch:** `k3d-manager-v1.40.0` (tracking); **work repo:** `shopping-cart-infra`
**Filed:** 2026-09-30 by Claude (cloud session), from `KubeJobFailed` (hub, `identity`)
**Status:** FIX READY — Codex `b11f1a2` ([wilddog64/shopping-cart-infra#103](https://github.com/wilddog64/shopping-cart-infra/pull/103)), verified by Claude 2026-09-30. Awaiting merge and live check.
**Target files:** `identity/keycloak/keycloak-reconcile-hook-job.yaml` and `scripts/tests/bin/keycloak-reconcile.bats` (amended 2026-09-30 at plan review: the stub harness is kept as a test, not thrown away)
**Severity:** Medium. The flow itself and logins are fine; every `shopping-cart-identity` sync
fails its PostSync hook, and `KubeJobFailed` stays firing.
**Related:** `2026-09-15-keycloak-browser-flow-regression-blocks-all-sso.md` (added
`reconcile_browser_flow` in #98; its live verification is still outstanding),
`2026-09-25-keycloak-realm-reconcile-awk-missing-in-image.md` (#100),
`2026-09-23-argocd-identity-replace-true-cannot-update-bound-pvc.md` (#101). Those two kept the
hook from reaching this code, so **2026-09-30 is the first time `reconcile_browser_flow` ran live**.

## Evidence (2026-09-30)

- The hook log, identical on the 8 PM run and on a manual re-sync, where all of ArgoCD's 5 retries
  failed:
  ```
  Realm shopping-cart exists; applying partial import
  browser-with-conditional-otp flow already exists; reconciling it
  Resource not found for url: http://keycloak.identity.svc.cluster.local/admin/realms/shopping-cart/authentication/flows/browser-with-conditional-otp/executions
  ```
  There is no `partialImport exited` warning, so the import succeeded.
- The flow exists: `get authentication/flows -r shopping-cart` lists
  `"browser-with-conditional-otp",true,false` (top-level, not built-in).
- Minutes later the same `GET …/executions` succeeds 8/8, through both `localhost:8080` and the
  service.
- Keycloak runs one replica, so the cause is not load-balancing across replicas.
- The imported realm file (`identity/keycloak/realm-shopping-cart.json`) has no
  `authenticationFlows` and no `browserFlow`. The import overwrites roles, groups, clients and
  components (the LDAP connection).

## Root cause (working theory, to be confirmed by the fix's own logging)

The existence check lists flows (`GET authentication/flows`), which reads the database. The failing
call resolves the flow **by alias** through Keycloak's cached realm. `partialImport` with
`ifResourceExists=OVERWRITE` rewrites cached realm objects. For a window after it, alias lookup
misses a flow the list still returns. The window closes on its own, which is why manual calls later
succeed, and it reliably includes the hook's next call, which runs milliseconds later.

Moving the flow reconcile **before** the import is not an option: the flow's
`platform-mfa-role-condition` references a realm role that the import creates.

## Codex brief (shopping-cart-infra)

**Goal:** the PostSync hook succeeds after a partial import. The fix records whether the wait was
needed, which confirms or refutes the theory on the first live run.

**Runs where:** Codex web; branch `fix/keycloak-reconcile-wait-for-flow` from `origin/main`. Offline
checks only.

**Change (`identity/keycloak/keycloak-reconcile-hook-job.yaml`; tests in `scripts/tests/bin/keycloak-reconcile.bats`):**
1. Add `wait_for_flow_executions()`. It calls `kcadm.sh get "authentication/flows/${browser_flow}/executions" -r "${KC_REALM}"`,
   with output to `/dev/null`, every 2 s until it succeeds, for up to `KEYCLOAK_FLOW_READY_TIMEOUT_SECONDS`
   (default 60). On success it prints `browser flow readable after N attempt(s)`. On timeout it prints
   `ERROR: browser flow executions still 404 after <n>s` and returns 1.
2. Call it on **both** branches (the existing flow and the just-created flow), immediately before
   `reconcile_browser_flow`. A newly copied flow has the same exposure.
3. Keep everything else byte-identical: no re-indentation, no other logic changes. The hook's
   `set -euo pipefail` semantics must hold, so the helper must not be the last command of an
   `if` condition that hides its failure.

**Checks (paste output):**
- `yamllint` and `kubeconform -strict` on the file. In k3d-manager, `make validate-manifests
  FILES=<path>` installs kubeconform if it is missing.
- `kustomize build identity/keycloak` renders.
- Extract the embedded script (`yq` or a Python YAML load of the container `args`) and run
  `bash -n` plus `shellcheck -S warning` on it.
- A stub harness, **added as `@test` cases to the existing `scripts/tests/bin/keycloak-reconcile.bats`**
  (extract the script from `kubectl kustomize identity/keycloak`, as the existing test renders it): put a fake `kcadm.sh` on `PATH` (or override the path variable in a copy of the
  script) that 404s the first 3 executions GETs and then succeeds. The script prints
  `readable after 4 attempt(s)` and proceeds. A stub that always 404s exits non-zero within the
  timeout (use `KEYCLOAK_FLOW_READY_TIMEOUT_SECONDS=6`).
- Mutation: remove the call on the "already exists" branch → the harness run fails with the
  original 404.

**Do not change:** the partial import, `reconcile_browser_flow`'s logic, the ArgoCD hook annotations,
`backoffLimit`, and the image.

**Hand back:** one commit, `fix(identity): wait for the browser flow to be readable after the partial import`.
Open a PR to `main` per shopping-cart-infra's rules; do not merge.

## Live verification (operator, after merge)

1. ArgoCD syncs `shopping-cart-identity`; the PostSync hook completes and the failed Job is deleted
   (`BeforeHookCreation,HookSucceeded`), so `KubeJobFailed` resolves.
2. `kubectl --context k3d-k3d-cluster -n identity logs job/keycloak-realm-reconcile` shows
   `browser flow readable after N attempt(s)`. N > 1 confirms the cache theory; N = 1 means the
   window is narrower than one call, and the wait still makes the hook safe.
3. This also closes the outstanding live verification in `2026-09-15-keycloak-browser-flow-regression-blocks-all-sso.md`.

## Verification (Claude, 2026-09-30)

`b11f1a2` is based on current `main` and touches only the two allowed files, with additions only.
- **Wait placement:** on both branches; the Job still runs `bash -euo pipefail -c`, so a timed-out
  wait stops the hook rather than reconciling blind. `activeDeadlineSeconds: 900` and the service
  wait are unchanged.
- **Tests:** the `keycloak-reconcile.bats` suite passes 3/3 against the script rendered through
  kustomize (404 ×3 then ok → "readable after 4 attempt(s)"; always 404 → the error within the
  6 s timeout). The mutation that removes the wait from the existing-flow branch fails all 3.
- **Gates:** the rendered script passes `bash -n` and `shellcheck -S warning`; `kustomize build`
  renders; kubeconform is valid; yamllint is clean under CI's config (the default config's 83
  line-length/indent errors also exist on `main`, and CI relaxes those rules).
- Nit, not blocking: the timeout message says "404" for any kcadm failure.
