# Plan: Hermes Vault-sealed — post-land review fixes (v1.44.2)

**Filed:** 2026-11-17
**Branch:** `k3d-manager-v1.44.2`
**Status:** ready for dispatch
**Covers:** H1, H2, H3, H5 in `docs/bugs/2026-11-17-vault-sealed-landed-review-findings.md` (follow-up to `docs/plans/hermes-vault-sealed.md`, fadf8438). H4 (guide) is Claude's.
**Risk:** low (one label check, one r7 precondition clause, two message strings; no cluster writes)
**Reviewed:** Claude only (low risk; findings already confirmed by a Fable diff review and re-read by Claude)
**Agent:** Luna (Codex)

## Problem

- **H1** `scripts/lib/hermes/sensors.py:908`: `sealed = labels["vault-sealed"] == "true"`, so `""`, `"True"` or garbage reads as unsealed.
- **H2** `scripts/lib/hermes/repairs.py:205`: `all(pod.get("sealed") is False for pod in pods)` is true for an empty list.
- **H3** `bin/k3dm-hermes:286`: the resolved text uses `timestamp()[11:16]` (no zone) and always says "without a repair";
  `repairs_attempted_this_incident` is cleared at `:279`, before the text is built.
- **H5** `scripts/lib/hermes/correlator.py:58`: "ESO and ArgoCD failures listed below follow from it" even when only `eso`
  contributes (live 2026-11-17 15:25:15Z: contributors `eso` + `vault_seal`).

## Before You Start

1. Read `memory-bank/activeContext.md` and the findings doc above.
2. `git pull` on `k3d-manager-v1.44.2`.
3. Read `vault_seal` in `sensors.py`, `_r7_precondition` in `repairs.py`, `_template` in `correlator.py`, `_run_cycle`
   in `bin/k3dm-hermes` (265-300), and the tests named below, before editing.

## Fix

1. **H1** (`sensors.py`, `vault_seal`): label value `"true"` → sealed, `"false"` → unsealed, anything else → return
   `record("vault_seal", "unknown", "vault seal state unavailable")` (same as a missing label).
2. **H2** (`repairs.py`, `_r7_precondition`): also require `bool(pods)`.
3. **H3** (`bin/k3dm-hermes`, `_run_cycle`): read `attempted = list(state.get("repairs_attempted_this_incident", []))`
   before it is cleared. The withdrawn text becomes
   `Hermes incident resolved at HH:MMZ <tail>. Withdrawn: … Nothing to approve; old buttons are refused.` where HH:MM is
   `timestamp()[11:16]` and `<tail>` is `without a repair` when `attempted` is empty, else `after repair <ids joined ", ">`.
4. **H5** (`correlator.py`, `_template`): name only the contributors other than `vault_seal`, mapped `eso` → `ESO`,
   `argocd` → `ArgoCD`, any other sensor by its name, joined with `" and "` for two and `", "` plus `" and "` before the
   last for three or more. Sentence: `<names> failures listed below follow from it. ` When no other sensor contributes,
   omit that sentence. The rest of the Root cause text is unchanged.

## Files

| File | Change |
|---|---|
| `scripts/lib/hermes/sensors.py` | Fix 1 |
| `scripts/lib/hermes/repairs.py` | Fix 2 |
| `bin/k3dm-hermes` | Fix 3 |
| `scripts/lib/hermes/correlator.py` | Fix 4 |
| `scripts/tests/hermes/test_hermes.py` | tests 1, 3, 4, 5 |
| `scripts/tests/hermes/test_repairs.py` | test 2 |

## Contract readers

The two message strings are read only by Slack and by tests. `grep -rn "ESO and ArgoCD\|without a repair" bin scripts docs/guides`
(2026-11-17) finds only the writers, `bin/k3dm-hermes:286` and `scripts/lib/hermes/correlator.py:58`; no test or guide
asserts either string today. `docs/guides/hermes.md` is updated by Claude (H4), not this dispatch.

## Tests (these names exactly)

1. `test_vault_seal_unexpected_label_value_is_unknown` (test_hermes.py) — label values `"True"`, `""` and `"yes"` each give
   status `unknown`; `"false"` still gives `healthy` (positive control).
2. `test_r7_not_offered_when_vault_seal_has_no_pods` (test_repairs.py) — the `test_r7_offered_when_only_cosign_fails`
   records, but the `vault_seal` record is healthy with `data: {"pods": []}` → r7 not proposed. `test_r7_offered_when_only_cosign_fails`
   stays green unchanged (positive control).
3. `test_resolved_text_has_utc_zone` (test_hermes.py) — resolved with one pending proposal: text matches
   `r"resolved at \d\d:\d\dZ "`.
4. `test_resolved_text_names_attempted_repair` (test_hermes.py) — `repairs_attempted_this_incident = ["r2"]` before the
   resolving cycle → text contains `after repair r2` and not `without a repair`; with an empty list → `without a repair`.
5. `test_root_cause_names_only_contributing_sensors` (test_hermes.py) — contributors `eso` + `vault_seal` → text contains
   `ESO failures listed below follow from it.` and not `ArgoCD`; `eso` + `argocd` + `vault_seal` → `ESO and ArgoCD failures`.

Pre-fix red: 1, 2, 3, 4, 5 fail on the current code. Mutations (each must turn the named test red; apply by hand, run,
revert): compare `labels["vault-sealed"] == "true"` again (1); drop `bool(pods)` (2); drop the `Z` (3); read `attempted`
after it is cleared (4); hard-code `ESO and ArgoCD` (5).

## What NOT to Do

- Do NOT add any unseal path, Vault API call, `kubectl exec` or Secret read.
- Do NOT change other sensors, the debounce, the correlator's two-contributor rule, the exporter or dashboard JSON.
- Do NOT touch `bin/k3dm-webhook`, `scripts/tests/bin/`, `docs/guides/` or `CHANGELOG.md`.
- Do NOT commit, push or open a PR. Claude verifies and commits.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT update `memory-bank/`.
- Do NOT modify files outside the Files table.

## Rules

- LF line endings only; keep existing indentation, quoting and naming; no unsolicited refactors.
- No test calls a real `kubectl`, Slack, Gemini or the Vault API; stubs only.
- If the spec contradicts the code, stop and say so; do not guess.

## Gates

`pytest scripts/tests/hermes`, then `make test-pytest`.

## Definition of Done

- [ ] Fix 1-4 implemented; `git status` shows only files in the Files table.
- [ ] Pre-fix red recorded for tests 1-5.
- [ ] Both gates green.
- [ ] Mutation table: mutation → test → red.
- [ ] Report back to Claude: changed files, test output, mutation table. No commit.

## Acceptance

```yaml
must:
  - id: M1
    text: an unexpected vault-sealed label value reads as unknown, and r7 needs at least one unsealed Vault pod on record
  - id: M2
    text: the resolved message carries a Z time and says whether a repair ran; the Root cause line names only the sensors that contributed
must_not:
  - id: N1
    text: a vault-sealed value other than "true"/"false" reads as unsealed — red today
  - id: N2
    text: r7 is proposed from a vault_seal record with no pods — red today
  - id: N3
    text: the Root cause line names ArgoCD when ArgoCD did not contribute — red today
evidence:
  - id: E1
    proves: [M1, N1, N2]
    kind: offline
    command: pytest scripts/tests/hermes -k "unexpected_label_value or no_pods or r7_offered_when_only_cosign"
    intent: Hermes treats unclear Vault state as unknown and never offers the cosign repair without proof that Vault is unsealed.
  - id: E2
    proves: [M2, N3]
    kind: offline
    command: pytest scripts/tests/hermes -k "utc_zone or attempted_repair or only_contributing"
    intent: The Slack text says exactly what failed and when, with no service named that was fine.
interface: none
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** "dispatch two small ones" (fix the review findings in v1.44.2 rather than carry).
