# Bug: Hermes offers the cosign signing-restore repair (r7) when every ExternalSecret fails because Vault is sealed

**Status:** OPEN
**Priority:** P2 — raised from P3 (operator, 2026-11-17: "go ahead"). The operator approves repairs from Slack while away; a card that recommends nothing, and offers the wrong repair during an upstream outage, cannot be judged from a phone.
**Introduced by:** pre-existing
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-17 (intent approval on the combined plan `docs/plans/hermes-vault-sealed.md`, then dispatch)
**Prior art:** `docs/bugs/2026-10-12-hermes-has-no-vault-sealed-sensor.md` (exact-slug pass; `find-similar-docs` not run, no k3d-k3d-cluster context on the M4) — read, related root cause (no sealed-Vault signal), different symptom (wrong repair offered). That bug is the prerequisite for this one and ships first in the same release.
**Filed:** 2026-11-17
**Branch:** `k3d-manager-v1.44.2`
**Triage:** patch → v1.44.2 (P2), together with `2026-10-12-hermes-has-no-vault-sealed-sensor.md` (operator, 2026-11-17: "go ahead" to "one plan covering both bugs, in v1.44.2")
**Depends on:** `docs/bugs/2026-10-12-hermes-has-no-vault-sealed-sensor.md` (the `vault_seal` record)

## What happened

At 01:09Z on 2026-11-17 Vault on the hub was sealed by a planned restart (watchdog live check, operator go). Hermes posted an incident to Slack: `eso: Ready=False; 19/20 not synced: cosign-public-key, ghcr-pull-secret, ghcr-pull-secret`, plus two ArgoCD apps Degraded, and offered **r7 "Restore cosign signing key and ESO grant"** (`make signing-restore`) with Approve / Deny buttons. The same window produced two Gemini ArgoCDAppDegraded diagnoses (shopping-cart-apps, shopping-cart-identity) that blamed an App-of-Apps misconfiguration and Keycloak probes; neither mentioned Vault.

After the watchdog unsealed Vault (01:25:28Z), every ExternalSecret on the hub and on ubuntu-hostinger (20/20) was Ready and every ArgoCD application was Synced/Healthy by 01:28Z, with no repair run. The operator denied `r7-8d401b43` at 17:09 local after asking Claude (Slack: "r7-8d401b43 denied … dismissed; Hermes may propose it again"). Away from home, with no Claude session, the card gave no way to tell that Deny was right (operator, 2026-11-17: "if I am not home and you are not with me then how do I know if I have to approve or deny?").

## Cause

Four gaps, all read 2026-11-17 on `k3d-manager-v1.44.1`:

1. **r7 matches a keyword.** `scripts/lib/hermes/repairs.py:195-199` `_r7_precondition` fires when the `eso` record is degraded, its evidence contains `cosign-public-key`, and that lasts two cycles. The evidence is built by `scripts/lib/webhook/smoke.py:537` as `"{n}/{total} not synced: {first three names}"`; names sort alphabetically, so `cosign-public-key` is nearly always among the first three when many fail. During a seal r7's precondition is true.
2. **No root cause on the card.** `scripts/lib/hermes/correlator.py:43-48` lists every degraded sensor side by side. There is no Vault record yet (prerequisite bug), so the cause never appears.
3. **No recommendation on the card.** `scripts/lib/hermes/approvals.py:57-77` `interactive_blocks` shows the repair name and blast radius only: nothing on when Approve is right or what happens if the operator does nothing.
4. **The alert diagnosis cannot see Vault.** `bin/k3dm-webhook:2054` `_run_analyze` gives Gemini `kubectl describe application` and non-running pods only, so it invents a story (its own text: "the provided diagnostic data is insufficient").

What already works and must stay: `repairs.approve()` (`repairs.py:363`) re-checks the precondition and the records digest at approval time, and `_drain_approvals` (`bin/k3dm-hermes:305`) drops an approval whose nonce no longer matches. A tap after the incident resolved is already refused.

## Fix

Deterministic rules decide; an LLM never decides whether to approve.

1. **r7 precondition** (`scripts/lib/hermes/repairs.py`, `_r7_precondition`). Keep the existing conditions and add:
   - the `vault_seal` record is `healthy` (degraded or unknown or missing → not offered);
   - the `N/M not synced` count parsed from the `eso` evidence has `N <= 2`; evidence that does not parse → not offered.
   Because `approve()` re-runs the precondition, the same rule refuses an approval if Vault seals between proposal and tap.
   Add `vault_seal` to r7's `reads` tuple (`repairs.py:291`) and to r7's entry in `_evidence` (`repairs.py:320`), so the proposal evidence shows Vault's state and the approval digest (`_records_digest`) changes if Vault seals after the proposal.
2. **Root cause first** (`scripts/lib/hermes/correlator.py`, `_template` and `_enrich`). When the `vault_seal` record is degraded, the incident text starts with
   `Root cause: Vault sealed (<evidence>). ESO and ArgoCD failures listed below follow from it. The unseal watchdog retries every 5 minutes; nothing to approve unless Vault is still sealed after 15 minutes.`
   followed by the existing per-sensor details, and `_enrich` does not call the LLM for that event.
3. **Recommendation on every card** (`scripts/lib/hermes/repairs.py` registry, `scripts/lib/hermes/approvals.py` `interactive_blocks`). Each `REPAIRS` entry gains two fixed strings: `approve_when` (the evidence that makes Approve right, e.g. r7: "only the cosign key is missing and Vault is unsealed") and `if_ignored` (e.g. r7: "image signature checks keep failing; it will not clear on its own"). Every proposal is offered only when its precondition holds, so the card line is
   `Recommended: Approve — <approve_when>. If you do nothing: <if_ignored>.`
   Fill both strings for r1–r10 from each precondition; a test asserts none is empty.
4. **Resolution names what it withdrew** (`bin/k3dm-hermes` resolved branch near line 273). When the incident resolves with entries in `pending_repairs`, the resolved message becomes
   `Hermes incident resolved at <HH:MMZ> without a repair. Withdrawn: <action_id> (<name>), … Nothing to approve; old buttons are refused.`
   and `pending_repairs` is cleared. With nothing pending the message stays as today.
5. **Alert diagnosis sees Vault and ESO** (`bin/k3dm-webhook`, `_run_analyze`). Before the LLM call, read the Vault pod labels (`kubectl -n secrets get pods -l app.kubernetes.io/name=vault,component=server -o json`, labels only, the same read as the `vault_seal` sensor; never exec, never the Vault API, never a Secret) and the ClusterSecretStore Ready condition. If any Vault pod has `vault-sealed=true`, skip the LLM and post
   `Likely cause: Vault is sealed; this alert follows from it. Check Vault first, not <app>.`
   Otherwise append both reads to the diagnostics the LLM receives.

Out of scope: a Claude API provider for these messages is a feature, so it goes to `docs/ideas.md` (row 2026-11-17), not this patch. Note there that `correlator.py:55` skips enrichment when `provider == "claude"` today.

## Files

| File | Change |
|---|---|
| `scripts/lib/hermes/repairs.py` | r7 precondition; `approve_when` / `if_ignored` on r1–r10 |
| `scripts/lib/hermes/approvals.py` | Recommended line in `interactive_blocks` |
| `scripts/lib/hermes/correlator.py` | root-cause line; no LLM while Vault sealed |
| `bin/k3dm-hermes` | resolved message lists withdrawn proposals; clears `pending_repairs` |
| `bin/k3dm-webhook` | `_run_analyze` Vault/ESO context and sealed short-circuit |
| `scripts/tests/hermes/test_hermes.py` | tests 1–7 |
| `scripts/tests/bin/test_webhook_analyze_routing.py` | tests 8–9 |
| `docs/guides/hermes.md` | card format: root cause, Recommended line, resolved message |
| `CHANGELOG.md` | `[Unreleased]` → `### Fixed` |

## Contract readers

`REPAIRS` gains two keys; readers by grep (2026-11-17): `scripts/lib/hermes/repairs.py:333,370,417`, `bin/k3dm-hermes:1101` — all read existing keys by name and ignore extra ones. `pending_repairs` is cleared on resolve; readers: `repairs.py:330,365,368,423`, `bin/k3dm-hermes:312` (drain: an empty map already yields "dropped: stale or unknown approval"), `:1071` (prints the map), `:1096` (deny). Writers: `repairs.py:330` (propose) and the new resolve branch. The Slack button value `<action_id>|<nonce>` is unchanged, so the relay's interactive handler is not a reader of anything new.

## Tests

`scripts/tests/hermes/test_hermes.py` with canned records; no test calls real `kubectl` or Slack.

1. Records from 2026-11-17 01:09Z (eso degraded, `19/20 not synced: cosign-public-key, …`, `vault_seal` degraded), two cycles → `propose()` returns no r7.
2. Same eso evidence but `1/20 not synced: cosign-public-key`, `vault_seal` healthy, two cycles → r7 proposed (positive control for test 1).
3. Test 2's records, then `approve()` with `vault_seal` degraded → `refused: precondition no longer holds`.
4. `vault_seal` missing from records → no r7.
5. Incident text with `vault_seal` degraded starts with `Root cause: Vault sealed`, and a stub LLM records zero calls; with `vault_seal` healthy and another incident, the stub is called once (positive control).
6. Every `REPAIRS` entry has non-empty `approve_when` and `if_ignored`; `interactive_blocks` output contains `Recommended: Approve` for each proposal.
7. Resolve with one pending proposal → message contains its action id and `Nothing to approve`; `pending_repairs` is empty afterwards. Resolve with none → message equals today's text.

`scripts/tests/bin/test_webhook_analyze_routing.py`, with the existing `_posix_spawn_capture` stub:

8. Vault pod JSON with `vault-sealed=true` → posted message contains `Vault is sealed` and `_call_gemini` is never called; the stub saw no `exec` and no `secret` in any argv.
9. `vault-sealed=false` → `_call_gemini` is called once and its prompt contains the Vault and ClusterSecretStore reads (positive control).

Mutations (each must turn a test red): drop the `vault_seal` check from r7 (test 1); raise the count limit to `N <= 20` (test 1); let `_enrich` run while sealed (test 5); keep `pending_repairs` on resolve (test 7); call Gemini when sealed (test 8).

Gates: `pytest scripts/tests/hermes/test_hermes.py scripts/tests/bin/test_webhook_analyze_routing.py`, `make test-pytest`.

## Acceptance

```yaml
must:
  - id: M1
    text: r7 is proposed only when Vault is unsealed and at most 2 ExternalSecrets fail, and approve() refuses it if that stops holding
  - id: M2
    text: while Vault is sealed, the incident card leads with "Root cause: Vault sealed" and no LLM is called for it
  - id: M3
    text: every repair card carries a "Recommended: Approve — <when>. If you do nothing: <what>." line
  - id: M4
    text: a resolved incident names each withdrawn proposal and says nothing needs approving
  - id: M5
    text: an alert diagnosis during a Vault seal names Vault and skips the LLM; otherwise the LLM sees Vault and ClusterSecretStore state
must_not:
  - id: N1
    text: r7 is proposed for the 2026-11-17 01:09Z records (19/20 failing, Vault sealed) — red today
  - id: N2
    text: the alert diagnosis path execs into a pod, calls the Vault API or reads a Secret
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: pytest scripts/tests/hermes/test_hermes.py -k "r7"
    intent: During a Vault outage Hermes no longer offers the cosign repair, and still offers it when only the cosign key is broken.
  - id: E2
    proves: [M2, M3, M4]
    kind: offline
    command: pytest scripts/tests/hermes/test_hermes.py -k "root_cause or recommended or resolved"
    intent: From a phone, each Slack card says what is wrong, whether to press Approve, and when it is safe to ignore.
  - id: E3
    proves: [M5, N2]
    kind: offline
    command: pytest scripts/tests/bin/test_webhook_analyze_routing.py -k "vault"
    intent: Alert diagnoses blame a sealed Vault instead of inventing an app problem, using read-only checks.
  - id: E4
    proves: [M2, M4, M5]
    kind: live
    command: at the next planned Vault restart (operator go), the Slack incident starts with "Root cause: Vault sealed", offers no r7, and the resolved message follows after the watchdog unseals
    intent: The next real Vault outage produces one clear message and no repair button.
interface: none
```

**Intent approved:** operator, 2026-11-17 ("approved your for intent")
