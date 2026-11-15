# Bug: any vault-0 pod restart breaks every hub ESO store (stale pod-bound `token_reviewer_jwt`, 403 on login)

**Status:** OPEN — captured 2026-11-15
**Priority:** P2 (proposed: all hub ExternalSecrets stop refreshing and new pods that need them cannot start; manual workaround exists)
**Introduced by:** pre-existing (auth config written with a pod-bound reviewer token by `_hub_data_repoint_vault`, `scripts/plugins/hub_data.sh:847`, and `vault.sh:2106`, `:2305`)
**Should have been caught by:** deploy step
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-15 (hub repaired 16:37Z; intent approved; Argon + Fable spec review running, then dispatch to Flash `gemini-3.8-flash-high`)
**Intent approved:** operator, 2026-11-15 ("approved")
**Spec review:** risk medium (hub Vault auth) — Argon + Fable blind before dispatch
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

`scripts/lib/test.sh` (`test_vault`, :722-733) also passes the root token inside `kubectl exec` strings
(`VAULT_TOKEN='$root_token'`), against the A02 rule. Both exec calls move to the stdin pattern used by
`_hub_data_repoint_vault` (`read -r VAULT_TOKEN; export VAULT_TOKEN; ...` with the token on stdin). The wrong comment
at :711-720 is removed.

Out of scope: `configure_vault_app_auth` (custom mount for a remote app cluster, `vault_app_auth.bats:175`) — it
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
  - `scripts/lib/test.sh:722-727` (`test_vault`; also the A02 token-in-argv fix at :723 and :730)
- Readers: Vault's kubernetes auth plugin (behaviour proven above); every ESO store logging in through
  `auth/kubernetes/login` (`ClusterSecretStore vault-backend`, `identity/vault-kv-store`) — unchanged config, only the
  reviewer source changes.
- Tests that assert on the writers: `scripts/tests/plugins/hub_data.bats:906-918`, `:1172` (stub `_vault_exec_stream`;
  order and payload checks must still pass); `scripts/tests/bin/orbstack_upgrade.bats:317-328` (calls
  `hub_data_repoint_vault`, unchanged); `scripts/tests/plugins/vault_app_auth.bats:175` (other mount, unchanged).

## Acceptance

```yaml
must:
  - id: M1
    text: "Each of the four writers sends a vault write auth/kubernetes/config that sets kubernetes_host and kubernetes_ca_cert from the pod's ServiceAccount CA, and nothing else that pins a reviewer."
  - id: M2
    text: "test_vault passes the root token to both vault commands on stdin, never inside the kubectl exec argument list."
  - id: M3
    text: "Existing hub_data.bats re-point tests (order config, shards, vault-root, root; payload root_token) still pass."
must_not:
  - id: N1
    text: "No writer stores token_reviewer_jwt (no token_reviewer_jwt= in any command sent to Vault for this mount)."
  - id: N2
    text: "No writer sets disable_local_ca_jwt=true."
  - id: N3
    text: "No kubectl exec or _vault_exec argument in test_vault contains the root token value."
evidence:
  - {id: E1, proves: [M1, N1, N2], kind: offline, intent: "You will see a bats test drive each of the four writer functions with Vault and kubectl stubbed, capture exactly what each sends to Vault (argv and stdin), and fail if it contains token_reviewer_jwt= or disable_local_ca_jwt=true, or lacks kubernetes_host and kubernetes_ca_cert; it fails on today's code for all four, and a positive control shows the capture really sees a planted token_reviewer_jwt."}
  - {id: E2, proves: [M2, N3], kind: offline, intent: "You will see a bats test run test_vault with a fake root token string, record every kubectl argument, and fail if the fake token appears in any argument while showing it does arrive on stdin; it fails on today's test.sh."}
  - {id: E3, proves: [M3], kind: offline, intent: "You will see the existing hub_data.bats and orbstack_upgrade.bats suites pass unchanged."}
  - {id: E4, proves: [M1, N1], kind: live, intent: "After the operator-approved repair on the M5 hub, Claude shows vault read auth/kubernetes/config with token_reviewer_jwt_set false and disable_local_ca_jwt false, both ESO stores Ready, and Hermes' eso sensor back to 9/9 synced (host, time, Vault version)."}
  - {id: E5, proves: [M1], kind: live, intent: "At the next vault-0 restart (operator present to unseal), Claude shows ESO stores return Ready within about two minutes of unseal with no config write in between."}
interface:
  - "scripts/plugins/vault.sh: _vault_set_eso_reader, _vault_configure_secret_reader_role"
  - "scripts/plugins/hub_data.sh: _hub_data_repoint_vault"
  - "scripts/lib/test.sh: test_vault"
  - "Vault path auth/kubernetes/config on the in-cluster mount"
mutants:
  - "m1: restore token_reviewer_jwt=\"$(cat .../token)\" in _hub_data_repoint_vault only — E1 red"
  - "m2: add disable_local_ca_jwt=true to _vault_configure_secret_reader_role only — E1 red"
  - "m3: put VAULT_TOKEN='$root_token' back in the test_vault role write only — E2 red"
```

## Worker definition of done

- Change only `scripts/plugins/vault.sh`, `scripts/plugins/hub_data.sh`, `scripts/lib/test.sh` and new or existing
  tests under `scripts/tests/`. Keep the `_no_trace` and stdin patterns; never print or log a token. Show E1 and E2 red
  on today's code, then green; run `bats scripts/tests/plugins/hub_data.bats scripts/tests/bin/orbstack_upgrade.bats`
  and `make test`. Paste command, rc and proving lines. Leave changes uncommitted; Claude reviews and lands. Never
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
