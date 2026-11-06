# Bug: hub cutover leaves the Hermes ArgoCD token dead, and nothing reports it

**Status:** OPEN — observed 2026-11-06 on the M5; re-mint given to the operator, not yet confirmed
**Priority:** P2
**Approval:** pending
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

## Files

- `bin/hub-cutover`
- `docs/howto/hub-rebuild-from-gitops-vault.md`
- `scripts/tests/bin/hub_cutover.bats`

## Fix direction

The token mint needs a terminal and must not run unattended, so keep it manual. Make the cutover refuse to report success while the Hermes ArgoCD credential is rejected, and print `make argocd-hermes-token` as the next step. Shared with the verify bug: resolve together.

## Acceptance

```yaml
must:
  - id: M1
    text: "hub-cutover verification fails and names make argocd-hermes-token when the Hermes argocd sensor reports credential rejected."
  - id: M2
    text: "Verification passes this check when the argocd sensor reports healthy or degraded with a working credential."
must_not:
  - id: N1
    text: "The check does not mint, store or print a token (paired with M1)."
evidence:
  - {id: E1, proves: [M1, M2, N1], kind: offline, text: "BATS with a stubbed Hermes status; M1 red on the pre-fix commit; N1 red by a mutant."}
  - {id: E2, proves: [M2], kind: live, text: "After make argocd-hermes-token on the M5, the Hermes log shows argocd no longer unknown for credential rejected."}
interface:
  - "bin/hub-cutover --verify"
  - "env: HOME, HUB_OLD_HOST, HUB_CUTOVER_STATE_DIR, PATH (stubs)"
```
