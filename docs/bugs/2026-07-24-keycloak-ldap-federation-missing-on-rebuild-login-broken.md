# Bug: shopping-cart login fails after hub rebuild — LDAP federation never created ("Invalid username or password")

**Primary branch (k3d-manager):** `k3d-manager-v1.18.0`
**Second repo (shopping-cart-infra):** `feat/keycloak-ldap-federation-self-heal` (branch from `origin/main`)

**Files:**
- k3d-manager: `bin/cluster-up` (Step 10d.6 block, ~978-1011)
- shopping-cart-infra: `identity/keycloak/keycloak-reconcile-hook-job.yaml` (PostSync hook script)

**Classification:** Bugfix in `docs/bugs/` (exempt from the max-5-plan limit).
**Discovered live on the hub, 2026-07-24.** This is a **regression** of
`docs/bugs/v1.4.11-bugfix-keycloak-ldap-bind-stale-on-realm-exists.md` and
`docs/bugs/2026-05-25-keycloak-reconcile-partial-import-not-idempotent.md`: the prior fixes
handled a *stale credential on an existing* LDAP component, but not the case where the
component is **entirely absent**, and they predate the ArgoCD PostSync hook crash below.

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — this is the
  "keycloak LDAP federation missing on rebuild / login broken" item.
- k3d-manager work: `git pull origin k3d-manager-v1.18.0` — never `main`.
- shopping-cart-infra work: `git checkout -b feat/keycloak-ldap-federation-self-heal origin/main`
  — never work from `main` (shopping-cart repos: always a feature branch).
- Read IN FULL before editing:
  - `bin/cluster-up` — Steps 10d.4 (realm import, ~883-942), 10d.5 (LDAP user passwords,
    ~944-976), 10d.6 (LDAP bind reconcile, ~978-1011), 10d.7 (group mapper, ~1013+)
  - `identity/keycloak/keycloak-reconcile-hook-job.yaml` — the whole inline script,
    especially the `ldap_id="$(...)"` block (~175-183) and the `if [ -n "${ldap_id}" ]`
    mapper section (~185-270)
  - The two prior specs named above — do not re-introduce what they fixed.
- Implement exactly what is written — no interpretation, no scope expansion.

---

## Symptom

Shopping-cart SSO login returns **"We are sorry… Invalid username or password"** for every
real user after a hub rebuild. Measured on the hub 2026-07-24:

- `shopping-cart` realm had **zero** `UserStorageProvider` components (`kcadm get components
  -q type=org.keycloak.storage.UserStorageProvider` → `[ ]`).
- The realm contained only the local `k3dm-smoke` user — none of the LDAP users
  (`admin`, `developer`, `operator`) that exist in OpenLDAP under
  `ou=users,dc=shopping-cart,dc=local`.
- The ArgoCD PostSync hook Job `keycloak-realm-reconcile` (owned by app
  `shopping-cart-identity`) was in **Error** (exit 1), last run 2026-07-20.

Live remediation already applied by Claude (create the component + correct bindCredential +
full sync) restored login — `admin`/`developer`/`operator` now carry a `federationLink`.
This spec makes that self-healing so a rebuild never reproduces the outage.

---

## Root causes (three, chained)

1. **`partialImport` does not create `components`.** Keycloak's partial import (used by the
   PostSync hook when the realm already exists) silently ignores the `components` block, so
   the LDAP `UserStorageProvider` defined in `realm-shopping-cart.json` is never created on
   the realm-exists path. The full realm import in `bin/cluster-up` Step 10d.4 only runs on
   HTTP **201** (realm absent); on **409** (realm exists) it falls through to client-only
   reconciliation and never re-creates the component.

2. **The PostSync hook crashes under `set -e` when no component exists.** In
   `keycloak-reconcile-hook-job.yaml` (~175-183):

   ```sh
   ldap_id="$(
     /opt/keycloak/bin/kcadm.sh get components -r "${KC_REALM}" \
       -q type=org.keycloak.storage.UserStorageProvider --fields id 2>/dev/null \
     | grep '"id"' | head -1 | sed 's/.*"id" : "\([^"]*\)".*/\1/'
   )"
   ```

   The job runs `bash -euo pipefail`. When the component list is empty, `grep '"id"'` exits
   1; under `pipefail` the pipeline returns 1, and under `set -e` the assignment aborts the
   whole job — **before** it can reach its own `else "No LDAP component found"` branch, which
   is therefore dead code. So the hook dies exactly when it most needs to report the problem.

3. **A stale bind credential baked into the mounted realm template (NOT an ExternalSecret
   drift).** During remediation the credential taken from the hook's mounted
   `keycloak-realm-import` realm JSON was 23 chars and **failed** to bind; the live LDAP
   admin password was 32 chars and bound. Investigation 2026-07-24 established where the 23
   came from — and it is **not** the live secrets:
   - The live LDAP **server** (`ldap` deployment, `envFrom secretRef: ldap-secrets`) and the
     live **Keycloak bind** secret (`keycloak-secrets.LDAP_BIND_CREDENTIAL`) are
     **byte-identical** (same sha256, 32 chars) and both resolve the **same** Vault key
     `secret/data/ldap/admin` property `admin_password`. **There is no live drift between the
     two secrets that matter.**
   - The 23-char value is a **pre-rendered literal baked into the mounted realm template**
     (`keycloak-realm-import` configMap in shopping-cart-infra). The hook's `render_realm()`
     does `sed 's/${LDAP_BIND_CREDENTIAL}/.../'`, but the mounted file no longer contains the
     `${LDAP_BIND_CREDENTIAL}` placeholder — it already holds a stale literal — so the
     substitution is a no-op and the stale value flows through.
   - Consequence for the fix: any create-when-missing MUST take `bindCredential` from the
     **live `${LDAP_BIND_CREDENTIAL}` env** (from `keycloak-secrets`, currently correct), not
     from the mounted template. `bin/cluster-up` Step 10d.6 already force-corrects an
     *existing* component's `bindCredential` — but it **warns and skips** when the component
     is absent (~1006-1007), which is exactly the failure state.

   **Separate latent hazard (owner-gated — see Change 3):** a *third* secret `openldap-admin`
   reads a **different** Vault path `ldap/openldap-admin` and holds a **different** value.
   That is the path the `ldap.sh` generator writes and `keycloak.sh` (`KEYCLOAK_LDAP_VAULT_PATH`)
   defaults to, so two parallel Vault representations of the LDAP admin password coexist.
   They do not break login today (the live consumers use `secret/data/ldap/admin`), but they
   can drift on a future rebuild. Converging them needs one Vault read to confirm values and
   is left as an owner decision.

---

## Fix

### Change 1 (k3d-manager) — `bin/cluster-up` Step 10d.6: create the component when missing

Make the `else` branch (component absent) **create** the LDAP `UserStorageProvider` from the
canonical config with the live bind credential, then sync — instead of warning and skipping.
This is the self-heal that closes root cause 1 on the 409 path.

**Exact old block (~1006-1008):**

```sh
    else
      _warn "[acg-up] Could not find LDAP federation component ID — skipping bind credential update"
    fi
```

**Exact new block:**

```sh
    else
      _info "[acg-up] LDAP federation component absent — creating it from canonical config"
      if kubectl exec -i -n identity --context k3d-k3d-cluster "${_kc_pod}" -- \
          env KC_ADMIN_PASS="${_kc_admin_pass}" LDAP_BIND="${_ldap_admin_pass}" sh -c '
            K=/opt/keycloak/bin/kcadm.sh
            "$K" config credentials --server http://localhost:8080 --realm master \
              --user admin --password "$KC_ADMIN_PASS" >/dev/null 2>&1 || exit 1
            RID="$("$K" get realms/shopping-cart --fields id 2>/dev/null \
              | sed "s/.*: \"//;s/\".*//" | head -1)"
            [ -n "$RID" ] || exit 1
            F="$(mktemp)"
            cat > "$F" <<JSON
            {"name":"ldap","providerId":"ldap","providerType":"org.keycloak.storage.UserStorageProvider","parentId":"$RID","config":{"enabled":["true"],"priority":["0"],"editMode":["READ_ONLY"],"syncRegistrations":["false"],"vendor":["other"],"usernameLDAPAttribute":["uid"],"rdnLDAPAttribute":["uid"],"uuidLDAPAttribute":["entryUUID"],"userObjectClasses":["inetOrgPerson, organizationalPerson"],"connectionUrl":["ldap://ldap.identity.svc.cluster.local:389"],"usersDn":["ou=users,dc=shopping-cart,dc=local"],"authType":["simple"],"bindDn":["cn=admin,dc=shopping-cart,dc=local"],"bindCredential":["$LDAP_BIND"],"searchScope":["2"],"trustEmail":["true"],"pagination":["true"],"batchSizeForSync":["1000"]}}
            JSON
            "$K" create components -r shopping-cart -f "$F" >/dev/null 2>&1 || { rm -f "$F"; exit 1; }
            rm -f "$F"
            NID="$("$K" get components -r shopping-cart \
              -q type=org.keycloak.storage.UserStorageProvider --fields id 2>/dev/null \
              | grep "\"id\"" | head -1 | sed "s/.*: \"//;s/\".*//")"
            [ -n "$NID" ] || exit 1
            "$K" create "user-storage/$NID/sync?action=triggerFullSync" -r shopping-cart >/dev/null 2>&1
          ' 2>/dev/null; then
        _info "[acg-up] LDAP federation component created and full sync triggered"
      else
        _warn "[acg-up] Failed to create LDAP federation component — SSO login may be broken"
      fi
    fi
```

Notes for the implementer:
- The bind credential is passed to the pod via **`env` (stdin/env), never as a positional
  argv token** — do not inline `${_ldap_admin_pass}` into the `sh -c` string. (This is a
  hardening improvement over the existing `-s 'config.bindCredential=[...]'` at ~1000; leave
  that existing line as-is — this spec does not rewrite the happy path.)
- The config mirrors the `components` block in
  `../shopping-carts/shopping-cart-infra/identity/keycloak/realm-shopping-cart.json`. If that
  file's LDAP config differs from the block above, **use the file as the source of truth** and
  reconcile the block to match (values only — keep the env-not-argv rule).

### Change 2 (shopping-cart-infra) — `keycloak-reconcile-hook-job.yaml`: don't crash, create when missing

Two edits to the inline hook script:

**2a — guard the `ldap_id` extraction so an empty result cannot abort the job.** Append
`|| true` to the pipeline inside the command substitution (so `grep` finding nothing yields
an empty `ldap_id` and control reaches the existing `if [ -n "${ldap_id}" ]` / `else` logic
instead of `set -e` killing the job):

**Exact old block (~175-183):**

```sh
          ldap_id="$(
            /opt/keycloak/bin/kcadm.sh get components \
              -r "${KC_REALM}" \
              -q type=org.keycloak.storage.UserStorageProvider \
              --fields id \
              2>/dev/null \
            | grep '"id"' | head -1 \
            | sed 's/.*"id" : "\([^"]*\)".*/\1/'
          )"
```

**Exact new block:**

```sh
          ldap_id="$(
            /opt/keycloak/bin/kcadm.sh get components \
              -r "${KC_REALM}" \
              -q type=org.keycloak.storage.UserStorageProvider \
              --fields id \
              2>/dev/null \
            | grep '"id"' | head -1 \
            | sed 's/.*"id" : "\([^"]*\)".*/\1/' || true
          )"
```

**2b — create the component in the `else` branch instead of only logging.** The existing
`else` prints `echo "No LDAP component found; skipping mapper setup"` (~269-270). Replace that
skip with: create the `UserStorageProvider`, re-resolve `ldap_id`, and fall through into the
existing mapper + `triggerFullSync` logic. Use the same `kcadm create components -f <file>`
pattern the mapper block already uses. Do NOT duplicate the mapper code — set `ldap_id` and
let the existing `if [ -n "${ldap_id}" ]` body run.

**Critical (Root cause 3):** set the new component's `bindCredential` from the **live
`${LDAP_BIND_CREDENTIAL}` env** (injected via `envFrom secretRef: keycloak-secrets`), NOT
from the mounted realm template — the mounted `/realm/realm-shopping-cart.json` may carry a
**stale baked literal** with no `${LDAP_BIND_CREDENTIAL}` placeholder left to substitute, and
reusing it reproduces the `AuthenticationFailure` this bug is about. Build the component JSON
inline (as Change 1 does) with `bindCredential=["${LDAP_BIND_CREDENTIAL}"]`.

### Change 3 (OUT OF SCOPE for this handoff — owner-gated) — collapse the parallel Vault paths

Investigation 2026-07-24 showed the live consumers do **not** drift (Root cause 3), so
Changes 1 and 2 fully fix the login outage. The remaining hazard is a **latent** one: the
LDAP admin password is represented under two Vault paths with different values —
`secret/data/ldap/admin`/`admin_password` (what `ldap-secrets` + `keycloak-secrets` consume)
vs `ldap/openldap-admin`/`LDAP_ADMIN_PASSWORD` (what the `ldap.sh` generator writes and
`keycloak.sh` `KEYCLOAK_LDAP_VAULT_PATH` defaults to). A rebuild that (re)generates into one
path while consumers read the other will reintroduce the drift.

**Do NOT implement Change 3 in this handoff.** It requires a Vault read (owner-only) to
confirm which path is canonical and whether the generator or the consumers should move. Once
the owner picks the canonical path, a follow-up spec repoints the minority side. Recorded here
so it is not lost; Changes 1 and 2 are complete and verifiable without it.

---

## Files Changed

| Repo | File | Change |
|------|------|--------|
| k3d-manager | `bin/cluster-up` | Step 10d.6 `else` branch creates the LDAP component when absent, then full-sync |
| shopping-cart-infra | `identity/keycloak/keycloak-reconcile-hook-job.yaml` | guard `ldap_id` (no `set -e` crash) + create component when missing |

---

## Rules

- k3d-manager: `bash -n bin/cluster-up` — parses clean;
  `shellcheck -S warning bin/cluster-up` — zero NEW warnings (record the baseline first).
- shopping-cart-infra: the hook script is embedded YAML — after editing, extract the script
  and run `bash -n` on it (or `yq '.spec.template.spec.containers[0].command[-1]' … | bash -n -`)
  — must parse clean.
- **Disappearance gate (hook):** `grep -c 'skipping mapper setup'
    identity/keycloak/keycloak-reconcile-hook-job.yaml` must drop to **0** (the skip is
  replaced by create-then-mapper).
- **Presence gate (hook):** the `ldap_id="$(...)"` block ends with `|| true`.
- **Presence gate (bin/cluster-up):** `grep -c 'creating it from canonical config' bin/cluster-up` → **1**.
- `./scripts/k3d-manager _agent_audit` (k3d-manager change) — **stage the file first**, then
  run under `/opt/homebrew/bin/bash`, capture `rc=$?` on its own line, report `rc=<n>`.
- No other files touched in either repo.

---

## Definition of Done

- [ ] `bin/cluster-up` Step 10d.6 creates the LDAP component when absent and triggers full sync
- [ ] `keycloak-reconcile-hook-job.yaml`: `ldap_id` guarded with `|| true`; `else` branch
      creates the component instead of skipping
- [ ] `bash -n` clean on both scripts; shellcheck zero new warnings on `bin/cluster-up`
- [ ] Disappearance + presence gates above all recorded with actual output
- [ ] `_agent_audit` `rc=0` (k3d-manager, staged first)
- [ ] Each repo: `git show --stat` shows exactly ONE file changed, ONE commit
- [ ] Committed and pushed — k3d-manager to `k3d-manager-v1.18.0`, shopping-cart-infra to
      `feat/keycloak-ldap-federation-self-heal`
- [ ] memory-bank updated with BOTH commit SHAs and task status

**Commit message — k3d-manager (exact):**
```
fix(keycloak): create LDAP federation component when absent so login self-heals on rebuild
```

**Commit message — shopping-cart-infra (exact):**
```
fix(keycloak): guard reconcile hook against empty component and create LDAP federation when missing
```

---

## What NOT to Do

- Do NOT inline `${_ldap_admin_pass}` / `${LDAP_BIND_CREDENTIAL}` as a positional argv token
  in any `sh -c` string — pass via `env`/stdin (secret hygiene; CLAUDE.md).
- Do NOT change the happy-path `update components/... -s config.bindCredential` line at
  ~998-1000 — this spec only adds the missing-component path.
- Do NOT switch the realm import from partialImport to full import on the 409 path — that
  would clobber runtime state (users, sessions). Create only the missing component.
- Do NOT invent a new Vault path for Change 3 — raise it as an owner decision.
- Do NOT touch `scripts/etc/keycloak/realm-config.json.tmpl` or the k3d-manager realm import
  (Step 10d.4) — the fix is the reconcile step, not the import.
- Do NOT create a PR (either repo)
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the one listed target per repo
- Do NOT commit to `main` in either repo

---

## Claude-only (do NOT delegate)

Live verification — driving `kcadm` against the running Keycloak, triggering syncs, and
confirming users federate — is Claude's step. The live remediation for the CURRENT outage is
already done (login restored 2026-07-24); this spec is the durable code fix, verified on the
next hub rebuild.
