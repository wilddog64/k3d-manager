# Plan: Hermes knows when Vault is sealed (v1.44.2)

**Filed:** 2026-11-17
**Branch:** `k3d-manager-v1.44.2`
**Status:** OPEN
**Covers:** `docs/bugs/2026-10-12-hermes-has-no-vault-sealed-sensor.md` (stage A) and
`docs/bugs/2026-11-17-hermes-r7-signing-restore-offered-when-vault-sealed.md` (stage B)
**Approval:** operator, 2026-11-17 — "one plan covering both bugs, in v1.44.2"
**Risk:** medium (Hermes repair gating and Slack card text; no cluster writes added)

## Why one plan

Stage B reads the `vault_seal` record that stage A creates, and both stages edit
`scripts/lib/hermes/` and `scripts/tests/hermes/test_hermes.py`. One dispatch keeps to the
one-dispatch-per-file rule and lets the stage B tests use the real stage A sensor.

## What to do

Do stage A, then stage B, in one working tree. The bug docs hold the detailed spec; follow each one's
`## Fix`, `## Files`, `## Tests` and `## What NOT to Do` exactly.

- **Stage A:** the sensor bug doc. Notes added 2026-11-17: the debounce is
  `max(0, threshold - 1)` like `hostnet_drift`, and test 8 asserts that no repair command unseals
  Vault. It does not assert that no repair reads `vault_seal`.
- **Stage B:** the r7 bug doc, Fix 1–5. Fix 1 also adds `vault_seal` to r7's `reads` and `_evidence`
  tuples.

Combined Files: the union of both Files tables. CHANGELOG `[Unreleased]` gets `### Added` (sensor) and
`### Fixed` (r7, cards, resolved message, alert diagnosis).

## What NOT to Do

- Do NOT add any unseal path, Vault API call, `kubectl exec` or Secret read anywhere in Hermes or the
  webhook.
- Do NOT change sensors other than adding `vault_seal`, or change the exporter or dashboard JSON.
- Do NOT add a Claude API provider (that is a feature, logged in `docs/ideas.md`).
- Do NOT commit, push or open a PR. Claude verifies and commits.
- Do NOT modify files outside the combined Files list.

## Gates

`pytest scripts/tests/hermes/test_hermes.py scripts/tests/bin/test_webhook_analyze_routing.py`,
`make test-pytest`. Every mutation listed in either bug doc must turn its test red. Report each
mutation and the test that caught it.

## Acceptance

```yaml
must:
  - id: M1
    text: a vault_seal sensor reports healthy, degraded (from the second sealed cycle) or unknown from the Vault pod labels alone, and Hermes runs it every cycle
  - id: M2
    text: r7 is proposed only when Vault is unsealed and at most 2 ExternalSecrets fail, and approve() refuses it if that stops holding
  - id: M3
    text: while Vault is sealed, the incident card leads with "Root cause: Vault sealed" and no LLM is called for it
  - id: M4
    text: every repair card carries a "Recommended: Approve — <when>. If you do nothing: <what>." line
  - id: M5
    text: a resolved incident names each withdrawn proposal and says nothing needs approving
  - id: M6
    text: an alert diagnosis during a Vault seal names Vault and skips the LLM; otherwise the LLM sees Vault and ClusterSecretStore state
must_not:
  - id: N1
    text: the vault_seal sensor reports healthy when the vault-sealed label is missing, or is not debounced — red today (no sensor exists)
  - id: N2
    text: r7 is proposed for the 2026-11-17 01:09Z records (19/20 failing, Vault sealed) — red today
  - id: N3
    text: Hermes or the alert diagnosis execs into a pod, calls the Vault API, reads a Secret, or carries any unseal command
evidence:
  - id: E1
    proves: [M1, N1, N3]
    kind: offline
    command: pytest scripts/tests/hermes/test_hermes.py -k "vault_seal"
    intent: Hermes notices a sealed Vault from read-only pod labels, and has no way to unseal it.
  - id: E2
    proves: [M2, N2]
    kind: offline
    command: pytest scripts/tests/hermes/test_hermes.py -k "r7"
    intent: During a Vault outage Hermes no longer offers the cosign repair, and still offers it when only the cosign key is broken.
  - id: E3
    proves: [M3, M4, M5]
    kind: offline
    command: pytest scripts/tests/hermes/test_hermes.py -k "root_cause or recommended or resolved"
    intent: From a phone, each Slack card says what is wrong, whether to press Approve, and when it is safe to ignore.
  - id: E4
    proves: [M6, N3]
    kind: offline
    command: pytest scripts/tests/bin/test_webhook_analyze_routing.py -k "vault"
    intent: Alert diagnoses blame a sealed Vault instead of inventing an app problem, using read-only checks.
  - id: E5
    proves: [M1]
    kind: live
    command: after promote, the next Hermes cycle shows a vault_seal row reading "unsealed: 1 pod(s)" on the Hermes Status dashboard (Claude, read-only)
    intent: You can see on the dashboard that Vault is unsealed, not guess it from ESO.
  - id: E6
    proves: [M1, M3, M5, M6]
    kind: live
    command: at the next planned Vault restart (operator go), vault_seal goes degraded, the Slack incident starts with "Root cause: Vault sealed", offers no r7, and the resolved message follows after the watchdog unseals
    intent: The next real Vault outage produces one clear message and no repair button.
interface: none
```

**Intent approved:** pending — stage B intents (E2–E4, E6) were approved on the r7 bug doc on 2026-11-17; E1 and E5 are new
