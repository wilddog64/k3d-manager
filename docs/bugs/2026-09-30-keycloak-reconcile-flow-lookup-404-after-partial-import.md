# Bug: the Keycloak reconcile hook's sub-flow updates omit `flowId`, so Keycloak rejects them with 404

**Branch:** `k3d-manager-v1.40.0` (tracking); **work repo:** `shopping-cart-infra`
**Filed:** 2026-09-30 by Claude (cloud session), from `KubeJobFailed` (hub, `identity`)
**Status:** OPEN — #104 (`930a82d`) fixed the sub-flow `flowId` 404 (confirmed live); the hook now fails at the next write. Brief 3 below. #103 and #104 stay.
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

## Correction (2026-09-30, live): the cause is a missing `flowId`, not import timing

After #103 merged, a manual sync ran the new hook at `98da0c5`. It logged
`browser flow readable after 1 attempt(s)` and then failed with the same 404. The flow was readable
immediately, so **the cache/timing theory is refuted**. The wait stays as a harmless guard.

No log line appears between the wait and the error, so every check passed and the hook reached its
first write. That write is `kcadm.sh update "authentication/flows/${browser_flow}/executions" -b '{"id":…,"requirement":"ALTERNATIVE","authenticationFlow":true,"displayName":…}'`.
Live tests in the Keycloak pod, all setting values the flow already has:

| Body sent to `PUT …/flows/browser-with-conditional-otp/executions` | Result |
|---|---|
| hook's body: `id`, `requirement`, `authenticationFlow: true`, `displayName` (merge) | **404** |
| same, `--no-merge` | **404** |
| same plus `"flowId":"1b41e828-…"` | **OK** |
| `id` and `requirement` only | **OK** |

The ID was correct (`837de7dc-…`, identical to its CSV row). For an execution flagged
`authenticationFlow: true`, Keycloak's update handler also resolves the sub-flow from the body's
`flowId`. When it is absent, the handler throws `NotFoundException("Illegal execution")` and marks the
transaction rollback-only. kcadm prints that as "Resource not found for url". The hook already computes
`forms_flow_id` (CSV column 5) and `conditional_otp_flow_id` (forms CSV column 6) and never sends them.

This code arrived in #98 (2026-09-15) and never ran live until 2026-09-30: `awk` (#100) and the PVC
sync block (#101) stopped the hook earlier. The live flow is already in the target state: forms
`ALTERNATIVE`, Username Password `REQUIRED`, Conditional OTP `CONDITIONAL`, role condition and OTP
Form `REQUIRED`. So logins work, and the hook fails on no-op writes.

## Codex brief 2 (shopping-cart-infra)

**Goal:** the PostSync hook completes. Both sub-flow updates send the `flowId` Keycloak requires.

**Branch:** `fix/keycloak-reconcile-subflow-flowid` from `origin/main`.
**Files:** `identity/keycloak/keycloak-reconcile-hook-job.yaml` and
`scripts/tests/bin/keycloak-reconcile.bats`. Nothing else.

**Change:**
1. In the forms-subflow update (`kcadm.sh update "authentication/flows/${browser_flow}/executions"`),
   add `\"flowId\":\"${forms_flow_id}\"` to the `-b` JSON.
2. In the conditional-OTP update (`kcadm.sh update "authentication/flows/${forms_flow_alias}/executions"`),
   add `\"flowId\":\"${conditional_otp_flow_id}\"`.
3. No other edits: no re-indentation, and keep the #103 wait. Both IDs are already validated
   non-empty before use.

**Tests (BATS, against the script rendered by `kubectl kustomize`, like the existing cases):**
1. **Static:** every `kcadm.sh update "authentication/flows/…/executions"` whose `-b` body contains
   `authenticationFlow` also contains `flowId`.
2. **Behavioural, with realistic fixtures.** Extract the CSV helpers, `level0_rows`, `urlencode_path` and
   `reconcile_browser_flow` (add `# BEGIN/# END` markers like #103 did). Run them against a stub
   `kcadm.sh` that:
   - returns, for `get …/flows/browser-with-conditional-otp/executions`, the live CSV below, captured on
     2026-09-30 (fields `id,displayName,requirement,authenticationFlow,flowId,level`);
   - returns matching CSVs for the forms and conditional-OTP sub-flow GETs;
   - logs every `update` body, and **exits 1 with `Resource not found for url`** for an
     `update …/executions` whose body has `"authenticationFlow":true` but no `"flowId"`, exactly as
     Keycloak does.

   The function returns 0, and the logged bodies carry `flowId` values `1b41e828-6706-41b9-8a3a-50b2013e7e1d`
   (forms) and `f01f2d25-00eb-4840-94d4-92a24cb78d68` (conditional OTP).
3. **Mutation:** drop `flowId` from either update → test 2 fails with the 404 message; test 1 fails too.

**Gates:** bats (all cases), `bash -n` + `shellcheck -S warning` on the rendered script, yamllint (CI
config), kubeconform, `kustomize build identity/keycloak`.

**Hand back:** one commit, `fix(identity): send flowId on sub-flow execution updates so Keycloak accepts them`,
and a PR to `main`; do not merge.

**Live verification (operator):** after the merge, trigger one sync; ArgoCD will not re-run a hook-only change on its own:
`kubectl --context k3d-k3d-cluster -n cicd patch application shopping-cart-identity --type merge -p '{"operation":{"initiatedBy":{"username":"operator"},"sync":{}}}'`.
Expect: the phase `Succeeded`, no `keycloak-realm-reconcile` Job left, and `KubeJobFailed` resolved.
This also closes the live check in `2026-09-15-keycloak-browser-flow-regression-blocks-all-sso.md`.

**Process gap noted:** hook-only changes never auto-sync. The Application stays `Synced`, because
ArgoCD excludes hooks from the diff, so each hook fix needs one manual sync to take effect.

### Fixture: live CSV, 2026-09-30 (`--fields id,displayName,requirement,authenticationFlow,flowId,level --format csv`)

```
"72f9df5f-9326-41de-9c75-dfc9f64161e9","Cookie","ALTERNATIVE",,,0
"b7a5af7e-2b1d-4e9c-9210-5a964d0f6ee4","Kerberos","DISABLED",,,0
"4132b009-6492-4bf2-8fc9-c23d5c326419","Identity Provider Redirector","ALTERNATIVE",,,0
"837de7dc-c162-4e6e-875a-206856e6a152","browser-with-conditional-otp forms","ALTERNATIVE",true,"1b41e828-6706-41b9-8a3a-50b2013e7e1d",0
"47df1e22-2f22-478f-bddc-32a9871a346f","Username Password Form","REQUIRED",,,1
"f3e14e86-26d4-4a7f-9bbb-0a6ab26514e4","browser-with-conditional-otp Browser - Conditional OTP","CONDITIONAL",true,"f01f2d25-00eb-4840-94d4-92a24cb78d68",1
"c93c67dd-14ae-4d7c-afde-4da9082a4300","Condition - user configured","REQUIRED",,,2
"ac0bb8fe-bc30-4f32-8b95-423f33a9e44a","OTP Form","REQUIRED",,,2
"2ed55ec6-0fe7-4298-a396-a07f8ad33993","Condition - user role","REQUIRED",,,2
```

The sub-flow GETs use other `--fields` lists (`id,displayName,providerId,requirement,authenticationFlow,flowId`
for the forms flow; `id,providerId` and `id,providerId,authenticationConfig` for conditional OTP). Build their
stub outputs from the same rows in those column orders, with provider IDs `auth-username-password-form`,
`conditional-user-configured`, `auth-otp-form` and `conditional-user-role`.

## Verification of brief 2 (Claude, 2026-09-30)

`4057069` is based on current `main` and touches only the two allowed files. The hook change is the two
`flowId` additions plus `# BEGIN/# END` markers.
- **Rendered bodies:** both `-b` bodies are split across two lines with a backslash inside double
  quotes. Evaluated in bash, both are valid JSON with `flowId` (checked by parsing them). The
  continuation leaves indentation whitespace inside the JSON, which is legal.
- **Strict mode:** the Job still runs `bash -euo pipefail -c`, and the probe runs under the same mode.
- **Tests:** BATS 5/5. The behavioural test runs the real `reconcile_browser_flow` and every helper
  against the captured CSV, takes the config-update branch as production does, and fails on any
  unhandled call. Dropping either `flowId` fails both the static and the behavioural test; restored,
  5/5 again.
- **Gates:** `bash -n` and shellcheck clean; yamllint (CI config) and kubeconform clean. PR CI:
  YAML Lint, Kubeconform, Kustomize Build and GitGuardian pass; the Copilot review was still running.

## Third failure (2026-09-30, live, after #104 as `930a82d`)

A sync at `930a82d` passed the forms sub-flow update (so `flowId` fixed that call), then failed on:
```
Resource not found for url: …/admin/realms/shopping-cart/authentication/executions/47df1e22-2f22-478f-bddc-32a9871a346f
```
That is `kcadm.sh update "authentication/executions/${username_password_id}" -s requirement=REQUIRED`.
Live tests in the Keycloak pod, all setting values the flow already has:

| Call | Result |
|---|---|
| `update authentication/executions/{id} -s requirement=REQUIRED` (the hook's form) | **404** |
| `get authentication/executions/{id}` | OK |
| `update "authentication/flows/browser-with-conditional-otp%20forms/executions" -b '{"id":…,"requirement":"REQUIRED"}'` | **OK** |

Keycloak 24 serves `GET /authentication/executions/{id}` but has no update on that path. An
execution's requirement is changed through its **parent flow's** `…/flows/{alias}/executions` PUT. The
hook uses the unsupported form three times. The #104 stub accepted every `update`, so the tests could
not catch it; brief 3 makes the stub model Keycloak 24 here.

## Codex brief 3 (shopping-cart-infra)

**Branch:** `fix/keycloak-reconcile-requirement-via-parent-flow` from `origin/main` (now at `930a82d`).
**Files:** `identity/keycloak/keycloak-reconcile-hook-job.yaml` and `scripts/tests/bin/keycloak-reconcile.bats`.

**Change:** replace each `kcadm.sh update "authentication/executions/${X}" -r "${KC_REALM}" -s requirement=R`
with `kcadm.sh update "authentication/flows/${PARENT}/executions" -r "${KC_REALM}" -b "{\"id\":\"${X}\",\"requirement\":\"R\"}"`:

| `X` | `R` | `PARENT` (already defined and URL-encoded at that point) |
|---|---|---|
| `username_password_id` | `REQUIRED` | `forms_flow_alias` |
| `role_condition_id` | `REQUIRED` | `conditional_otp_flow_alias` |
| `otp_form_id` | `REQUIRED` | `conditional_otp_flow_alias` |

Keep the body on one line (no backslash-newline continuation inside the JSON string). Change nothing
else, and keep #103 and #104's changes.

**Tests (extend the #104 harness):**
1. **Static:** the rendered script contains no `kcadm.sh update "authentication/executions/`
   (`delete` and `create …/config` on that path stay; they are supported).
2. **Stub fidelity:** the stub `kcadm.sh` exits 1 with `Resource not found for url` for any
   `update authentication/executions/…`, as Keycloak 24 does. It keeps the #104 rule for sub-flow
   updates without `flowId`, and it logs every `update` call's path and body.
3. **Behavioural:** `reconcile_browser_flow` returns 0 against the captured CSV. The logged updates
   include the three parent-flow calls with the right `PARENT` (URL-encoded, containing `%20`) and IDs
   `47df1e22-2f22-478f-bddc-32a9871a346f`, `2ed55ec6-0fe7-4298-a396-a07f8ad33993` and
   `ac0bb8fe-bc30-4f32-8b95-423f33a9e44a`.
4. **Mutation:** revert any one of the three calls to the old form → tests 1 and 3 fail. Also, the
   #104 test run against the new stub, with the old code, fails at the Username Password update (the
   exact live failure).

**Gates:** BATS all green, `bash -n` + shellcheck on the rendered script, yamllint (CI config),
kubeconform, `kustomize build`. **Hand back:** one commit,
`fix(identity): set execution requirements through the parent flow, which Keycloak 24 supports`, and a PR; do not merge.

**After merge (operator):** a hard refresh, then one sync; the hook change alone does not trigger a sync:
```
kubectl --context k3d-k3d-cluster -n cicd annotate application shopping-cart-identity argocd.argoproj.io/refresh=hard --overwrite
kubectl --context k3d-k3d-cluster -n cicd patch application shopping-cart-identity --type merge -p '{"operation":{"initiatedBy":{"username":"operator"},"sync":{}}}'
```
Then confirm the synced revision (`.status.operationState.syncResult.revisions`) is the merge commit,
the phase is `Succeeded`, and no `keycloak-realm-reconcile` Job is left.

**Lesson recorded:** a stub that accepts every write only tests the caller's arithmetic. Model each
endpoint the code writes to as the real server behaves, including what it rejects.
