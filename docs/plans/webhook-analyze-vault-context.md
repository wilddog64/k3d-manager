# Plan: alert diagnosis sees Vault and ESO (v1.44.2)

**Filed:** 2026-11-17
**Branch:** `k3d-manager-v1.44.2`
**Status:** LANDED bea02b84 2026-11-17; live evidence pending
**Covers:** `docs/bugs/2026-11-17-hermes-r7-signing-restore-offered-when-vault-sealed.md` Fix 5 (cause 4).
The rest of that bug is `docs/plans/hermes-vault-sealed.md`.
**Approval:** operator, 2026-11-17 — part of "one plan covering both bugs, in v1.44.2"; split out for
Flash on 2026-11-17 ("dispatch task evenly across flash and luna").
**Risk:** low (read-only kubectl reads added to one webhook job; message text)
**Reviewed:** Argon + Fable blind, 2026-11-17, as part of the combined plan; Claude adjudicated.
**Agent:** Flash (agy, `gemini-3.8-flash-medium`)

## Problem

On 2026-11-17 01:09Z Vault was sealed by a planned restart. Two ArgoCDAppDegraded diagnoses blamed an
App-of-Apps misconfiguration and Keycloak probes. `_run_analyze` (`bin/k3dm-webhook:2054`) gives
Gemini only `kubectl describe application` and non-running pods, so it cannot see Vault.

## Before You Start

1. Read `memory-bank/activeContext.md` and the r7 bug doc (cause 4, Fix 5).
2. `git pull` on `k3d-manager-v1.44.2`.
3. Read `bin/k3dm-webhook` `_run_analyze` (lines 2054-2180) and
   `scripts/tests/bin/test_webhook_analyze_routing.py` in full before editing.

## Fix (`bin/k3dm-webhook`, `_run_analyze`)

1. Once per job, after `analyzed` is computed and before the `for alert in analyzed:` loop, run two
   reads through `_posix_spawn_capture` with `timeout=15`, exactly these argv:
   - `["kubectl", "-n", "secrets", "get", "pods", "-l", "app.kubernetes.io/name=vault,component=server", "-o", "json"]`
   - `["kubectl", "get", "clustersecretstore", "vault-backend", "-o", "json"]`
2. Reduce each to one summary line; never put raw JSON in the prompt:
   - Vault: from each item's `metadata.labels`,
     `Vault pods: vault-0 sealed=false initialized=true active=true` (pods joined with `; `).
   - Store: from `status.conditions` where `type == "Ready"`,
     `ClusterSecretStore vault-backend: Ready=True (<reason>)`.
   - A timeout, non-JSON output, no items, or a missing label/condition → the line
     `Vault pods: state unavailable` / `ClusterSecretStore vault-backend: state unavailable`, and Vault
     counts as not sealed. Never raise. (The existing `analyze_env` fixture returns
     `"diagnostic output"` for every call; all existing tests must stay green unchanged.)
3. Vault is sealed when any pod has label `vault-sealed == "true"`. Then, for each alert, before the
   `if not diag_parts:` check, skip the kubectl diagnostics and `_call_gemini` and use as the analysis
   `Vault is sealed right now (<sealed pod names>). This alert likely follows from it; check Vault first, not <display_name>.`
   It goes out through the existing `message = f"🔍 *{alert_name}* — `{display_name}`\n{analysis}"`
   and routing code, unchanged.
4. When Vault is not sealed, append both summary lines to `diag_parts` as one part
   `Vault and ESO:\n<vault line>\n<store line>`, so the LLM always sees them (this also means
   `diag_parts` is never empty).

## Files

| File | Change |
|---|---|
| `bin/k3dm-webhook` | `_run_analyze` reads, summaries, sealed short-circuit |
| `scripts/tests/bin/test_webhook_analyze_routing.py` | tests below |

## Tests (`scripts/tests/bin/test_webhook_analyze_routing.py`)

Use the `analyze_env` fixture and override `_posix_spawn_capture` with a stub that records each argv
and returns canned JSON by argv. Use these names exactly:

1. `test_analyze_vault_sealed_skips_gemini`: pod JSON with `vault-sealed=true` on `vault-0` → the posted
   message contains `Vault is sealed right now (vault-0)` and the display name, and `_call_gemini` is
   never called.
2. `test_analyze_vault_unsealed_prompt_has_summaries`: `vault-sealed=false`, store Ready=True →
   `_call_gemini` is called once; its prompt contains `Vault pods: vault-0 sealed=false` and
   `ClusterSecretStore vault-backend: Ready=True`, and does not contain `"metadata"` (no raw JSON).
3. `test_analyze_vault_reads_are_exact_and_once`: with two firing alerts, the recorded argv contain each
   of the two Fix 1 argv lists exactly once (whole-list equality).
4. `test_analyze_vault_unreadable_fails_open`: both reads time out → `_call_gemini` is called and its
   prompt contains `Vault pods: state unavailable`.

Pre-fix red: tests 1-4 fail on the current code. Mutations (each must turn the named test red): call
Gemini when sealed (1); drop the summaries from the prompt (2); read Vault inside the per-alert loop (3);
treat unreadable state as sealed (4).

## What NOT to Do

- Do NOT exec into a pod, call the Vault API, or read a Secret (`kubectl get secret(s)`).
- Do NOT change the routing, posting, `filter_suggestion` or `fence` code, or any other job.
- Do NOT touch `scripts/lib/hermes/`, `bin/k3dm-hermes`, `docs/guides/hermes.md` or `CHANGELOG.md`
  (another dispatch and Claude own them).
- Do NOT commit, push or open a PR. Claude verifies and commits.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT update `memory-bank/`.
- Do NOT modify files outside the Files table.

## Rules

- LF line endings only; keep existing indentation, quoting and naming; no unsolicited refactors.
- No test calls a real `kubectl`, Slack or Gemini; stubs only.
- If the spec contradicts the code, stop and say so; do not guess.

## Gates

`pytest scripts/tests/bin/test_webhook_analyze_routing.py`, then `make test-pytest`.

## Definition of Done

- [ ] Fix 1-4 implemented; `git status` shows only the two files.
- [ ] Pre-fix red recorded for tests 1-4.
- [ ] Both gates green.
- [ ] Mutation table: mutation → test → red.
- [ ] Report back to Claude: changed files, test output, mutation table. No commit.

## Acceptance

```yaml
must:
  - id: M1
    text: an alert diagnosis during a Vault seal names Vault and skips the LLM; otherwise the LLM sees Vault and ClusterSecretStore state
must_not:
  - id: N1
    text: the alert diagnosis path execs into a pod, calls the Vault API or reads a Secret
  - id: N2
    text: during a Vault seal the alert diagnosis calls the LLM and blames the app — red today
evidence:
  - id: E1
    proves: [M1, N1, N2]
    kind: offline
    command: pytest scripts/tests/bin/test_webhook_analyze_routing.py -k "vault"
    intent: Alert diagnoses blame a sealed Vault instead of inventing an app problem, using read-only checks.
  - id: E2
    proves: [M1]
    kind: live
    command: at the next planned Vault restart (operator go), an ArgoCDAppDegraded diagnosis in Slack says "Vault is sealed right now" (Claude or operator, read-only)
    intent: The next real Vault outage produces one clear message and no repair button.
interface: none
```

**Intent approved:** operator, 2026-11-17


## Live run 2026-11-17 15:01Z (Claude, operator go "go ahead for E5 and E2")

Webhook restarted first (`make restart-webhook`, new PID 14:58:57Z). `secrets/vault-0` deleted 15:01:11Z (unsealed before);
Hermes was kicked with `launchctl kickstart` while sealed. Watchdog unsealed it on its 15:05 run (`sealed=false` 15:06:41Z);
all 9 ExternalSecrets back to `True`.

- `vault_seal` records: 15:02:52Z `healthy`, evidence `sealed: vault-0` (first sealed cycle, debounced); 15:06:03Z
  `healthy`, `unsealed: 1 pod(s)`. Never degraded, so no "Root cause: Vault sealed" card: **E5 not met, not failed.**
  A Hermes cycle takes about 70 s to reach `vault_seal`, and a kickstart during a running cycle is a no-op, so only one
  sealed sample fit in the ~4 min seal.
- `ArgoCDAppDegraded` holds `for: 5m`, longer than the seal, so no alert fired and the webhook had nothing to diagnose:
  **E2 not exercised.**
- Finding: with a working watchdog, a pod restart self-heals inside one Hermes cycle, so the debounce correctly stays
  quiet. E5 and E2 can only be observed on a seal that outlasts the watchdog (the case that matters), or by pausing the
  watchdog CronJob for about 12 minutes. Operator decision.
