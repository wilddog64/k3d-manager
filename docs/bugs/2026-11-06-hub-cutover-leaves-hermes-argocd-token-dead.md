# Bug: hub cutover leaves the Hermes ArgoCD token dead, and nothing reports it

**Status:** LANDED `5b436578`, independent verify PASS 2026-11-06 (6 of 6 on the fix, M1 and M3 red on the parent, 5 mutants red). Live E2 open. Landed with `--allow-out-of-scope` for `scripts/tests/bin/makefile_argocd_hermes_token.bats`, which pins the changed recipe and was missing from `## Files`. The listed howto needed no change: its Aftermath re-mint step still holds.
**Priority:** P2
**Approval:** operator, 2026-11-06: "dispatch them in a batch base on dependencies or priority"
**Depends on:** `2026-11-06-hub-cutover-verify-accepts-hermes-unknown` (same function in `bin/hub-cutover`; land it first)
**Branch:** `k3d-manager-v1.43.14`
**Related:** `docs/howto/hub-rebuild-from-gitops-vault.md` (the manual Aftermath step); `docs/bugs/2026-11-06-hub-cutover-verify-accepts-hermes-unknown.md`

## Symptom

Every Hermes record on the M5 since its log began (2026-10-31T01:47:08Z) reports:

    argocd unknown ArgoCD status source unavailable: credential rejected; re-mint k3dm-hermes-argocd-token
    values_branch unknown ArgoCD status source unavailable: credential rejected; re-mint k3dm-hermes-argocd-token

A brief `ArgoCD status source unavailable` variant appears 2026-11-06T03:52Z to 04:07Z. In 1,352 cycles Hermes recorded 0 events, so for six days it could not raise an ArgoCD finding.

The Keychain item on the M5 was last modified 2026-10-30T15:54:09Z, before the rebuild that the cutover carried.

## Cause

An ArgoCD rebuild regenerates `server.secretkey`, which invalidates every earlier token. `make argocd-hermes-token` is the fix, but it is only a manual Aftermath line in the rebuild how-to. Neither `make hub-new` nor `make hub-cutover` runs or checks it, and Hermes `unknown` does not page by design.

## Second defect: the re-mint itself fails after a rotation

On 2026-11-06 the operator ran `make argocd-hermes-token` on the M5 and got `HTTP Error 401: Unauthorized` from `could not mint a token on argocd.3ai-talk.org`.

The target takes `ARGOCD_ADMIN_PASSWORD`, else `argocd-initial-admin-secret`. `admin.passwordMtime` in `argocd-secret` is 2026-11-01T12:14:02Z, and the monthly `argocd-credential-rotator` writes a new password to Vault `secret/argocd/admin`, which the target never reads. `accounts.hermes=apiKey` is set, so the account is not the cause. `bin/argocd-app-sync` already tries env, then Vault, then the initial secret, per `docs/bugs/2026-10-18-argocd-app-sync-stale-vault-admin-password.md`.

Proven 2026-11-06T15:19Z on the M5: the operator reran the target with `ARGOCD_ADMIN_PASSWORD` taken from Vault and got `stored in Keychain`, `verified: 29 applications visible to hermes`, `Hermes restarted`. The Keychain item date moved to 2026-11-06T15:19:13Z. The next Hermes record, sampled 2026-11-06T15:20:00Z, shows `argocd` and `values_branch` no longer `unknown` (`argocd healthy`, 29 applications) and no event raised; `alert_delivery` stays `unknown` for its own PyYAML cause.

## Files

- `bin/hub-cutover`
- `Makefile`
- `docs/howto/hub-rebuild-from-gitops-vault.md`
- `scripts/tests/bin/hub_cutover.bats`

## Fix direction

The token mint needs a terminal and must not run unattended, so keep it manual. Make the cutover refuse to report success while the Hermes ArgoCD credential is rejected, and print `make argocd-hermes-token` as the next step. Shared with the verify bug: resolve together. Make the target try env, then Vault, then the initial secret, as `bin/argocd-app-sync` does.

## Captured contract (Claude, 2026-11-06)

`bin/k3dm-hermes status` does not carry the ArgoCD sensor. Read it from the Hermes log, `~/Library/Logs/k3dm-hermes.log`: take the newest line beginning `{"records"`, then the record whose `sensor` is `argocd`. Captured from `m5-air.local`, 2026-11-06T15:48:11Z:

    {"sensor": "argocd", "status": "healthy", "evidence": "29 applications healthy", "sampled_at": "2026-11-06T15:48:11Z", "data": {}}

The rejected form, from the Symptom section above, has `"status": "unknown"` and evidence `ArgoCD status source unavailable: credential rejected; re-mint k3dm-hermes-argocd-token`. A missing log or missing record is reported as not verified, never as a pass. Only `credential rejected` fails with the re-mint step.

For M3, copy the env, Vault, initial-secret order from `bin/argocd-app-sync` rather than inventing another one.

## Acceptance

```yaml
must:
  - id: M1
    text: "hub-cutover verification fails and names make argocd-hermes-token when the Hermes argocd sensor reports credential rejected."
  - id: M2
    text: "Verification passes this check when the argocd sensor reports healthy or degraded with a working credential."
  - id: M3
    text: "make argocd-hermes-token mints a token when the initial admin secret is stale and the Vault copy is current."
must_not:
  - id: N1
    text: "The check does not mint, store or print a token (paired with M1)."
  - id: N2
    text: "The target does not print the admin password or the Vault token, and does not pass either as a command argument (paired with M3)."
evidence:
  - {id: E1, proves: [M1, M2, M3, N1, N2], kind: offline, text: "BATS with a stubbed Hermes status and stub ArgoCD and Vault endpoints; M1 and M3 red on the pre-fix commit; N1 and N2 red by a mutant."}
  - {id: E2, proves: [M2], kind: live, text: "After make argocd-hermes-token on the M5, the Hermes log shows argocd no longer unknown for credential rejected."}
interface:
  - "bin/hub-cutover --verify"
  - "env: HOME, HUB_OLD_HOST, HUB_CUTOVER_STATE_DIR, PATH (stubs)"
```

## Verifier notes (2026-11-06, not failures)

- With Vault unreachable, the target falls back to the initial secret without saying so. If that secret is stale, the error reads `could not mint a token` and does not name Vault.
- The stubbed `degraded` and `unknown / connection timed out` Hermes log lines, and the `bin/k3dm-hermes status` shape, are the verifier's own, not real captures. Only the healthy and rejected lines were captured. Check them against the M5 log during E2.
