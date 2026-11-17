# Bug: Hermes offers the cosign signing-restore repair (r7) when every ExternalSecret fails because Vault is sealed

**Status:** LANDED on `k3d-manager-v1.44.2` 2026-11-17 (fadf8438 Fix 1–4, bea02b84 Fix 5); verified offline by Claude
**Priority:** P2 — raised from P3 (operator, 2026-11-17: "go ahead"). The operator approves repairs from Slack while away; a card that recommends nothing, and offers the wrong repair during an upstream outage, cannot be judged from a phone.
**Introduced by:** pre-existing
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Waiting on:** live check — since 2026-11-17 (promote, then dashboard row; Vault-restart check needs an operator go)
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

Deterministic rules decide; an LLM never decides whether to approve. Fix 1–4 are the Hermes dispatch
(`docs/plans/hermes-vault-sealed.md`); Fix 5 is a separate dispatch on the webhook
(`docs/plans/webhook-analyze-vault-context.md`).

1. **r7 precondition** (`scripts/lib/hermes/repairs.py`, `_r7_precondition`). Keep the existing conditions and add:
   - the `vault_seal` record is present, its status is `healthy`, and every entry in its `data["pods"]` has
     `sealed is False`. The raw label check closes the first sealed cycle, when the debounced status is
     still `healthy`. Degraded, unknown or missing → not offered.
   - the eso evidence starts with `N/M not synced` (`re.match(r"(\d+)/(\d+) not synced", evidence)`, the
     leading count only; evidence is truncated at 200 characters and lists names after the colon) and
     `N <= 2`. Evidence that does not match → not offered.
   Because `approve()` re-runs the precondition, the same rule refuses an approval if Vault seals between proposal and tap.
   Add `vault_seal` to r7's `reads` tuple (`repairs.py:291`) and to r7's entry in `_evidence` (`repairs.py:320`), so the proposal evidence shows Vault's state and the approval digest (`_records_digest`) changes if Vault seals after the proposal.
2. **Root cause first** (`scripts/lib/hermes/correlator.py`, `_template` and `_enrich`). When the current cycle's `vault_seal` record is `degraded`, the incident text starts with
   `Root cause: Vault sealed (<evidence>). ESO and ArgoCD failures listed below follow from it. The unseal watchdog retries every 5 minutes; nothing to approve unless Vault is still sealed after 15 minutes.`
   followed by the existing per-sensor details, and `_enrich` does not call the LLM for that event.
   Both must use the same predicate on the current `records` (one private helper), not `event["sensors"]`, which spans the correlation window. `_enrich(self, event, state, llm, today)` does not take `records` today: pass the boolean from `process()`.
   Known limit, no change: an incident needs two degraded contributors, so a lone seal posts nothing until ESO or ArgoCD also degrades. Production `_run_cycle` passes no `llm` to `process()`, so the LLM rule is defensive; test it with a stub.
3. **Recommendation on every card** (`scripts/lib/hermes/repairs.py` registry, `propose()`, `scripts/lib/hermes/approvals.py` `interactive_blocks`, `bin/k3dm-hermes` text fallback). Each `REPAIRS` entry gains two fixed strings: `approve_when` (the evidence that makes Approve right, e.g. r7: "only the cosign key is missing and Vault is unsealed") and `if_ignored` (e.g. r7: "image signature checks keep failing; it will not clear on its own"). Fill both for r1–r10 from each precondition.
   - `propose()` copies both strings into each proposal dict.
   - `interactive_blocks` renders `Recommended: Approve — <approve_when>. If you do nothing: <if_ignored>.` for a proposal that has both keys, and renders the block as today when either is absent (`test_approvals.py:75` and `:101` pass dicts without them and must stay green unchanged).
   - The text card built in `_run_cycle` (`bin/k3dm-hermes:282-284`, "Approve with: …") adds the same Recommended line under each proposal, so a card posted without buttons carries it too.
4. **Resolution names what it withdrew** (`bin/k3dm-hermes`, `_run_cycle` resolved branch, lines 273-276).
   - `_run_cycle` gains keyword `withdraw_on_resolve=False`; `_poll` (`bin/k3dm-hermes:974`) passes `True`. The approval re-samples in `_drain_approvals` (`:317`) and the CLI `approve` (`:1097`) keep the default, so `approve()` still sees the proposal and refuses with its real reason.
   - With `withdraw_on_resolve=True` and a `resolved` event: collect the entries in `pending_repairs` that are not expired (`repairs._expired`), clear `pending_repairs`, skip `repairs.propose()` for that cycle, and, when anything was collected, make the message
     `Hermes incident resolved at <HH:MMZ> without a repair. Withdrawn: <action_id> (<name>), … Nothing to approve; old buttons are refused.`
     When nothing was collected the message stays as today.
   - Known limit, no change: if the resolve happens inside an approval re-sample, the message is not posted (as today); the nonce is already dropped, so old buttons are refused.
5. **Alert diagnosis sees Vault and ESO** (`bin/k3dm-webhook`, `_run_analyze`). Specified in `docs/plans/webhook-analyze-vault-context.md`.

Out of scope: a Claude API provider for these messages is a feature, so it goes to `docs/ideas.md` (row 2026-11-17), not this patch. Note there that `correlator.py:55` skips enrichment when `provider == "claude"` today.

## Files

Hermes dispatch:

| File | Change |
|---|---|
| `scripts/lib/hermes/repairs.py` | r7 precondition, `reads`, `_evidence`; `approve_when` / `if_ignored` on r1–r10; copied by `propose()` |
| `scripts/lib/hermes/approvals.py` | Recommended line in `interactive_blocks` |
| `scripts/lib/hermes/correlator.py` | root-cause line; no LLM while Vault sealed |
| `bin/k3dm-hermes` | Recommended line on the text card; `withdraw_on_resolve` |
| `scripts/tests/hermes/test_hermes.py` | root-cause and resolved tests |
| `scripts/tests/hermes/test_repairs.py` | r7 tests; existing r7 test gains a healthy `vault_seal` record |
| `scripts/tests/hermes/test_approvals.py` | recommended tests; obsolete `git diff` assertion removed |
| `docs/guides/hermes.md` | card format: root cause, Recommended line, resolved message |

Two existing tests break without these edits:
- `test_repairs.py:330` `test_r7_requires_cosign_evidence_for_two_cycles` has no `vault_seal` record: add `record("vault_seal", "healthy", "unsealed: 1 pod(s)")` with `data={"pods": [{"name": "vault-0", "sealed": False, "initialized": True, "active": True}]}` (extend the `record` helper if it takes no `data`).
- `test_approvals.py:198-199` runs `git diff --quiet -- scripts/lib/hermes/repairs.py`, a v1.33.0 scope guard that fails whenever `repairs.py` is edited and not committed. Delete those two lines and put `# agent-audit: allow assert-removed v1.33.0 scope guard against editing repairs.py; this fix edits repairs.py by design` above the test.

`CHANGELOG.md` is written by Claude at land.

## Contract readers

`REPAIRS` gains two keys; readers by grep (2026-11-17): `scripts/lib/hermes/repairs.py:333,370,417`, `bin/k3dm-hermes:1101` — all read existing keys by name and ignore extra ones. Proposal dicts gain the same two keys; readers: `approvals.py` `interactive_blocks` (uses them), `bin/k3dm-hermes:282-284` (uses them), `:1071` (prints the map). `pending_repairs` is cleared on resolve; readers: `repairs.py:330,365,368,423`, `bin/k3dm-hermes:312` (drain: an empty map already yields "dropped: stale or unknown approval"), `:1071` (prints the map), `:1096` (CLI approve). Writers: `repairs.py:330` (propose) and the new resolve branch. The new `vault_seal` record is read by `scripts/lib/hermes/pager.py:79-82` (`health_events`): 30+ minutes of `unknown` pages "vault_seal check unknown", like every other sensor; intended. The Slack button value `<action_id>|<nonce>` is unchanged, so the relay's interactive handler is not a reader of anything new.

## Tests

Canned records only; no test calls real `kubectl` or Slack. Use these names exactly (the Acceptance `-k` filters select on them). A `vault_seal` "healthy" record below always carries `data` with one pod, `sealed: False`; "degraded" carries `sealed: True`.

`scripts/tests/hermes/test_repairs.py` (each `propose()` case runs two cycles with eso degraded):

1. `test_r7_not_offered_for_seal_capture`: eso `19/20 not synced: cosign-public-key, ghcr-pull-secret, ghcr-pull-secret`, `vault_seal` degraded (the 2026-11-17 01:09Z records) → no r7.
2. `test_r7_not_offered_when_many_fail_vault_healthy`: same eso evidence, `vault_seal` healthy → no r7.
3. `test_r7_not_offered_when_vault_degraded_one_failing`: eso `1/20 not synced: cosign-public-key`, `vault_seal` degraded → no r7.
4. `test_r7_not_offered_when_vault_seal_missing`: eso `1/20 not synced: cosign-public-key`, no `vault_seal` record → no r7.
5. `test_r7_not_offered_on_unparseable_evidence`: eso `cosign-public-key not synced`, `vault_seal` healthy → no r7.
6. `test_r7_not_offered_on_first_sealed_cycle`: eso `1/20 not synced: cosign-public-key`, `vault_seal` status `healthy` but `data` pod `sealed: True` → no r7.
7. `test_r7_offered_when_only_cosign_fails`: eso `1/20 not synced: cosign-public-key`, `vault_seal` healthy → r7 proposed, its evidence mentions `vault_seal` (positive control for 1–6).
8. `test_r7_approve_refused_when_vault_seals`: test 7's proposal, then `approve()` with `vault_seal` degraded → `refused: precondition no longer holds` (stub the git revision as the existing approve tests do).

17. `test_r7_digest_covers_vault_seal`: changing only the `vault_seal` record changes `repairs._records_digest(records, repairs.REPAIRS["r7"]["reads"])`.

`scripts/tests/hermes/test_hermes.py`:

9. `test_root_cause_vault_sealed_leads_and_skips_llm`: `Correlator.process` with `vault_seal` degraded plus eso and argocd degraded → text starts with `Root cause: Vault sealed`, and a stub `llm` records zero calls.
10. `test_root_cause_absent_when_vault_healthy`: `vault_seal` healthy, eso and argocd degraded → text does not contain `Root cause`, and the stub `llm` is called once (positive control).
11. `test_resolved_lists_withdrawn_and_clears`: `_run_cycle(..., withdraw_on_resolve=True)` with a stubbed correlator returning `resolved` and one non-expired pending proposal → message contains its action id and `Nothing to approve`, `pending_repairs == {}`, and `repairs.propose` was not called.
12. `test_resolved_without_pending_keeps_text`: same with nothing pending → message equals today's text.
13. `test_resolved_keeps_pending_on_approval_resample`: same as 11 with the default `withdraw_on_resolve` → `pending_repairs` still holds the proposal.
14. `test_recommended_line_on_text_card`: an incident with one proposal → the event text contains `Recommended: Approve — ` and `If you do nothing: `.

`scripts/tests/hermes/test_approvals.py`:

15. `test_recommended_every_repair_has_strings`: every `REPAIRS` entry has non-empty `approve_when` and `if_ignored`.
16. `test_recommended_line_in_interactive_blocks`: proposals from `propose()` (test 7's records) → each proposal's section in `interactive_blocks` contains `Recommended: Approve — <its approve_when>`; a proposal dict without the keys renders without the line.

Mutations (each must turn the named test red):

| Mutation | Test |
|---|---|
| drop the `vault_seal` status check from r7 | 3 |
| raise the count limit to `N <= 20` | 2 |
| treat unparseable evidence as `N = 0` | 5 |
| treat a missing `vault_seal` as healthy | 4 |
| drop the raw `sealed` check | 6 |
| drop `vault_seal` from r7's `reads` | 17 |
| let `_enrich` run while sealed | 9 |
| keep `pending_repairs` on resolve | 11 |
| clear `pending_repairs` on an approval re-sample | 13 |
| drop the Recommended line from the text card | 14 |
| leave `approve_when` empty on any repair | 15 |

Gates: `pytest scripts/tests/hermes`, `make test-pytest`.

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
    command: pytest scripts/tests/hermes/test_repairs.py -k "r7"
    intent: During a Vault outage Hermes no longer offers the cosign repair, and still offers it when only the cosign key is broken.
  - id: E2
    proves: [M2, M3, M4]
    kind: offline
    command: pytest scripts/tests/hermes -k "root_cause or recommended or resolved"
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
