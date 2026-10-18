# Bug: the Vault copy of the ArgoCD admin password is never revalidated, so `make show-service-passwords` shows a dead password after a hub rebuild

**Filed:** 2026-10-18 (Claude, from the operator's failed ArgoCD UI login)
**Status:** FIXED — awaiting operator E3 run
**Priority:** P2 — the ArgoCD UI login is broken with the documented credential; a workaround exists (read `argocd-initial-admin-secret` directly)
**Severity:** medium
**Approval:** approved — operator, 2026-10-18: "we should fix this issue so file it and send to codex"
**Branch:** `k3d-manager-v1.43.5`
**Release:** v1.43.5
**Component:** `Makefile` (`show-service-passwords`), `scripts/plugins/hub_recovery.sh` (`_hub_recovery_mirror_argocd_admin`)
**Fix commit:** `b1a0b575` (Codex), `3aee39e6` (Claude: temp-file cleanup), `07298804` (Claude: make-escaped jq variables)
**Related:** `2026-10-18-argocd-app-sync-stale-vault-admin-password.md` (same stale value, fixed in `bin/argocd-app-sync` only); `2026-09-13-hub-restore-argocd-admin-vault-mirror-missing.md` (introduced the mirror)

## Symptom

2026-10-18: the operator copied the ArgoCD password from `make show-service-passwords` into
`https://argocd.3ai-talk.org` as `admin` and got "Invalid username or password". The Keycloak
credential from the same output worked.

## Root cause

The hub was rebuilt on 2026-10-16, which generated a new ArgoCD admin password
(`argocd-initial-admin-secret`, created 2026-10-16T02:11:10Z = `admin.passwordMtime`). Vault
`secret/argocd/admin` still holds the pre-rebuild value.

1. **The mirror never replaces a value.** `_hub_recovery_mirror_argocd_admin`
   (`scripts/plugins/hub_recovery.sh:181`) returns 0 as soon as `vault kv get ... argocd/admin` finds a
   password. It never checks that ArgoCD accepts it, so the stale value survived the rebuild.
2. **The display trusts Vault blindly.** `show-service-passwords` (`Makefile`, the `_argocd=` block)
   prints the Vault value and falls back to `argocd-initial-admin-secret` only when Vault is empty.

Vault cannot simply lose to the cluster secret: `argocd-credential-rotator` (monthly, writes
`secret/argocd/admin`) makes Vault the current source and the initial secret stale after a rotation.
The source that is correct is whichever one ArgoCD accepts.

## Fix

Both places choose the password by asking ArgoCD, using
`POST ${url}/api/v1/session` with `{"username":"admin","password":...}` from a `mktemp` payload file
(never on a command line). Send `User-Agent: k3dm-hub-recovery/1` as the mirror does (Cloudflare
blocks the default curl agent). HTTP 200 = accepted.

- **F1. Mirror (`_hub_recovery_mirror_argocd_admin`).**
  - When Vault has a password, test it. If accepted, return 0 (unchanged behaviour).
  - If rejected, continue into the existing path: read `argocd-initial-admin-secret`, test it, and if
    accepted `vault kv put` it. Log `[hub-recovery] Vault ArgoCD admin password rejected by ArgoCD;
    replacing it from argocd-initial-admin-secret`.
  - If ArgoCD is unreachable (HTTP 000 or 5xx) while testing the Vault value, keep the value and
    return 0 with a `_warn`. Do not overwrite on an unreachable server.
- **F2. Display (`show-service-passwords`).** Collect the Vault and initial-secret candidates, then
  print the first one ArgoCD accepts, Vault first.
  - If Vault was rejected and the initial secret accepted, print a second line
    `    note:     Vault secret/argocd/admin is stale (rejected by ArgoCD)`.
  - If neither is accepted, or ArgoCD is unreachable, print the Vault value (else the initial secret)
    followed by `    note:     not verified against ArgoCD`.
  - The ArgoCD URL comes from a variable defaulting to `https://argocd.3ai-talk.org`, overridable for
    tests. The target stays read-only: it never writes to Vault.
- Do not touch the Grafana or Keycloak blocks.

### Operator step after merge

Run `make show-service-passwords` and log in with what it prints. Vault's copy is corrected by the
next hub recovery (F1), or now by writing the printed value to `secret/argocd/admin`.

## Acceptance

```yaml
must:
  - id: M1
    text: When ArgoCD rejects the Vault password and accepts the initial-secret password, show-service-passwords prints the initial-secret password plus a stale-Vault note.
  - id: M2
    text: When ArgoCD accepts the Vault password, show-service-passwords prints the Vault password with no note (rotated-password case).
  - id: M3
    text: When the Vault password is rejected and the initial-secret password accepted, the hub-recovery mirror writes the initial-secret password to Vault secret/argocd/admin.
  - id: M4
    text: When ArgoCD accepts the Vault password, the mirror writes nothing to Vault.
must_not:
  - id: N1
    text: show-service-passwords must not print a password ArgoCD rejected while another candidate is accepted (red on pre-fix).
  - id: N2
    text: The mirror must not keep a Vault password ArgoCD rejected when the initial secret is accepted (red on pre-fix).
  - id: N3
    text: The mirror must not overwrite Vault when ArgoCD is unreachable.
  - id: N4
    text: No password appears on a command line, in set -x output, or in any log line.
evidence:
  - id: E1
    proves: [M1, M2, N1, N4]
    kind: offline
    text: scripts/tests/bin/makefile_show_service_passwords.bats with stubbed kubectl and curl on PATH; N1 red on the pre-fix Makefile.
  - id: E2
    proves: [M3, M4, N2, N3, N4]
    kind: offline
    text: scripts/tests/plugins/hub_recovery.bats with stubbed _kubectl and curl; N2 red on pre-fix hub_recovery.sh.
  - id: E3
    proves: [M1]
    kind: live
    text: the operator runs make show-service-passwords against the rebuilt hub, sees the stale-Vault note, and logs in to the ArgoCD UI with the printed password.
interface:
  - make show-service-passwords (env override for the ArgoCD URL)
  - _hub_recovery_mirror_argocd_admin <hub_context> (scripts/plugins/hub_recovery.sh)
```

## Definition of Done

- [ ] F1, F2; tests in the two BATS files above; N1, N2 red against the pre-fix source.
- [ ] `docs/guides/` or `docs/howto/` page that documents `show-service-passwords` notes that the ArgoCD
      password is checked against ArgoCD and when the stale-Vault note appears.
- [ ] Commit: `fix(argocd): pick the ArgoCD admin password that ArgoCD accepts`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`.
- Do NOT contact a real ArgoCD, Vault or cluster in tests.
- Do NOT edit `scripts/lib/foundation/`, or the Grafana/Keycloak blocks of `show-service-passwords`.

## Verification log

- 2026-10-18: Codex `b1a0b575`; Claude reviewed the diff against F1/F2. One defect found and fixed in
  `3aee39e6`: the mirror's RETURN trap captured `${payload_file:-}` while it was still empty, so the two
  JSON payloads holding the admin password were never removed from `TMPDIR`. A new test ("removes its
  password temp files") is red on `b1a0b575` and green after. Both suites 71/71; against `9577850c`
  N1 (test 62) and N2 (test 47) fail. shellcheck clean at warning level.
- 2026-10-18: operator's first live run failed with `jq: error: sername/0 is not defined`. Make expanded
  `$username`/`$password` in the recipe's jq filter. The curl stub accepted any payload, so the tests
  missed it. Fixed in `07298804` (`$$username`, `$$password`); the stub now rejects a payload that lacks
  `username: admin` and a password, and tests 5–6 are red against the broken Makefile.
