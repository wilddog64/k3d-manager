# Plan: Hermes knows when Vault is sealed (v1.44.2)

**Filed:** 2026-11-17
**Branch:** `k3d-manager-v1.44.2`
**Status:** LANDED fadf8438 2026-11-17; live evidence pending
**Covers:** `docs/bugs/2026-10-12-hermes-has-no-vault-sealed-sensor.md` (stage A) and
`docs/bugs/2026-11-17-hermes-r7-signing-restore-offered-when-vault-sealed.md` Fix 1–4 (stage B).
Fix 5 (webhook alert diagnosis) is the separate dispatch `docs/plans/webhook-analyze-vault-context.md`.
**Approval:** operator, 2026-11-17 — "one plan covering both bugs, in v1.44.2"; split across Luna and
Flash on 2026-11-17 ("dispatch task evenly across flash and luna").
**Risk:** medium (Hermes repair gating and Slack card text; no cluster writes added)
**Reviewed:** Argon + Fable blind, 2026-11-17; Claude adjudicated (both CHANGES; every finding folded
into the bug docs).
**Agent:** Luna (Codex)

## Why one plan

Stage B reads the `vault_seal` record that stage A creates, and both stages edit
`scripts/lib/hermes/` and the Hermes tests. One dispatch keeps to the one-dispatch-per-file rule and
lets the stage B tests use the real stage A sensor.

## Before You Start

1. Read `memory-bank/activeContext.md` and both bug docs in full.
2. `git pull` on `k3d-manager-v1.44.2`.
3. Read every target file before editing it: `scripts/lib/hermes/sensors.py` (`hostnet_drift`,
   `_debounced`), `scripts/lib/hermes/repairs.py` (`REPAIRS`, `_r7_precondition`, `_evidence`,
   `_records_digest`, `_expired`, `propose`, `approve`), `scripts/lib/hermes/correlator.py`,
   `scripts/lib/hermes/approvals.py`, `bin/k3dm-hermes` (sensor list, `_run_cycle`, `_drain_approvals`,
   `_poll`, CLI `approve`), and the four test files.

## What to do

Do stage A, then stage B, in one working tree. The bug docs hold the detailed spec; follow each one's
`## Fix`, `## Files`, `## Tests` and `## What NOT to Do` exactly, including the exact test names.

- **Stage A:** the sensor bug doc, Fix 1–4, tests 1–9, and the stub updates for the existing
  `_run_cycle` tests.
- **Stage B:** the r7 bug doc, Fix 1–4 only, tests 1–17, and the two existing-test edits it lists.

## Files

| File | Stage |
|---|---|
| `scripts/lib/hermes/sensors.py` | A |
| `scripts/lib/hermes/repairs.py` | B |
| `scripts/lib/hermes/correlator.py` | B |
| `scripts/lib/hermes/approvals.py` | B |
| `bin/k3dm-hermes` | A, B |
| `scripts/tests/hermes/test_hermes.py` | A, B |
| `scripts/tests/hermes/test_app_health.py` | A |
| `scripts/tests/hermes/test_repairs.py` | B |
| `scripts/tests/hermes/test_approvals.py` | B |
| `docs/guides/hermes.md` | A, B |

## What NOT to Do

- Do NOT add any unseal path, Vault API call, `kubectl exec` or Secret read in the new sensor or in
  any repair.
- Do NOT change sensors other than adding `vault_seal`, or change the exporter or dashboard JSON.
- Do NOT touch `bin/k3dm-webhook`, `scripts/tests/bin/test_webhook_analyze_routing.py` or
  `CHANGELOG.md` (another dispatch and Claude own them).
- Do NOT add a Claude API provider (that is a feature, logged in `docs/ideas.md`).
- Do NOT commit, push or open a PR. Claude verifies and commits.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT update `memory-bank/`.
- Do NOT modify files outside the Files table.

## Rules

- LF line endings only; keep existing indentation, quoting and naming; no unsolicited refactors.
- No test calls a real `kubectl`, Slack, Gemini or the Vault API; stubs only.
- Pre-fix red: write the new tests first, run them against the unmodified code, and record which fail.
- If the spec contradicts the code, stop and say so; do not guess.

## Gates

`pytest scripts/tests/hermes`, then `make test-pytest`. Every mutation listed in either bug doc must
turn its named test red; apply each by hand, run the named test, revert.

## Definition of Done

- [ ] Stage A and stage B Fix 1–4 implemented; `git status` shows only files in the Files table.
- [ ] `pytest scripts/tests/hermes` green; `make test-pytest` green.
- [ ] Pre-fix red recorded for N1 and N2 tests (`test_vault_seal_missing_label_is_unknown`,
      `test_vault_seal_sealed_degrades_on_second_cycle`, `test_r7_not_offered_for_seal_capture`).
- [ ] Mutation table: mutation → test → red, for every mutation in both bug docs.
- [ ] Report back to Claude: changed files, test output, mutation table. No commit.

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
    text: every repair card, with or without buttons, carries a "Recommended: Approve — <when>. If you do nothing: <what>." line
  - id: M5
    text: a resolved incident names each withdrawn proposal and says nothing needs approving
must_not:
  - id: N1
    text: the vault_seal sensor reports healthy when the vault-sealed label is missing, or is not debounced — red today (no sensor exists)
  - id: N2
    text: r7 is proposed for the 2026-11-17 01:09Z records (19/20 failing, Vault sealed) — red today
  - id: N3
    text: the vault_seal sensor execs into a pod, calls the Vault API or reads a Secret, or any repair carries an unseal command
evidence:
  - id: E1
    proves: [M1, N1, N3]
    kind: offline
    command: pytest scripts/tests/hermes/test_hermes.py -k "vault_seal"
    intent: Hermes notices a sealed Vault from read-only pod labels, and has no way to unseal it.
  - id: E2
    proves: [M2, N2]
    kind: offline
    command: pytest scripts/tests/hermes/test_repairs.py -k "r7"
    intent: During a Vault outage Hermes no longer offers the cosign repair, and still offers it when only the cosign key is broken.
  - id: E3
    proves: [M3, M4, M5]
    kind: offline
    command: pytest scripts/tests/hermes -k "root_cause or recommended or resolved"
    intent: From a phone, each Slack card says what is wrong, whether to press Approve, and when it is safe to ignore.
  - id: E4
    proves: [M1]
    kind: live
    command: after promote, the next Hermes cycle shows a vault_seal row reading "unsealed: 1 pod(s)" on the Hermes Status dashboard (Claude, read-only)
    intent: You can see on the dashboard that Vault is unsealed, not guess it from ESO.
  - id: E5
    proves: [M1, M3, M5]
    kind: live
    command: at the next planned Vault restart (operator go), vault_seal goes degraded, the Slack incident starts with "Root cause: Vault sealed", offers no r7, and the resolved message follows after the watchdog unseals
    intent: The next real Vault outage produces one clear message and no repair button.
interface: none
```

**Intent approved:** operator, 2026-11-17
