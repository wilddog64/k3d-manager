# Bug: `keycloak-realm-reconcile` dies on `pipefail`, and the realm has no LDAP federation

**Filed:** 2026-09-12
**Spec repo:** `k3d-manager` (this file)
**Work repo:** `shopping-cart-infra` — `identity/keycloak/keycloak-reconcile-hook-job.yaml`
**Branch (work repo):** `fix/keycloak-reconcile-pipefail-ldap-federation` — create from `origin/main`, never commit to `main`
**Incident:** `docs/issues/2026-09-11-status-warnings-hub-vault-eso-breakage.md` Finding 11

---

## Summary

`shopping-cart-identity` has sat at `operationState.phase=Failed` since
`2026-09-11T01:54:41Z` because its PostSync hook Job `keycloak-realm-reconcile`
exits 1. The Application still reports `Synced/Healthy` — see Finding 10 for why
that hides the failure and blocks self-heal.

There are **two separate defects**. Defect A is unambiguous and mechanical.
Defect B is a design question that must be answered before it is coded, and it
contradicts an assumption written into an earlier bug doc.

---

## Defect A — `set -e` + `pipefail` kills the script at an unmatched `grep`

The hook script runs under `/bin/bash -euo pipefail` (`:33-36`). The pods fail with
exit 1, **no error output**, and a *success* line as the last thing logged:

```
browser-with-conditional-otp flow already exists; skipping creation
browser-with-conditional-otp flow activated
```

The next statement (`:175-186`) is:

```bash
ldap_id="$(
  /opt/keycloak/bin/kcadm.sh get components \
    -r "${KC_REALM}" \
    -q type=org.keycloak.storage.UserStorageProvider \
    --fields id \
    2>/dev/null \
  | grep '"id"' | head -1 \
  | sed 's/.*"id" : "\([^"]*\)".*/\1/'
)"

if [ -n "${ldap_id}" ]; then
  ...
else
  echo "No LDAP component found; skipping mapper setup"
fi
```

Live, the query returns an empty array:

```
$ kcadm.sh get components -r shopping-cart \
    -q type=org.keycloak.storage.UserStorageProvider --fields id,name
[ ]
```

So `grep '"id"'` matches nothing and exits 1. Under `pipefail` the pipeline returns
1; because this is a plain assignment, `set -e` terminates the script immediately.
**The `else` branch that exists specifically to handle "no LDAP component" is
unreachable** — the script dies before the `if` is evaluated. The guard is dead
code.

### A.1 — the same hazard exists at four more sites

Any `grep` in a command substitution under `pipefail` is the same trap. Audit of
the file:

| Line | Assignment | Guarded? |
|---|---|---|
| 120 | `_otp_subflow_exec_id` | **NO** |
| 138 | `_role_cond_id` | **NO** |
| 160 | `_otp_form_id` | **NO** |
| 181 | `ldap_id` | **NO** |
| 203 | `existing` (`grep -c`) | yes — `\|\| true` |
| 235 | `_gm_existing` (`grep -c`) | yes — `\|\| true` |
| 256 | `_gm_id` | **NO** |
| 102 | `if ... \| grep -q` | n/a — inside `if`, `set -e` suspended |

The three flow-execution sites (120/138/160) each already have an explicit
diagnostic that is **also unreachable** for this reason:

```bash
if [[ -z "${_otp_subflow_exec_id}" ]]; then
  echo "ERROR: could not resolve otp-conditional-subflow execution ID" >&2; exit 1
fi
```

The script can never print that message. It dies silently instead. Fixing only
line 181 leaves four latent silent-death sites, so fix all five.

### A.2 — required change

Append ` || true` to the **last line of the pipeline** inside each of the five
unguarded command substitutions, matching the existing guarded style at 203/235
(`| grep -c '"id"' || true`). `|| true` binds to the whole pipeline, which is what
is wanted: an empty result must yield an empty string, not a dead script.

The five lines are given literally below with their exact leading whitespace.
Indentation must be preserved byte-for-byte — the script is embedded in YAML, so a
shifted line changes the manifest.

**1. line 120** (14 spaces)
```bash
              | grep "otp-conditional-subflow" | cut -d',' -f1 | tr -d '"'
```
→
```bash
              | grep "otp-conditional-subflow" | cut -d',' -f1 | tr -d '"' || true
```

**2. line 138** (14 spaces)
```bash
              | grep "conditional-user-role" | cut -d',' -f1 | tr -d '"'
```
→
```bash
              | grep "conditional-user-role" | cut -d',' -f1 | tr -d '"' || true
```

**3. line 160** (14 spaces)
```bash
              | grep "auth-otp-form" | cut -d',' -f1 | tr -d '"'
```
→
```bash
              | grep "auth-otp-form" | cut -d',' -f1 | tr -d '"' || true
```

**4. line 182** (12 spaces — the `ldap_id` assignment opens at 181)
```bash
            | sed 's/.*"id" : "\([^"]*\)".*/\1/'
```
→
```bash
            | sed 's/.*"id" : "\([^"]*\)".*/\1/' || true
```

**5. line 257** (14 spaces — the `_gm_id` assignment opens at 256)
```bash
              | sed 's/.*"id" : "\([^"]*\)".*/\1/'
```
→
```bash
              | sed 's/.*"id" : "\([^"]*\)".*/\1/' || true
```

Sites 4 and 5 are byte-identical apart from two leading spaces. Do **not** use a
global replace for them — match on the full line including indentation, or edit by
line number, and confirm afterwards that both lines changed and nothing else did.

Do **not** remove `pipefail` — it is load-bearing for the rest of the script.

Once guarded, the three `ERROR: could not resolve ... execution ID` diagnostics at
121-123 / 139-141 / 161-163 become reachable for the first time. Leave them exactly
as they are; they are correct, they were merely unreachable.

## Defect B — the realm has no LDAP user federation and no users

`|| true` alone would turn a crashing job into a **green job that silently
configures nothing**. That is the same reported-success-over-real-failure pattern
as Finding 10 and Finding 12, and it must not be the whole fix.

Verified live against the `shopping-cart` realm (Keycloak 24.0):

```
users                        -> [ ]          (zero users)
UserStorageProvider components -> [ ]        (no LDAP federation)
all components by type       -> 4x KeyProvider, 8x ClientRegistrationPolicy only
```

Yet:

- `identity/keycloak/realm-shopping-cart.json:359` **does** declare
  `components["org.keycloak.storage.UserStorageProvider"] = [{ name: "ldap",
  providerId: "ldap" }]`, pointing at `ldap.identity.svc.cluster.local`.
- The `ldap` pod is **Running** in namespace `identity` (24h uptime).
- `partialImport` exited **0** on this run — the script's
  `"Warning: partialImport exited N"` line does not appear in the logs.
- Nothing else in the repo creates this component:
  `grep -rn UserStorageProvider` outside `docs/` matches only the realm JSON and
  the reconcile job's *read*.

So nobody can authenticate against this realm at all. This is the most likely real
origin of the standing Keycloak smoke-user and frontend-login warnings
(Findings 4/5) — they have been triaged as credential/seed problems, but the realm
has no user store.

### B.1 — this contradicts an existing bug doc (open question, NOT a blocker)

`shopping-cart-infra/docs/bugs/2026-05-15-keycloak-ldap-mappers-missing-from-reconcile.md`
asserts:

> The `partialImport` API creates the top-level LDAP `UserStorageProvider`
> component, but **does not create nested mapper sub-components**.

The live evidence above is consistent with partialImport creating **neither**. That
May 2026 claim may have been an inference rather than a verified observation, or
the component may have been lost in a later realm recreation (the hub was rebuilt
on 2026-09-11).

**Decision 2026-09-12 — do not block on this.** Settling it empirically requires
creating a scratch realm on the live Keycloak, which is an operator action, not an
implementation action. It is deliberately **out of scope for this fix** and is
tracked as an open question in the incident doc. The reason it is safe to defer:
B.2's shape is identical either way. "Resolve the component; create it if absent;
fail loudly if it is still absent" is correct whether partialImport creates the
component, creates it sometimes, or never creates it. If it does create it, the
new code is a no-op on a healthy realm.

**Consequence for the implementer:** treat "partialImport may or may not create the
component" as the contract. Do not add code that depends on either answer, and do
not attempt to verify it against a live cluster.

### B.2 — the fix (verified recipe)

**Container toolchain constraint — verified 2026-09-12.** `quay.io/keycloak/keycloak:24.0`
ships **no `jq`, no `python`/`python3`, and no `awk`**. Only `sed` is available:

```
$ docker run --rm --entrypoint sh quay.io/keycloak/keycloak:24.0 -c 'command -v jq python3 awk sed'
jq       MISSING
python3  MISSING
awk      MISSING
sed      /usr/bin/sed
```

So the component body must be lifted out of the rendered realm JSON with `sed`
alone. Do not add a JSON tool, an initContainer, or a second image.

The extraction below was run against the real `realm-shopping-cart.json` and its
output parses as valid JSON with all **24** `config` entries and the
`bindCredential` value intact. Read it from
`/tmp/realm-shopping-cart.rendered.json` (the output of `render_realm`), **not**
from `/realm/realm-shopping-cart.json`, so the credential is already substituted.

`providerType` must be injected because the realm-file form encodes it as the map
key. `parentId` must be **omitted** — Keycloak defaults a component's `parentId` to
the realm when it is absent, and the realm's internal id is not the realm name.

Insert this immediately after Defect A's `ldap_id` resolution and before the
existing `if [ -n "${ldap_id}" ]; then` line, at the same indentation as that line:

```bash
          if [ -z "${ldap_id}" ]; then
            echo "No LDAP UserStorageProvider in realm ${KC_REALM}; creating it from the rendered realm"
            _usp_file="/tmp/ldap-userstorageprovider.json"
            sed -n '/^    "org\.keycloak\.storage\.UserStorageProvider": \[$/,/^    \]$/p' \
              /tmp/realm-shopping-cart.rendered.json \
              | sed -e '1d' -e '$d' \
                    -e 's|^        "providerId": "ldap",$|        "providerId": "ldap",\n        "providerType": "org.keycloak.storage.UserStorageProvider",|' \
              > "${_usp_file}"
            if [ ! -s "${_usp_file}" ]; then
              echo "ERROR: could not extract the LDAP UserStorageProvider block from the rendered realm" >&2
              exit 1
            fi
            /opt/keycloak/bin/kcadm.sh create components \
              -r "${KC_REALM}" -f "${_usp_file}" >/dev/null
            rm -f "${_usp_file}"
            ldap_id="$(
              /opt/keycloak/bin/kcadm.sh get components \
                -r "${KC_REALM}" \
                -q type=org.keycloak.storage.UserStorageProvider \
                --fields id \
                2>/dev/null \
              | grep '"id"' | head -1 \
              | sed 's/.*"id" : "\([^"]*\)".*/\1/' || true
            )"
          fi

          if [ -z "${ldap_id}" ]; then
            echo "ERROR: realm ${KC_REALM} still has no LDAP UserStorageProvider after create attempt; refusing to continue with no user store" >&2
            exit 1
          fi
```

Notes on that block:

- `${_usp_file}` transiently holds the bind credential. It is written by
  redirection (never echoed to stdout) and `rm -f`'d immediately after use. This
  adds no new exposure class: `/tmp/realm-shopping-cart.rendered.json` in the same
  container already holds the same secret for the same reason.
- The two `sed` expressions are anchored to 4-space and 8-space indentation in
  `realm-shopping-cart.json`. That is why `realm-shopping-cart.json` must **not** be
  reformatted by this change — reindenting it silently breaks the extraction. The
  `[ ! -s ]` guard is what turns such a break into a loud failure instead of a
  skipped user store.
- The re-resolve deliberately repeats the query rather than factoring it into a
  helper — a helper would be a larger diff than the duplication saves.

**The `else` branch.** With the hard failure above, the existing
`else echo "No LDAP component found; skipping mapper setup"` is unreachable. Do
**not** dedent and unwrap the ~100-line `if [ -n "${ldap_id}" ]` body to remove it
— that is a large diff for no behavioural gain. Instead leave the `if` wrapper in
place and replace only the `else` body with:

```bash
          else
            echo "ERROR: LDAP component id unexpectedly empty" >&2
            exit 1
          fi
```

so that if the invariant is ever broken by a later edit, it fails loudly rather
than silently skipping every mapper.

### B.3 — known limitation: create-if-absent is not reconcile-to-desired

The B.2 fix creates the component **only when it is absent**. It does not update an
existing component whose live config has drifted from the realm file. That is
deliberate — updating in place is a larger change and needs its own decision about
whether the hook is allowed to mutate a working federation — but it has a concrete
consequence that the operator must know about.

There is an **unmerged** branch in `shopping-cart-infra`,
`fix/sso-federate-openldap0` (`d02e6622`, 2026-09-04, not an ancestor of
`origin/main`), which rewrites this exact LDAP component to retire the osixia
`ldap` service in favour of `openldap-0` (the user's "Option B" decision):

```
rdnLDAPAttribute   uid                                    -> cn
connectionUrl      ldap://ldap.identity.svc...            -> ldap://openldap.identity.svc...
usersDn            ou=users,dc=shopping-cart,dc=local     -> ou=users,dc=home,dc=org
bindDn             cn=admin,dc=shopping-cart,dc=local     -> cn=ldap-admin,dc=home,dc=org
```

The fix itself is **config-agnostic** — it extracts whatever the rendered realm
file declares at run time, so it creates the correct component under either
branch, and nothing about it is hardcoded to osixia. The two branches also touch
disjoint files, so they will not conflict in git.

**But the landing order matters.** If this fix lands first, the next sync creates
an osixia-pointed federation. When `fix/sso-federate-openldap0` later lands, the
realm file changes but the component already exists, so create-if-absent does
nothing and the live federation stays pointed at the retired directory —
`partialImport` does not reliably update it either (that is the whole premise of
this bug). The operator would have to delete the component by hand.

Recommended order: land `fix/sso-federate-openldap0` first, then this fix. If this
fix lands first instead, deleting the stale component once is the remedy.

Follow-up (out of scope here): decide whether the hook should reconcile an existing
component's config toward the realm file, which would remove this ordering
constraint entirely.

## Rules

- Work **only** in `shopping-cart-infra`, only in
  `identity/keycloak/keycloak-reconcile-hook-job.yaml`. Read
  `realm-shopping-cart.json` for the component body, but do not modify it.
- Create and work on `fix/keycloak-reconcile-pipefail-ldap-federation` from
  `origin/main`. Never commit to `main`.
- The script is embedded in YAML (`spec.template.spec.containers[0].command[4]`,
  a `- |` block under `command: [/bin/bash, -euo, pipefail, -c]`). After editing,
  run **both** gates and paste their output:

  ```bash
  python3 -c 'import yaml; yaml.safe_load(open("identity/keycloak/keycloak-reconcile-hook-job.yaml"))' \
    && echo "YAML OK"

  python3 -c '
  import yaml
  d = yaml.safe_load(open("identity/keycloak/keycloak-reconcile-hook-job.yaml"))
  open("/tmp/hook.sh","w").write(d["spec"]["template"]["spec"]["containers"][0]["command"][4])
  '
  shellcheck -s bash /tmp/hook.sh
  ```

  The file already carries `# shellcheck shell=bash` / `disable=SC2153` directives
  for this. Record the shellcheck warning count before and after your change — the
  gate is **no new warnings**, not zero warnings.
- No secret values in logs, argv, or commit messages. `LDAP_BIND_CREDENTIAL`,
  `KEYCLOAK_ADMIN_PASSWORD` and the `*_CLIENT_SECRET` vars must stay in env and
  template substitution only.
- Minimal patch. Do not reformat, reorder, or refactor the surrounding script.
- Do not touch the ArgoCD Application, and do not run a sync. Landing the manifest
  is the deliverable; the operator replays the hook.

## Definition of Done

- [ ] All five unguarded `grep`-in-command-substitution pipelines guarded with
      `|| true` (lines 120, 138, 160, 182, 257); indentation unchanged byte-for-byte.
- [ ] `git diff --stat` shows exactly one file changed.
- [ ] Absent-LDAP-component path creates the component, re-resolves, and fails
      loudly if still empty — never silently skips.
- [ ] The `else` "No LDAP component found; skipping mapper setup" skip is gone.
- [ ] `YAML OK` printed; extracted script's shellcheck warning count is unchanged
      from `origin/main` (paste both counts).
- [ ] Commit message exactly:

      fix(keycloak): guard grep pipelines and create LDAP federation if absent

- [ ] Committed on `fix/keycloak-reconcile-pipefail-ldap-federation` and pushed;
      `git rev-parse origin/<branch>` matches local.

      **Note for a sandboxed `codex exec` dispatch:** `.git` writes are denied in
      that sandbox, so Codex cannot satisfy this item. Codex leaves the edit in the
      working tree and reports the diff; Claude reviews, commits with the exact
      message above, and pushes.

## What NOT to Do

- Do NOT create a PR or merge.
- Do NOT commit to `main`.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT remove `set -euo pipefail`.
- Do NOT "fix" this by making the job always exit 0, or by adding
  `ignore-errors` / removing the hook. A failed user-store setup must be visible.
- Do NOT modify any file other than `identity/keycloak/keycloak-reconcile-hook-job.yaml`.
- Do NOT run `argocd app sync` or mutate any live cluster resource.
- Do NOT attempt to answer B.1 — no scratch realms, no live `kcadm.sh` calls.
