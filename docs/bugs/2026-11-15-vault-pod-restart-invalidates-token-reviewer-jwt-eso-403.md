# Bug: any vault-0 pod restart breaks every hub ESO store (stale pod-bound `token_reviewer_jwt`, 403 on login)

**Status:** OPEN — captured 2026-11-15
**Priority:** P2 (proposed: all hub ExternalSecrets stop refreshing and new pods that need them cannot start; manual workaround exists)
**Introduced by:** pre-existing (auth config written with a pod-bound reviewer token by `_hub_data_repoint_vault`, `scripts/plugins/hub_data.sh:847`, and `vault.sh:2106`, `:2305`)
**Should have been caught by:** deploy step
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-15 (hub repaired 16:37Z; intent approved; Argon + Fable spec review running, then dispatch to Flash `gemini-3.8-flash-high`)
**Intent approved:** operator, 2026-11-15 ("approved"; revised E2, E4, E5 re-approved "ok")
**Spec review:** risk medium (hub Vault auth) — Argon + Fable blind, 2026-11-15: both CHANGES, same main finding (test_vault token sites); all confirmed findings applied; Argon's here-string xtrace claim refuted by test (see Fix)
**Prior art:** `docs/issues/2026-09-11-status-warnings-hub-vault-eso-breakage.md` and `docs/bugs/2026-10-25-deploy-vault-rejected-unseal-cache-triggers-destructive-reinit.md:163` (grep `token_reviewer`) — appended as the third recurrence; the 2026-10-25 doc says "file it separately if it recurs"

## What happened (Claude, 2026-11-15, M5 hub `k3d-k3d-cluster`)

Claude deleted `secrets/vault-0` at 15:24:45Z to live-check the unseal watchdog (see
`2026-11-15-vault-unseal-watchdog-secret-shard-rejected-errors-suppressed.md`). After the operator unsealed Vault at
about 15:37Z, ESO still failed: `ClusterSecretStore vault-backend` and `identity/vault-kv-store` are
`InvalidProviderConfig: unable to create client`; the ESO controller logs
`PUT http://vault.secrets.svc:8200/v1/auth/kubernetes/login Code: 403 permission denied`. Hermes went degraded at
15:47Z (8/9, then 9/9 not synced by 16:15Z: argocd-oidc-secret, k3dm-smoke-user, keycloak-client-secrets, ...),
ArgoCD apps hub-platform-ops, hub-vectordb, shopping-cart-apps and shopping-cart-identity Degraded, and vectordb-0
cannot start without `vectordb-postgres`. Slack incident card 15:54Z.

## Cause

The Kubernetes auth config holds a `token_reviewer_jwt` read from the vault-0 pod's projected ServiceAccount token.
That token is bound to the pod object; deleting the pod invalidates it, so Vault's TokenReview call fails and every
login is denied. Vault's server log shows only the unrelated audience warning.

## Workaround

Rewrite the auth config from the new pod's token (root token via stdin, never in the exec string), as
`_hub_data_repoint_vault` does.

## External behaviour proof (Claude, 2026-11-15, upstream source at the deployed tag)

The hub runs `hashicorp/vault:1.20.1` (`kubectl -n secrets get pod vault-0`, M5, 2026-11-15). Vault v1.20.1 `go.mod`
bundles `github.com/hashicorp/vault-plugin-auth-kubernetes v0.22.2`. In that plugin at tag `v0.22.2`:

- `backend.go:347-359` (`loadConfig`): when `disable_local_ca_jwt` is false and no `token_reviewer_jwt` is stored, the
  plugin reads the local ServiceAccount token file (`localSATokenReader.ReadFile()`), cached with
  `jwtReloadPeriod = 1 * time.Minute` (`backend.go:50`). A new pod's token is picked up within a minute.
- `token_review.go:70-74`: logins always go through the TokenReview API; the reviewer bearer is the stored or locally
  read JWT, else the client's own JWT. `disable_local_ca_jwt` does not select "OIDC discovery" — the comment at
  `scripts/lib/test.sh:711-720` is wrong.
- `path_config.go:167,201`: `vault write auth/kubernetes/config` builds a fresh config from the request; an omitted
  `token_reviewer_jwt` is stored empty, so a write without it clears the stale value.
- Vault's ServiceAccount `vault` already has `system:auth-delegator` (`vault-auth-delegator`, `vault.sh:2111`, `:2309`),
  which TokenReview needs.

## Fix

Every writer of `auth/kubernetes/config` on the in-cluster mount stops storing a reviewer JWT and stops setting
`disable_local_ca_jwt=true`. It writes `kubernetes_host="https://kubernetes.default.svc:443"` and
`kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt` only (the flag left at its default,
false). Vault then follows pod restarts and token rotation by itself; no watchdog refresh is needed.

`scripts/lib/test.sh` also passes the root token inside `kubectl exec` strings (`VAULT_TOKEN='$root_token'`), against
the A02 rule: `test_vault` at :723, :731, :739, and `_cleanup_vault_test` (run by `test_vault`'s EXIT/TERM trap) at
:816, :820. The trap string at :705 embeds the token value too. All five exec calls move to the stdin pattern used by
`_hub_data_repoint_vault` (`read -r VAULT_TOKEN; export VAULT_TOKEN; ...` with the token on stdin), and the trap stops
embedding the value (for example, it calls a function that reads the token from a variable). The wrong comment at
:711-720 is removed.

How the token is passed (proven by Claude, 2026-11-15, bash 5.3.20 and 3.2.57 on the M4, `set -x` with a marker
value): `_no_trace <cmd> <<<"$root_token"` never shows the value in the trace; `printf %s "$t" | _no_trace <cmd>` and
`_no_trace <cmd> < <(printf %s "$t")` both trace `printf %s <value>`. Use the here-string form under `_no_trace` only.
The values interpolated into today's double-quoted `sh -c "..."` strings (`$sa`, `$test_ns`, `$vault_secret_path`,
`$secret_key`, `$secret_val`) become positional arguments (`sh -c '...' sh "$sa" ...`) so the single-quoted script
does not splice them (A03).

Note for whoever deploys: `_vault_set_eso_reader` returns early when the `eso-reader` policy exists
(`vault.sh:2089-2092`), so `deploy_vault` on an existing cluster does not rewrite the config; an existing hub is healed
only by the live repair below (done 2026-11-15) or by a `_vault_configure_secret_reader_role` caller.

Stub needs (from spec review): `_vault_set_eso_reader` and `_vault_configure_secret_reader_role` send their script on
stdin, so the `_vault_exec_stream` stub must capture stdin (reuse the harness in
`scripts/tests/plugins/vault_role_policy_merge.bats:21-52`; `_vault_policy_exists` must return 1 for the first).
`hub_data.sh:847` has the script in argv and the token on stdin. `test_vault` has no harness yet: the `_kubectl` stub
must return base64 of the fake token for `get secret vault-root` (:702-703) and the secret value for
`exec vault-read -- cat /tmp/secret` (:771), or the function sleeps 30 s and calls `_err` (:770-783).

Out of scope (captured separately as `2026-11-15-root-token-and-sa-jwt-in-kubectl-exec-argv-test-eso-get-ldap-password.md`):
`test_eso` root token in argv (`test.sh:583`, :587, :661), the ServiceAccount JWT and derived token at `test.sh:792-796`,
and `bin/get-ldap-password:132-143`. Also out of scope: `configure_vault_app_auth` (custom mount for a remote app cluster, `vault_app_auth.bats:175`) — it
already stores no reviewer JWT; unchanged. The watchdog shard bug is separate
(`2026-11-15-vault-unseal-watchdog-secret-shard-rejected-errors-suppressed.md`).

**Live repair after land** (operator go needed; root token on stdin): one `vault write auth/kubernetes/config` in the
new form. It is the same write, so it doubles as the first live evidence.

## Contract readers

Contract: the stored `auth/kubernetes/config` of the in-cluster Vault (grep `token_reviewer_jwt|disable_local_ca_jwt|auth/kubernetes/config`, 2026-11-15).

- Writers (all change):
  - `scripts/plugins/vault.sh:2106-2109` (`_vault_set_eso_reader`)
  - `scripts/plugins/vault.sh:2305` (`_vault_configure_secret_reader_role`)
  - `scripts/plugins/hub_data.sh:847` (`_hub_data_repoint_vault`, DR recovery)
  - `scripts/lib/test.sh:722-727` (`test_vault`; also the A02 token-in-argv fix at :705, :723, :731, :739 and in
    `_cleanup_vault_test` at :816, :820)
- TokenReview permission: live 2026-11-15, `kubectl auth can-i create tokenreviews.authentication.k8s.io
  --as=system:serviceaccount:secrets:vault` → `yes`, via `vault-auth-delegator` (ours, `vault.sh:2112`, `:2308`) and
  `vault-server-binding` (the Helm chart's own), so the DR path that never creates ours (`hub_data.sh:844-866`) is covered.
- Readers: Vault's kubernetes auth plugin (behaviour proven above), and everything that logs in through
  `auth/kubernetes/login` — unchanged roles; only the reviewer token source changes, so each benefits:
  ESO stores (`ClusterSecretStore vault-backend`, `identity/vault-kv-store`); `scripts/plugins/hub_data.sh:191`
  (`_hub_data_vault_login`, role `hub-data-inventory`); the credential rotators
  `scripts/etc/argocd/platform-ops/grafana-credential-rotator.yaml:109`, `keycloak-credential-rotator.yaml:75`,
  `argocd-credential-rotator.yaml:112`; `scripts/etc/jenkins/cert-rotator.sh:278` and `vault-seed-wrapper.yaml:22`
  (deprecated Jenkins); `scripts/lib/test.sh:760`, `:793` (`test_vault` login checks).
- Production caller of a writer: `bin/k3dm-orbstack-upgrade:131` runs `hub_data_repoint_vault` when the vault-0 UID
  changed and a store is invalid (the existing automated mitigation for this bug after an OrbStack upgrade; unchanged,
  and after the fix it writes the new form).
- Tests that assert on the writers: `scripts/tests/plugins/hub_data.bats:906-918`, `:1172` (stub `_vault_exec_stream`;
  order and payload checks must still pass); `scripts/tests/bin/orbstack_upgrade.bats:317-328` (calls
  `hub_data_repoint_vault`, unchanged); `scripts/tests/plugins/vault_role_policy_merge.bats:102-105` (drives
`_vault_configure_secret_reader_role`; its stub discards stdin, so it still passes); `scripts/tests/plugins/vault_app_auth.bats:175` (other mount, unchanged).

## Acceptance

```yaml
must:
  - id: M1
    text: "Each of the four writers sends a vault write auth/kubernetes/config that sets kubernetes_host and kubernetes_ca_cert from the pod's ServiceAccount CA, and nothing else that pins a reviewer."
  - id: M2
    text: "test_vault and _cleanup_vault_test pass the root token to every vault command on stdin, never inside a kubectl exec argument list or the trap string."
  - id: M3
    text: "Existing hub_data.bats re-point tests (order config, shards, vault-root, root; payload root_token) still pass."
must_not:
  - id: N1
    text: "No writer stores token_reviewer_jwt (no token_reviewer_jwt= in any command sent to Vault for this mount)."
  - id: N2
    text: "No writer sets disable_local_ca_jwt=true."
  - id: N3
    text: "No kubectl argument and no trap string set by test_vault (including the _cleanup_vault_test calls it triggers) contains the root token value."
evidence:
  - {id: E1, proves: [M1, N1, N2], kind: offline, intent: "You will see a bats test drive each of the four writer functions with Vault and kubectl stubbed, capture exactly what each sends to Vault (argv and stdin), and fail if it contains token_reviewer_jwt= or disable_local_ca_jwt=true, or lacks kubernetes_host and kubernetes_ca_cert; it fails on today's code for all four, and a positive control shows the capture really sees a planted token_reviewer_jwt."}
  - {id: E2, proves: [M2, N3], kind: offline, intent: "You will see a bats test run test_vault with a fake root token string, record every kubectl argument including those from its cleanup trap, and fail if the fake token appears in any argument, in the trap text, or in the xtrace output of a run under set -x, while showing it does arrive on stdin; it fails on today's test.sh."}
  - {id: E3, proves: [M3], kind: offline, intent: "You will see the existing hub_data.bats, orbstack_upgrade.bats and vault_role_policy_merge.bats suites pass unchanged."}
  - {id: E4, proves: [M1, N1], kind: live, intent: "After the operator-approved repair on the M5 hub, Claude shows vault read auth/kubernetes/config with token_reviewer_jwt_set false and disable_local_ca_jwt false, both ESO stores Ready, 9/9 ExternalSecrets synced, and the vault ServiceAccount allowed to create TokenReviews (host, time, Vault version)."}
  - {id: E5, proves: [M1], kind: live, intent: "At the next vault-0 restart (operator present to unseal), Claude shows ESO stores return Ready after unseal (on their own refresh, or after a reconcile annotation) with no write to auth/kubernetes/config in between."}
interface:
  - "scripts/plugins/vault.sh: _vault_set_eso_reader, _vault_configure_secret_reader_role"
  - "scripts/plugins/hub_data.sh: _hub_data_repoint_vault"
  - "scripts/lib/test.sh: test_vault, _cleanup_vault_test"
  - "Vault path auth/kubernetes/config on the in-cluster mount"
mutants:
  - "m1: restore token_reviewer_jwt=\"$(cat .../token)\" in _hub_data_repoint_vault only — E1 red"
  - "m2: add disable_local_ca_jwt=true to _vault_configure_secret_reader_role only — E1 red"
  - "m3: put VAULT_TOKEN='$root_token' back in the test_vault role write only — E2 red"
  - "m4: restore token_reviewer_jwt=\"$(cat .../token)\" in _vault_set_eso_reader only — E1 red"
  - "m5: restore token_reviewer_jwt and disable_local_ca_jwt=true in the test_vault config write only — E1 red"
  - "m6: put VAULT_TOKEN='$root_token' back in _cleanup_vault_test's kv delete only — E2 red"
```

## Worker definition of done

- Change only `scripts/plugins/vault.sh`, `scripts/plugins/hub_data.sh`, `scripts/lib/test.sh` and new or existing
  tests under `scripts/tests/`. Apply each mutant m1-m6 and paste the red run. Keep the `_no_trace` and stdin patterns; never print or log a token. Show E1 and E2 red
  on today's code, then green; run `bats scripts/tests/plugins/hub_data.bats scripts/tests/bin/orbstack_upgrade.bats`
  and `bats scripts/tests/plugins/vault_role_policy_merge.bats` and `make test`. Paste command, rc and proving lines. Leave changes uncommitted; Claude reviews and lands. Never
  touch a live cluster.

## Live repair (Claude, operator go 2026-11-15, M5 hub `k3d-k3d-cluster`, Vault 1.20.1)

16:35:35Z: `vault write auth/kubernetes/config kubernetes_host=https://kubernetes.default.svc:443
kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt` (root token piped from `vault-root` to the
pod's stdin, never in argv) → `Success!`. `vault read`: `token_reviewer_jwt_set: false`, `disable_local_ca_jwt: false`.
After a reconcile annotation on both stores and `force-sync` on the ExternalSecrets: `vault-backend` and
`identity/vault-kv-store` Ready at 16:36:14Z; 8/9 synced, then `cicd/argocd-oidc-secret` (stuck in backoff from the
"store not ready" error) synced at 16:37:37Z on a second force-sync → 9/9. Every ArgoCD application Healthy. This is
E4 for the config shape on the live hub; the code fix (four writers) is still to be dispatched, and E5 (survives the
next vault-0 restart) is still open. Until the code lands, `test_vault` or a DR re-point would write the old form back.
