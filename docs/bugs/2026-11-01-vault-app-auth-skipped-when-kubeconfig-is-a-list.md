# Bug: acg-up skips app-cluster Vault auth when `KUBECONFIG` lists several files

**Status:** FIXED — `10381790` (Codex; Claude review, independent verify); E2 (live) pending
**Fix commit:** 10381790
**Priority:** P3
**Severity:** low — `configure_vault_app_auth_for_context` warns and returns 0, so the app cluster gets no Vault Kubernetes auth role; ESO still syncs through the vault-token ClusterSecretStore (all 10 ExternalSecrets `True` after job `cdff3cea`)
**Approval:** operator, 2026-11-01 ("let's get the reminding items complete so we can create-pr"; found in the session's acg-up live run)
**Filed:** 2026-11-01
**Detected by:** Claude, reading job `cdff3cea` output on the M5
**Affected:** `scripts/plugins/vault.sh` (`configure_vault_app_auth_for_context`, ~lines 2000-2030)
**Branch:** `k3d-manager-v1.43.13`

## Observed failure

Job `cdff3cea` (/cluster-up on the M5, 2026-11-01) logged
`WARN: [vault] no API server for context 'ubuntu-k3s' — skipping app-cluster Vault auth`, although the same run had just
registered `ubuntu-k3s` with ArgoCD and `kubectl config get-contexts` lists it.

## Root cause

The function builds `kctl=(kubectl --kubeconfig "${app_kubeconfig}")` with `app_kubeconfig` defaulting to
`${KUBECONFIG}`. The webhook's `KUBECONFIG` is a colon-separated list of three files, and `--kubeconfig` accepts one
file only: on the M5, `kubectl --kubeconfig "<the list>" config view` exits 1, while `KUBECONFIG="<the list>" kubectl
config view` returns the `ubuntu-k3s` server. The `2>/dev/null` hides the error and the empty server takes the skip
branch.

## Fix

When the kubeconfig argument contains `:`, pass it as `KUBECONFIG=<value>` in the environment of each `kubectl`
call instead of `--kubeconfig`; a single path keeps `--kubeconfig`. Leave the skip-and-warn branch for a context that
really has no server.

## Files

- `scripts/plugins/vault.sh`
- `scripts/tests/plugins/vault.bats` (or the existing suite that covers this function)
- `CHANGELOG.md`

## What NOT to do

- Do not change `APP_VAULT_AUTH_REQUIRED` semantics or the warning for a missing context.
- Tests use a scratch HOME and a stub `kubectl` that rejects a `--kubeconfig` value containing `:` the way real
  kubectl does (captured on the M5, 2026-11-01: exit 1) and records its argv and `KUBECONFIG`.

## Acceptance

```yaml
must:
  M1: with KUBECONFIG=a:b:c and the context in one of the files, the function resolves the server and proceeds to configure auth
  M2: with a single-file kubeconfig, kubectl still receives --kubeconfig <file> (paired positive control)
must_not:
  N1: a colon-separated value is never passed to --kubeconfig
  N2: a context with no server still warns and returns 0 (1 when APP_VAULT_AUTH_REQUIRED=true)
evidence:
  E1:
    proves: [M1, M2, N1, N2]
    kind: offline
    intent: You will see BATS with a stub kubectl show the list case reach the configure path (red on the pre-fix code, which warns), the single-file case use --kubeconfig, and the missing-context case keep its warning and return codes.
    what: bats on the vault suite
  E2:
    proves: [M1]
    kind: live
    intent: You will see the next /cluster-up on the M5 log no "no API server for context 'ubuntu-k3s'" warning.
    what: Claude reading the webhook job output on the M5
interface:
  - configure_vault_app_auth_for_context <context> [kubeconfig]
  - env KUBECONFIG, APP_VAULT_AUTH_REQUIRED
```

## Verification (2026-11-01, Claude)

- Landed as `10381790` through `make codex-land`; the ledger records `land` and `verify` events for slug `2026-11-01-vault-app-auth-skipped-when-kubeconfig-is-a-list`.
- Offline evidence: worker bats (ok 27-29) and the land test passed (rc 0); fast gate passed. Independent black-box verifier (Sonnet, tests written from the Acceptance block only): PASS; M1/N1 red on pre-fix code.
- Errors seen: the worker's version failed the pre-commit `_agent_audit` if-count threshold; Claude rewrote the selection as a `case` and both test sets still passed.
- E2 (live) pending: the next acg-up shows `configure_vault_app_auth_for_context` create the app-cluster role.
