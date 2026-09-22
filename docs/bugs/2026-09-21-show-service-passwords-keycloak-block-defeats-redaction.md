# Bug: the Keycloak block in `show-service-passwords` defeats redaction-by-convention, and its realm users always print N/A

**Filed:** 2026-09-21
**Branch:** `k3d-manager-v1.36.0`
**Status:** OPEN
**Targets:** `Makefile` (`show-service-passwords`), `bin/get-keycloak-password`
**Follows:** `docs/bugs/2026-09-21-vault-rebuild-leaves-prometheus-and-argocd-credentials-unseeded.md` (`6c744a23`)
**Related:** `docs/bugs/2026-05-11-keycloak-admin-password-reseed-on-rebuild.md`,
`docs/bugs/2026-07-30-keycloak-vault-ldap-password-drift-guard.md`

---

## Problem

Three defects in the same block, found while reading `make show-service-passwords` output
through a redaction filter.

### D1 — the output shape breaks the convention every other service follows

Every other service emits two separate labelled lines:

```
  Prometheus  https://prometheus.3ai-talk.org
    user:     admin
    password: <value>
```

Keycloak emits the credential on a `user:`-prefixed line instead (`Makefile:572-573`):

```
    admin user:     admin / <value>
    dev users:      admin / <v1>  |  developer / <v2>  |  operator / <v3>
```

This matters beyond aesthetics. Anything that consumes this output and redacts on the
`password:` convention — a filter, a log scrubber, an agent reading the terminal — passes the
Keycloak line through **unredacted**, because the secret does not follow a `password:` label.
This is not hypothetical: it leaked the live Keycloak admin password into a session transcript
on 2026-09-21. Four secrets on two lines, none of them labelled as secrets.

`user:` is exactly the label the convention marks as *safe to print*. Putting a password after
it is worse than having no convention at all.

### D2 — the three realm users always print `N/A`, and the message blames the wrong thing

`bin/get-keycloak-password <user> -q` returns empty for all three users. Verified on the live
hub (`kubectl config current-context` = `k3d-k3d-cluster`, so this is not context drift):

```
WARN: admin: not found in Vault (run make up first)
```

Live Vault probe — data **and** metadata, the discriminator established in the 2026-09-21
reseed spec:

| Path | data | metadata |
|---|---|---|
| `secret/keycloak/users/admin` | 404 | **404** |
| `secret/keycloak/users/developer` | 404 | **404** |
| `secret/keycloak/users/operator` | 404 | **404** |

```
LIST secret/metadata/keycloak → {"keys":["admin","clients"]}
```

Metadata 404 means never written to this Vault instance. And the LIST shows why the confusion
is easy: `secret/keycloak/admin` **does** exist and is unrelated — it holds the Keycloak
*service* admin (`admin_password`, `db_password`) and is one of the 14 keys in the hub seed
allowlist (`scripts/plugins/vault.sh:1119-1126`). The *realm SSO users* live at
`secret/keycloak/users/<user>` and are written **only** by `bin/cluster-up:1031` during the
LDAP/SSO seeding step. That path is **not** in the allowlist, so a hub rebuild never restores
it.

So `keycloak/users/*` is a third instance of the class root-caused in the reseed spec:
credentials outside the 14-key allowlist vanish on rebuild and every consumer degrades
silently. **This spec does not fix that** — see *Scope* below.

What this spec does fix is the lie in the message. `run make up first` is wrong advice on the
hub: `make up` does not seed these. The display cannot distinguish "not provisioned on this
cluster" from "lookup failed", and prints the same bare `N/A` for both.

### D3 — `bin/get-keycloak-password` puts the Vault token in the `kubectl exec` command string

`bin/get-keycloak-password:51-56`:

```bash
_vault_get() {
  local _path="$1" _field="$2"
  kubectl exec -n "${_VAULT_NS}" vault-0 -- \
    env VAULT_TOKEN="${_VAULT_TOKEN}" vault kv get -field="${_field}" "${_path}" 2>/dev/null
}
```

This violates a standing rule in `CLAUDE.md` — *"No secrets in `kubectl exec` command strings
that appear in logs"* and *"Vault tokens must never appear in script arguments visible in shell
history or CI logs — use env vars or stdin."* The root token lands in argv, so it is visible to
`ps`, to any trace, and to anything capturing the command.

The repo already has the correct wrapper. `bin/vault-exec:80-85` does it via stdin:

```bash
kubectl exec -i -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
  sh -c 'read -r VAULT_TOKEN; export VAULT_TOKEN; exec "$@"' sh "${CMD[@]}"
```

and `scripts/tests/bin/identity_tools.bats:12` pins that idiom. `bin/cluster-up:1070` even
tells operators to use `bin/vault-exec` for exactly this lookup. `get-keycloak-password`
reimplemented it unsafely instead of calling it.

Two smaller defects in the same script, fixed alongside because they are one-line each:

- It calls bare `kubectl` with **no `--context`** (`:45`, `:53`), unlike every other hub
  credential reader in the `Makefile`, which pins `--context k3d-k3d-cluster`. It works today
  only because the ambient context happens to be the hub. Point it at the hub explicitly.
- `_VAULT_TOKEN=$(... | base64 -d)` at `:45` runs under `set -euo pipefail` with no `|| true`;
  a `kubectl` failure there aborts the script before the clearer `_err` on the next line can
  report it.

---

## Scope

**In scope:** the display contract (D1), honest degradation messaging (D2), and the token-in-argv
fix plus the two one-line robustness fixes in `bin/get-keycloak-password` (D3).

**Explicitly OUT of scope — do not do these:**

- **Do NOT add `keycloak/users/*` to the 14-key seed allowlist** in `scripts/plugins/vault.sh`.
  Changing that allowlist is not approved and is a separate decision with its own blast radius
  (it would start copying realm user passwords between Vaults).
- **Do NOT seed, write, rotate or repair any Keycloak credential**, in Vault or in Kubernetes.
  This is a display-and-hygiene change. The `N/A` for the three realm users is *correct output*
  for this cluster's current state after the fix; the goal is to make it *honest*, not to make
  it non-empty.
- **Do NOT reformat any other service's block.** The other four already follow the convention.

---

## Fix

### M1 — `Makefile`: put every Keycloak secret behind a `password:` label

Replace the two `echo` lines at `Makefile:572-573`. Current:

```make
	echo "    admin user:     admin / $${_kc:-N/A}";\
	echo "    dev users:      admin / $${_realm_admin:-N/A}  |  developer / $${_dev:-N/A}  |  operator / $${_op:-N/A}";\
```

New — one labelled pair per account, matching the other four services:

```make
	echo "    user:     admin";\
	echo "    password: $${_kc:-N/A}";\
	echo "    realm SSO users (secret/keycloak/users/*):";\
	echo "      user:     admin";\
	echo "      password: $${_realm_admin:-$$_kc_hint}";\
	echo "      user:     developer";\
	echo "      password: $${_dev:-$$_kc_hint}";\
	echo "      user:     operator";\
	echo "      password: $${_op:-$$_kc_hint}";\
```

Every line carrying a secret now begins with `password:`. No secret appears on a `user:` line.

### M2 — `Makefile`: make the realm-user degradation honest

The three realm lookups share one cause, so compute the hint once, before the `echo`s, right
after the three `_realm_admin` / `_dev` / `_op` assignments (`Makefile:567-569`):

```make
	_kc_hint="N/A"; \
	if [ -z "$$_realm_admin$$_dev$$_op" ]; then \
	  _kc_hint="not provisioned on this cluster (seeded by bin/cluster-up, not by make up)"; \
	fi; \
```

When all three are empty the cause is structural, and the output says so instead of implying a
transient failure. When only some resolve, the empty ones stay `N/A`.

Keep `$${_kc:-N/A}` for the service admin exactly as it is — that one *is* seeded on the hub
(`secret/keycloak/admin`, in the allowlist), so a blank there is a real fault, not an expected
state, and must not be softened.

### M3 — `bin/get-keycloak-password`: stop putting the token in argv

Replace `_vault_get` (`:51-56`) with a call through the existing wrapper, so there is one
token-handling path in the repo instead of two:

```bash
_vault_get() {
  local _path="$1" _field="$2"
  "${REPO_ROOT}/bin/vault-exec" --namespace "${_VAULT_NS}" -- \
    vault kv get -field="${_field}" "${_path}" 2>/dev/null
}
```

If `bin/vault-exec` cannot accept this invocation as written, do **not** work around it by
re-inlining the token — use the stdin idiom directly instead:

```bash
_vault_get() {
  local _path="$1" _field="$2"
  printf '%s\n' "${_VAULT_TOKEN}" | kubectl exec -i -n "${_VAULT_NS}" \
    --context "${_KC_CONTEXT}" vault-0 -- \
    sh -c 'read -r VAULT_TOKEN; export VAULT_TOKEN; exec "$@"' sh \
    vault kv get -field="${_field}" "${_path}" 2>/dev/null
}
```

Read `bin/vault-exec` in full first and prefer the wrapper. Report in the handoff which of the
two forms you used and why.

### M4 — `bin/get-keycloak-password`: pin the hub context, and do not abort on a failed read

Add near the other defaults (`:17-20`):

```bash
: "${_KC_CONTEXT:=k3d-k3d-cluster}"
```

and change the token read (`:45-46`) to pin the context and tolerate failure so the existing
`_err` is what the operator sees:

```bash
_VAULT_TOKEN=$(kubectl get secret -n "${_VAULT_NS}" vault-root \
  --context "${_KC_CONTEXT}" -o jsonpath='{.data.root_token}' 2>/dev/null | base64 -d || true)
```

Keep the existing `if [[ -z "${_VAULT_TOKEN}" ]]` guard and its message unchanged.

### M5 — docs

- `CHANGELOG.md`, under `## [Unreleased]` → `### Fixed`, exactly:

  `- every credential \`make show-service-passwords\` prints now sits behind a \`password:\` label — the Keycloak block previously emitted four secrets on \`user:\`-prefixed lines, which defeats any consumer redacting on the \`password:\` convention; the three realm SSO users now say they are not provisioned on the hub instead of printing a bare \`N/A\`, and \`bin/get-keycloak-password\` no longer passes the Vault root token in a \`kubectl exec\` command string`

- In `docs/howto/hub-rebuild-from-gitops-vault.md`, extend the existing
  `### Credential paths after a Vault rebuild` subsection (added by `6c744a23`) with one
  sentence: `secret/keycloak/users/*` holds the realm SSO users, is written only by
  `bin/cluster-up`, is **not** in the 14-key seed allowlist, and is therefore expected to be
  absent on a rebuilt hub — `make show-service-passwords` reports it as not provisioned rather
  than as a failure.

---

## Tests

Extend `scripts/tests/bin/makefile_show_service_passwords.bats`. Reuse the existing
`show_service_passwords_target()` helper and the per-block `awk` extraction idiom already in
that file — do not invent a new one.

**Test 12 — no secret is ever emitted on a `user:` line.** This is the assertion that would
have caught the leak. Extract the whole target and assert that no line containing a shell
expansion of a credential variable also carries a `user:` label:

```bash
@test "show-service-passwords: no credential is emitted on a user: line" {
  target="$(awk '/^show-service-passwords:/,/^$/' "${MAKEFILE}")"
  run grep -nE 'echo "[^"]*user:[^"]*\$\$\{_(kc|realm_admin|dev|op|argocd|graf|prom_pass|am_pass)' <<<"${target}"
  [ "${status}" -ne 0 ]
}
```

**Test 13 — every Keycloak credential sits behind a `password:` label.** Assert the Keycloak
block contains four `password:` echoes and that `_kc`, `_realm_admin`, `_dev` and `_op` each
appear only on a `password:`-labelled line.

**Test 14 — the realm-user hint exists and the service admin is not softened.** Assert the
block defines `_kc_hint`, that `_kc_hint` is referenced by the three realm-user lines, and that
the service-admin line still uses `$${_kc:-N/A}` — i.e. the hint was **not** applied to
`_kc`. This pins the M2 asymmetry.

**Test 15 — the other four blocks are untouched.** Assert `ArgoCD`, `Grafana`, `Prometheus` and
`Alertmanager` still each emit a `user:` line and a `password:` line, and that test 6's
`:-N/A}` count for them is unchanged. This is the guard against a well-meaning "make them all
consistent" sweep.

Add to `scripts/tests/bin/identity_tools.bats`:

**Test 16 — `get-keycloak-password` never puts the token in argv:**

```bash
@test "get-keycloak-password does not pass VAULT_TOKEN in the exec command string" {
  run grep -nE 'env[[:space:]]+VAULT_TOKEN=' bin/get-keycloak-password
  [ "${status}" -ne 0 ]
}
```

**Test 17 — it pins the hub context:** assert `bin/get-keycloak-password` contains
`--context` on both the `kubectl get secret` call and whichever exec path M3 landed on.

### Mutation check (mandatory)

A new test passing does not prove it can fail. Run the suites against the pre-fix `Makefile`
and the pre-fix script:

```bash
git show HEAD:Makefile > /tmp/pre-keycloak.mk
MAKEFILE=/tmp/pre-keycloak.mk bats scripts/tests/bin/makefile_show_service_passwords.bats
```

Expected pre-fix: **tests 12, 13 and 14 `not ok`** — 12 and 13 because the secrets are on
`user:` lines, 14 because `_kc_hint` does not exist. Test 15 asserts the other four blocks are
*unchanged*, so it is **expected to pass pre-fix** — say so explicitly rather than presenting
it as evidence of anything. Test 16 likewise must be shown `not ok` against the pre-fix script
(`git show HEAD:bin/get-keycloak-password`), since that is the line being removed.

---

## Definition of Done

- M1–M5 implemented; tests 12–17 added; all gates run with **pasted real output**
- `shellcheck -x bin/get-keycloak-password` — no **error**-severity findings (CI runs
  `shellcheck -S error`; do **not** chase info-level findings on lines this spec does not touch)
- `bats scripts/tests/bin/makefile_show_service_passwords.bats scripts/tests/bin/identity_tools.bats`
- Mutation check output pasted, with test 15's expected pre-fix pass called out
- `make show-service-passwords` is **NOT** to be run — it prints live credentials. Verify the
  rendered shape with `make -n show-service-passwords` or by reading the target. (Note:
  `make -n` still executes `$(MAKE)` lines — this target has none, so it is safe.)
- Commit message first line exactly:

  `fix(makefile): label every show-service-passwords credential so redaction can find it`

- Ends with:

  ```
  Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01B9RRyT5eU8S76oXYMrLZN8
  ```

- `git push origin k3d-manager-v1.36.0`, then report `git rev-parse origin/k3d-manager-v1.36.0`

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`
- Do NOT `git add -A`; do NOT `git stash` (forbidden in this session)
- Do NOT change the 14-key allowlist in `scripts/plugins/vault.sh`
- Do NOT write, seed, rotate or repair any credential in Vault or Kubernetes
- Do NOT run `make show-service-passwords`, `bin/get-keycloak-password` without `-q`, or any
  command that prints a live credential
- Do NOT modify `scripts/lib/foundation/` or `scripts/lib/acg/`
- Do NOT reformat the ArgoCD, Grafana, Prometheus or Alertmanager blocks
- Do NOT modify files outside: `Makefile`, `bin/get-keycloak-password`,
  `scripts/tests/bin/makefile_show_service_passwords.bats`,
  `scripts/tests/bin/identity_tools.bats`, `CHANGELOG.md`,
  `docs/howto/hub-rebuild-from-gitops-vault.md`
