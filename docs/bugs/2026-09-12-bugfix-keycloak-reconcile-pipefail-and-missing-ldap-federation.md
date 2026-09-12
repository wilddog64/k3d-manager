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

For each of lines **120, 138, 160, 181, 256**, append `|| true` to the pipeline
inside the command substitution, matching the existing style at 203/235. Example
for 181:

**Old**
```bash
            | grep '"id"' | head -1 \
            | sed 's/.*"id" : "\([^"]*\)".*/\1/'
          )"
```

**New**
```bash
            | grep '"id"' | head -1 \
            | sed 's/.*"id" : "\([^"]*\)".*/\1/' || true
          )"
```

`|| true` binds to the whole pipeline, which is what is wanted: an empty result
must yield an empty string, not a dead script. Do **not** remove `pipefail` — it is
load-bearing for the rest of the script.

Preserve indentation exactly (the script is embedded in YAML; a shifted line
changes the manifest).

---

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

### B.1 — this contradicts an existing bug doc; resolve before coding

`shopping-cart-infra/docs/bugs/2026-05-15-keycloak-ldap-mappers-missing-from-reconcile.md`
asserts:

> The `partialImport` API creates the top-level LDAP `UserStorageProvider`
> component, but **does not create nested mapper sub-components**.

The live evidence above is consistent with partialImport creating **neither**. That
May 2026 claim may have been an inference rather than a verified observation, or
the component may have been lost in a later realm recreation (the hub was rebuilt
on 2026-09-11). **Do not assume either way.** First establish the fact:

1. On a scratch realm, `create partialImport` from `realm-shopping-cart.json` and
   query `get components -q type=org.keycloak.storage.UserStorageProvider`.
2. Record the answer in this spec before writing the fix.

### B.2 — the fix shape, whichever way B.1 lands

Either way the durable fix is the same in kind as the May 2026 mapper fix:
**create the component imperatively if absent**, rather than trusting the import.
Add, immediately after Defect A's `ldap_id` resolution and before the
`if [ -n "${ldap_id}" ]` branch:

- if `ldap_id` is empty, `kcadm.sh create components` with the
  `UserStorageProvider` body taken from `realm-shopping-cart.json:359` (single
  source of truth — do not retype the config; the bind credential must keep coming
  from `${LDAP_BIND_CREDENTIAL}` via the existing `render_realm` substitution, and
  must never be echoed);
- re-resolve `ldap_id`, and if it is *still* empty, `echo` a real diagnostic to
  stderr and `exit 1`. A missing user store is a genuine failure — it must fail
  loudly, not skip.

The existing mapper and group-sync code below the branch then runs unchanged.

Keep the `else` "No LDAP component found; skipping mapper setup" branch only if
B.1 shows a legitimate no-LDAP deployment mode exists. If it does not, that branch
is the bug and should be replaced by the hard failure above.

---

## Rules

- Work **only** in `shopping-cart-infra`, only in
  `identity/keycloak/keycloak-reconcile-hook-job.yaml` (plus
  `realm-shopping-cart.json` if and only if B.1 requires it).
- Create and work on `fix/keycloak-reconcile-pipefail-ldap-federation` from
  `origin/main`. Never commit to `main`.
- The script is embedded in YAML. After editing, verify the manifest still parses
  and the script still lints:
  ```bash
  python3 -c 'import yaml,sys; yaml.safe_load(open("identity/keycloak/keycloak-reconcile-hook-job.yaml"))'
  ```
  and extract the `command` string and run `shellcheck` on it (the file already
  carries `# shellcheck shell=bash` / `disable=SC2153` directives for this).
- No secret values in logs, argv, or commit messages. `LDAP_BIND_CREDENTIAL`,
  `KEYCLOAK_ADMIN_PASSWORD` and the `*_CLIENT_SECRET` vars must stay in env and
  template substitution only.
- Minimal patch. Do not reformat, reorder, or refactor the surrounding script.
- Do not touch the ArgoCD Application, and do not run a sync. Landing the manifest
  is the deliverable; the operator replays the hook.

## Definition of Done

- [ ] All five unguarded `grep`-in-command-substitution sites (120, 138, 160, 181,
      256) guarded; indentation unchanged.
- [ ] B.1 answered empirically, and the answer written into this spec.
- [ ] Absent-LDAP-component path either creates the component and re-resolves, or
      fails loudly — never silently skips.
- [ ] YAML parses; extracted script passes shellcheck with no new warnings.
- [ ] Commit message exactly:

      fix(keycloak): guard grep pipelines and create LDAP federation if absent

- [ ] Pushed to `origin/fix/keycloak-reconcile-pipefail-ldap-federation`; report
      the SHA and confirm `git rev-parse origin/<branch>` matches local.

## What NOT to Do

- Do NOT create a PR or merge.
- Do NOT commit to `main`.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT remove `set -euo pipefail`.
- Do NOT "fix" this by making the job always exit 0, or by adding
  `ignore-errors` / removing the hook. A failed user-store setup must be visible.
- Do NOT modify files outside the two named above.
- Do NOT run `argocd app sync` or mutate any live cluster resource.
