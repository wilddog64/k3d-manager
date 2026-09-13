# `make status CLUSTER_PROVIDER=k3s-hostinger` — 2 errors, 2 warnings (2026-09-11)

Reported output:

```
✗ Product images: empty or non-list response
! Keycloak login: no credentials (k3dm-smoke-user Secret absent; set K3DM_SMOKE_KC_USER/PASS)
! Frontend login: skipped (no Keycloak token)
✗ Grafana login: HTTP 401
Overall: FAIL (2 errors, 2 warnings)
```

Four reported symptoms, three distinct causes, plus two defects the run did not
report.

## Finding 1 - Hub Vault Kubernetes auth is broken; 24/25 hub ExternalSecrets are failing

**This is the largest problem and `make status` did not report it.**

`auth/kubernetes/login` on the hub Vault returns `403 permission denied` for both
stores:

```
ClusterSecretStore vault-backend : Ready=False  InvalidProviderConfig "unable to create client"
SecretStore identity/vault-kv-store : Ready=False
error: unable to log in with Kubernetes auth:
  PUT http://vault.secrets.svc:8200/v1/auth/kubernetes/login -> Code: 403 permission denied
```

Consequence: **24 of 25 hub ExternalSecrets are `Ready=False`** (`could not get
secret data from provider`) — every hub secret is frozen at its last-synced
value. The one healthy ES is unrelated.

Ruled out by direct check:

| Hypothesis | Evidence against |
|---|---|
| Vault sealed / down | `vault status` → `Sealed false`, `Initialized true`, pod `1/1 Running` |
| Cluster CA rotated by the rebuild | Vault-stored `kubernetes_ca_cert` and live `kube-root-ca.crt` have **identical** SHA-256 fingerprints (`1B:FC:4C:…D7:87`), both `CN=k3s-server-ca@1789083601` |
| Missing reviewer RBAC | `vault-auth-delegator` and `vault-server-binding` both bind `ServiceAccount secrets/vault` to `system:auth-delegator` |
| Roles deleted | `auth/kubernetes/role` still lists `eso-reader`, `eso-ldap-directory`, `argocd-rotation`, `grafana-rotation` |

Remaining cause: the stored **`token_reviewer_jwt` is stale**. This is a known and
already-documented failure mode in this repo — `scripts/lib/test.sh:710-726`:

> "Projected SA tokens rotate every ~24h so we also refresh `token_reviewer_jwt`
> with the pod's current token."

`vault-0` has restarted 3 times (most recently ~96m before the run), so the JWT
Vault holds no longer validates.

**Repair** (the canonical form from `scripts/lib/test.sh`):

```bash
VT=$(kubectl --context k3d-k3d-cluster -n secrets get secret vault-root \
      -o jsonpath='{.data.root_token}' | base64 -d)
kubectl --context k3d-k3d-cluster -n secrets exec -i vault-0 -- \
  sh -c "VAULT_TOKEN='$VT' vault write auth/kubernetes/config \
    token_reviewer_jwt=\"\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)\" \
    disable_local_ca_jwt=true \
    kubernetes_host=\"https://kubernetes.default.svc:443\" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
```

Note the current live config has `disable_local_ca_jwt=false` and
`kubernetes_host=https://10.43.0.1:443`; the command above also restores the
TokenReview mode the repo standardised on.

## Finding 2 - `make status` never checks hub ESO (coverage gap, causes a false green)

The run printed `✓ ESO ExternalSecrets: 20/20 synced` while the hub was 24/25
broken. Both statements are true — the ESO checks run against the **app cluster**
(`ubuntu-hostinger`), which really is 20/20 `Ready=True`. The hub's ESO is never
sampled.

This matters because hub-hosted credentials (Grafana, Keycloak, ArgoCD) are read
from the hub by the very same smoke run. A green ESO line next to a Grafana 401
is actively misleading. **Not yet fixed** — needs a spec.

## Finding 3 - Grafana login HTTP 401

Downstream of Finding 1. Grafana reads `GF_SECURITY_ADMIN_PASSWORD` from
`monitoring/grafana-admin-credentials`, and the smoke check reads the same
Secret — but that Secret's ExternalSecret is one of the 24 in `SecretSyncedError`,
so it is frozen at a stale value.

Verified directly: authenticating to `https://grafana.3ai-talk.org/login` with the
password currently in the Secret also returns **401**, so the value in the Secret
is not the one Grafana is enforcing. Grafana only applies
`GF_SECURITY_ADMIN_PASSWORD` when it initialises `grafana.db`; the database here
is persistent (`/var/lib/grafana/grafana.db`, 1.9MB, pre-dating the current pod),
so the stored admin password has diverged from the Secret.

Fix Finding 1 first, let ESO resync, then re-check. If it still 401s the
`grafana.db` password must be reset explicitly (`grafana cli admin
reset-admin-password`) — env changes alone will not move it.

## Finding 4 - Keycloak login "no credentials" (correct message, missing seed)

Not a code bug. `identity/k3dm-smoke-user` is genuinely absent from the hub — the
`identity` namespace holds only `keycloak-client-secrets`, `keycloak-secrets`,
`ldap-secrets`, `openldap-admin`.

That Secret is created by `keycloak_seed_smoke_user` (`scripts/plugins/keycloak.sh:486`),
which exists because the app-owned `frontend` client has
`directAccessGrantsEnabled=false` and can never serve a password grant. The seed
did not survive the hub rebuild.

The webhook's fallback lookup of `keycloak-admin-secret` / key `password` was
checked and is **correct** — those are the documented defaults
(`keycloak.sh:37-38`); that Secret is simply absent too.

**Repair:** `scripts/k3d-manager keycloak_seed_smoke_user`. The seeder reads admin
credentials from `keycloak-secrets`, which is ESO-managed and currently stale, so
do this after Finding 1.

## Finding 5 - Frontend login "skipped"

Pure cascade of Finding 4 — the check is gated on `kc_token is None`. No separate
action; it clears when the smoke user is reseeded.

## Finding 6 - Product images: catalog is genuinely empty

Not a transport failure. The endpoint is healthy and returns valid JSON:

```
GET https://frontend.3ai-talk.org/api/products -> HTTP 200
{"items":[],"total":0,"page":1,"page_size":20,"pages":0}
```

`product-catalog-5767467bcd-gzvvs` is `1/1 Running` (12d) on the app cluster,
whose ESO is fully healthy — so this is not a credential problem. The product
catalog database has no rows; the catalog needs reseeding. Root-causing which
seed step was skipped needs a query against the products database.

The check's wording (`empty or non-list response`) conflates "endpoint broken"
with "zero products", which sent the first pass of this triage down the wrong
path. Worth splitting into two distinct details.

## Finding 7 - FIXED: product-catalog diagnostic selector matched no pods

Both smoke-failure triage maps in `bin/k3dm-webhook` (lines 2264 and 2498)
selected `app=product-catalog`. The deployed pod carries only:

```
app.kubernetes.io/component=backend
app.kubernetes.io/name=product-catalog
app.kubernetes.io/part-of=shopping-cart
```

No `app` label. So every "Product images" failure — including this one — produced
empty pod state in the triage output, exactly when that output was needed.

Fixed in `5f356e90`: both entries now use `app.kubernetes.io/name=product-catalog`,
verified to match the live pod. `Frontend` keeps `app=frontend`, which was
checked and does exist on that pod (it carries both label styles).

## Order of operations

1. Refresh the hub Vault `token_reviewer_jwt` (Finding 1) — unblocks 24 ESOs.
2. Confirm `ClusterSecretStore vault-backend` returns `Ready=True`.
3. `scripts/k3d-manager keycloak_seed_smoke_user` (Findings 4, 5).
4. Re-run `make status`; if Grafana still 401s, reset `grafana.db` admin password (Finding 3).
5. Reseed the product catalog (Finding 6).
6. Spec the hub-ESO coverage gap (Finding 2).

---

## Resolution log (2026-09-11, same day)

### Finding 1 — FIXED. Hub ESO recovered 1/25 → 24/25

The user ran the `vault write auth/kubernetes/config` repair. `Success! Data
written`. Confirmed working end-to-end:

```
ClusterSecretStore vault-backend        Ready=True  "store validated"
SecretStore identity/vault-kv-store     Ready=True  "store validated"
hub ExternalSecrets                     24/25 Ready=True
```

**Both stores lag the fix.** Immediately after the write both still reported
`Ready=False / InvalidProviderConfig`, and the ExternalSecrets stayed failed —
the controller had not revalidated yet. Annotating with `force-sync` flipped the
stores to `Ready=True`; the ExternalSecrets then needed their own `force-sync`
(refreshInterval is 1h, so they would otherwise have trailed by up to an hour).
Do not read a post-repair status within the first ~60s as evidence the repair
failed.

### Finding 3 — CONFIRMED genuine, still open. Grafana admin password diverged

Now proven rather than inferred. With the freshly-resynced Secret, Grafana itself
answers:

```json
{"message":"Invalid username or password","messageId":"password-auth.failed","statusCode":401}
```

So ESO was only half the story: the Secret is now current, and Grafana still
rejects it. The persistent `grafana.db` holds an admin password predating the
current Secret, and `GF_SECURITY_ADMIN_PASSWORD` is only applied at first DB
init. Repair (needs `kubectl exec`):

```bash
GP=$(kubectl --context k3d-k3d-cluster -n monitoring get secret grafana-admin-credentials \
      -o jsonpath='{.data.admin-password}' | base64 -d)
kubectl --context k3d-k3d-cluster -n monitoring exec deploy/kube-prometheus-stack-grafana \
  -c grafana -- grafana cli admin reset-admin-password "$GP"
```

### Finding 8 — NEW. Cloudflare blocks User-Agent-less probes (error 1010)

A probe of `https://grafana.3ai-talk.org/login` with no `User-Agent` returns
**HTTP 403, body `error code: 1010`** — a Cloudflare browser-integrity block, not
a Grafana response. The identical request with `User-Agent: k3dm-smoketest/1`
reaches Grafana and returns a real 401 JSON body.

This nearly derailed the triage: the 403 looked like a second, different auth
failure. Any manual probe of a `*.3ai-talk.org` host must send a User-Agent, and
any `1010` body should be read as "edge blocked me", never as an application
verdict. The smoke tests already set a UA, so they are unaffected.

### Finding 4/5 — still open, command corrected

`keycloak_seed_smoke_user` must run with the provider set, or
`_keycloak_smoke_base_url` (`keycloak.sh:376-382`) falls back to
`http://keycloak.shopping-cart.local` and dies with curl exit 7:

```bash
CLUSTER_PROVIDER=k3s-hostinger ./scripts/k3d-manager keycloak_seed_smoke_user
```

Its admin-token source (`keycloak-secrets`) is now resynced, so this should
succeed. `https://keycloak.3ai-talk.org/realms/master/.well-known/openid-configuration`
returns HTTP 200.

### Finding 9 — NEW. `platform-ops/app-cluster-kubeconfig` has no source data

The one remaining failed hub ExternalSecret. Not an auth problem — the Vault path
does not exist at all:

```
vault kv list secret/platform-ops -> No value found at secret/metadata/platform-ops
```

No seeder for `platform-ops/app-cluster-hostinger` exists anywhere in the repo.
Its only consumer (`vulnerability-inventory-exporter.yaml:398`) mounts it
`optional: true`, so this degrades gracefully rather than breaking the exporter.
Needs a decision: seed it, or drop the ExternalSecret.

### Still open after this pass

| # | Item | Blocked on |
|---|---|---|
| 3 | Grafana admin password reset | `kubectl exec` (classifier) |
| 4/5 | Keycloak smoke-user reseed | classifier |
| 6 | Product catalog empty | data seed, root cause unknown |
| 9 | `app-cluster-kubeconfig` Vault path | decision: seed or drop |
| 2 | Hub-ESO coverage gap in `make status` | needs a spec |

### Finding 10 — NEW. A failed ArgoCD operation hides behind a green app and blocks self-heal

This is the defect *class* behind Finding 6, and it has now been observed three
times in one day. When a sync operation errors **before reaching the PostSync
phase**, every *tracked* resource still compares `Synced` — the resources really
were applied. Only hooks are missing, and hooks are not tracked resources. So the
Application reports `Synced/Healthy` while `status.operationState.phase` is
`Error` or `Failed`.

| App | sync/health | `operationState.phase` | finishedAt | What was actually broken |
|---|---|---|---|---|
| `ubuntu-k3s-shopping-cart-product-catalog` | `Synced/Healthy` | `Error` | `2026-09-11T11:18:51Z` | seed + FTS-index PostSync hooks never ran → empty DB behind HTTP 200 |
| `ubuntu-k3s-data-layer` | `OutOfSync/Healthy` | `Error` | `2026-09-11T11:18:51Z` | 3 ExternalSecrets drifted; self-heal suppressed for 14h |
| `shopping-cart-identity` | `Synced/Healthy` | `Failed` | `2026-09-11T01:54:41Z` | `keycloak-realm-reconcile` hook Job failed (Finding 11) |

Both `Error` cases share the same origin: `argocd-repo-server` was crash-looping
(28 restarts) during the `11:11:44Z → 11:18:51Z` window and the operation died on
`ComparisonError: ... dial tcp 10.43.86.193:8081: connection refused (retried 5
times)`.

**The important correction.** It is tempting to assume the `Synced` case is the
dangerous one and a drifted app will self-heal. It will not.
`ubuntu-k3s-data-layer` had `syncPolicy.automated.selfHeal: true` **and** real
drift, and still sat broken for 14h: ArgoCD suppresses automated retry of a
revision whose last operation terminally failed, so it will not hot-loop on a
known-bad revision. The `Error` phase is the blocker, not the absence of drift.
Neither auto-sync nor self-heal can recover either shape without an operator.

Consequences:

- **Detection.** `argocd()` in `scripts/lib/hermes/sensors.py` keyed only on
  `health`/`sync` and was blind to all three rows above. Fixed 2026-09-11 in
  `6014235f`; spec
  `docs/bugs/v1.33.0-bugfix-hermes-argocd-operation-phase-blindspot.md`. Only
  `Error` and `Failed` alert — `Running`/`Terminating` are in-flight and a missing
  `operationState` yields `phase=None`, which must stay silent (`hub-loki` has no
  `operationState` at all).
- **Recovery lever** (operator-initiated; the only thing that works):

  ```bash
  kubectl -n cicd patch application <app> --type merge \
    -p '{"operation":{"initiatedBy":{"username":"<operator>"},"sync":{"revision":"HEAD"}}}'
  ```

`ubuntu-k3s-data-layer` was recovered this way at `2026-09-12T01:51:26Z`
(`Succeeded/Synced/Healthy`). Its drift turned out **not** to be the outage's
fault: three `shopping-cart-payment` ExternalSecrets
(`payment-encryption-secret`, `payment-gateway-secrets`, `postgres-payment-app`)
stored `refreshInterval: 15m0s` where git has `15m`. `kubectl diff` confirmed
that was the only real difference, and `git log -S'15m0s'` in
`shopping-cart-infra` returns zero matches — so the normalized value came from an
out-of-band `kubectl apply` during the Finding 1 ESO recovery, not from the repo.
After the sync all three read `15m` with `Ready=True`, and the value did not
re-normalize, so this will not recur on its own.

### Finding 11 — NEW. `keycloak-realm-reconcile` fails on `pipefail` when the realm has no LDAP provider

Root cause of the `shopping-cart-identity` row above, and the likely real origin
of the standing Keycloak smoke-user warning (Findings 4/5).

The hook Job is `Failed` with `backoffLimit: 1` (both pods exit 1), but its logs
end on a **success** line and emit no error:

```
browser-with-conditional-otp flow already exists; skipping creation
browser-with-conditional-otp flow activated
```

The next statement in the inlined script — which runs under
`/bin/bash -euo pipefail` — is:

```bash
ldap_id="$(
  /opt/keycloak/bin/kcadm.sh get components \
    -r "${KC_REALM}" -q type=org.keycloak.storage.UserStorageProvider \
    --fields id 2>/dev/null \
  | grep '"id"' | head -1 | sed 's/.*"id" : "\([^"]*\)".*/\1/'
)"

if [ -n "${ldap_id}" ]; then
  ...
else
  echo "No LDAP component found; skipping mapper setup"
fi
```

The realm genuinely has no LDAP provider — verified live:

```
kcadm.sh get components -r shopping-cart \
  -q type=org.keycloak.storage.UserStorageProvider --fields id,name
[ ]
```

So `grep '"id"'` matches nothing and exits 1. Under `pipefail` the whole pipeline
returns 1, and because this is a plain assignment, `set -e` kills the script
immediately with **no diagnostic**. The `else` branch that exists precisely to
handle "no LDAP component" is therefore **unreachable** — the script dies before
the `if` is ever evaluated.

Two defects, not one:

1. The guard is dead code. `|| true` (or `grep ... || :`) on the pipeline is the
   minimal fix, letting `ldap_id` be empty and the `else` branch run.
2. The failure is silent. Exit 1 with a success line as the last output is the
   worst possible signature — it is what made this look like a Keycloak problem
   rather than a shell problem.

Not fixed here: the Job manifest lives in `shopping-cart-infra`, which is
spec-first and Codex-only. Spec required before any edit.

### Finding 12 — NEW. `shopping_cart_reconcile_product_catalog()` is provider-coupled and swallows every failure

Named in Finding 6's remediation path, but it could not have helped here. All 13
of its `kubectl` calls hardcode `--context ubuntu-k3s`, and every one of them ends
in `|| _info WARN` (several also `2>/dev/null`), so the function runs to completion
and reports success while doing nothing.

**Correction to the first draft of this finding:** this is *not* "dead code". Per
`docs/bugs/2026-07-07-stale-kube-context-assumptions.md`, `ubuntu-k3s` is the **ACG
AWS sandbox context**, and these functions belong to the `acg-up` /
`bin/cluster-up:1831` flow where that context is correct. A sandbox lives 4h
(extendable to 8h), so its absence is the normal steady state, not drift. The
defect is the provider coupling plus the swallowed failures — not the function's
existence. It also means the worse failure mode is a **hang against an
expired-but-still-resolvable endpoint**, not a clean "context not found".

The swallowed failures are the more serious half: they are the same
reported-success-over-real-failure pattern as Finding 10, in the very function
meant to remediate it.

Not filed as a new bug doc — `docs/bugs/2026-07-07-app-cluster-vault-portability.md`
already owns this as **Phase 3 (De-hardcode `ubuntu-k3s`)**. The measured inventory
(24 sites across 3 functions in `scripts/plugins/shopping_cart.sh`, with the
default-preserving resolver `_shopping_cart_resolve_app_context()` already present
in the same file at `:553-563`) was appended there instead. That phase still needs
its re-scope and an implementation spec before any edit (`scripts/plugins/` is
spec-first).

### Still open after this pass (updated 2026-09-12)

| # | Item | Blocked on |
|---|---|---|
| 3 | Grafana admin password reset | `kubectl exec` (classifier) |
| 4/5 | Keycloak smoke-user reseed | classifier; likely downstream of Finding 11 |
| 9 | `app-cluster-kubeconfig` Vault path | decision: seed or drop |
| 2 | Hub-ESO coverage gap in `make status` | needs a spec |
| 11 | `keycloak-realm-reconcile` pipefail | spec + Codex in `shopping-cart-infra` |
| 12 | `shopping_cart_reconcile_product_catalog` context + swallowed failures | folded into portability Phase 3; needs re-scope + spec |

Closed this pass: Finding 6 (product catalog, repaired + root-caused), Finding 10
(detection shipped in `6014235f`; `ubuntu-k3s-data-layer` recovered).

### Update 2026-09-13

- **Finding 3 — likely MISDIAGNOSED.** Both 401 proofs were logins to
  `https://grafana.3ai-talk.org`, but `:3001` was port-forwarded to the
  **hostinger** `acg-kube-prometheus-stack-grafana`, not the hub
  `kube-prometheus-stack-grafana` whose Secret was used. The "diverged
  `grafana.db` password" is therefore unproven; do NOT run
  `reset-admin-password`. Repoint the port-forward to the hub (see recurrence
  note in `docs/issues/2026-07-08-hostinger-grafana-502-from-wrong-refresh-port-forward-target.md`)
  and re-run `make status` first.
- **Finding 9** — unchanged: ESO reports `Secret does not exist` for
  `platform-ops/app-cluster-hostinger`; still needs the seed-or-drop decision.
- **Finding 11** — code fix merged as shopping-cart-infra PR #97 (`1b35d962`),
  and `shopping-cart-identity` already tracks that revision, but the only hook
  Job run (`2026-09-12T12:04:19Z`) predates the merge and ran the old script.
  Operator sync with hook replay still owed; an agent-initiated sync was denied
  as a shared-cluster mutation.
