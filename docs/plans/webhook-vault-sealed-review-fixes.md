# Plan: webhook Vault-sealed check — post-land review fixes (v1.44.2)

**Filed:** 2026-11-17
**Branch:** `k3d-manager-v1.44.2`
**Status:** ready for dispatch
**Covers:** W1–W6 in `docs/bugs/2026-11-17-vault-sealed-landed-review-findings.md` (follow-up to `docs/plans/webhook-analyze-vault-context.md`, bea02b84).
**Risk:** low (parsing and argv of two read-only kubectl reads in one webhook job; tests)
**Reviewed:** Claude only (low risk; findings already confirmed by a Fable diff review and re-read by Claude)
**Agent:** Luna (Codex)

## Problem

`_posix_spawn_capture` (`bin/k3dm-webhook:1429`) writes the child's stderr into the same file as stdout
(`POSIX_SPAWN_DUP2, 1, 2` at `:1456`). When kubectl prints a warning, `_vault_summary` (`:2054`) and
`_store_summary` fail `json.loads`, report "state unavailable", and Vault counts as not sealed: the sealed
short-circuit silently falls back to the LLM diagnosis. Also, one unlabelled pod hides a sealed one, the two reads
have no `--request-timeout`, tests never assert the argv, `if not diag_parts` is dead, and `argocd_app` reaches kubectl
without `--`.

**External behaviour proof (Claude, 2026-11-17):** the hub's kubectl is `v1.37.2` (hub pane, `kubectl version --client`).
At tag v1.37.2, `staging/src/k8s.io/kubectl/pkg/cmd/cmd.go:166` installs `rest.NewWarningWriter(o.IOStreams.ErrOut, …)`
with `ErrOut: os.Stderr` (`:97`) and colour only when stderr is a terminal; `staging/src/k8s.io/client-go/rest/warnings.go:167`
writes each warning as `fmt.Fprintf(w.out, "Warning: %s\n", message)`. So, captured to a file, a warning is a whole
line that starts with `Warning: `.

## Before You Start

1. Read `memory-bank/activeContext.md` and the findings doc above.
2. `git pull` on `k3d-manager-v1.44.2`.
3. Read `bin/k3dm-webhook` `_posix_spawn_capture` (1429-1484), `_vault_summary`, `_store_summary` and `_run_analyze`
   (2054-2240), and `scripts/tests/bin/test_webhook_analyze_routing.py` in full before editing.

## Fix (`bin/k3dm-webhook` only)

1. **W1.** Add `_kubectl_json(out)`: drop every line that starts with `Warning: `, then `json.loads` the rest. Use it
   in `_vault_summary` and `_store_summary` in place of `json.loads`. Do NOT change `_posix_spawn_capture` (it has
   other callers).
2. **W3.** In `_vault_summary`, a pod with no name, no labels dict, or a missing/None `vault-sealed`,
   `vault-initialized` or `vault-active` label no longer returns "state unavailable" for the whole line: it becomes
   `<name or ?> state unavailable` in the joined line and is not counted as sealed. The line is
   `Vault pods: state unavailable` only when no pod has all three labels. Sealed = any fully labelled pod with
   `vault-sealed` `true`.
3. **W4.** Append `"--request-timeout=10s"` to both read argv (`vault_cmd`, `store_cmd`).
4. **W5.** Delete the dead `if not diag_parts:` block.
5. **W6.** The describe argv becomes `["kubectl", "describe", "application", "-n", "cicd", "--", argocd_app]`.

## Files

| File | Change |
|---|---|
| `bin/k3dm-webhook` | Fix 1-5 |
| `scripts/tests/bin/test_webhook_analyze_routing.py` | tests below; update the argv in `test_analyze_vault_reads_are_exact_and_once` |

## Contract readers

None. The two argv and both summary helpers are private to `_run_analyze`; `grep -n "_vault_summary\|_store_summary\|vault_cmd\|store_cmd" bin/ scripts/`
finds only `bin/k3dm-webhook` (2054-2170) and the test file.

## Tests (`scripts/tests/bin/test_webhook_analyze_routing.py`, these names exactly)

1. `test_vault_summary_ignores_kubectl_warning_lines` — `_vault_summary("Warning: v1 Foo is deprecated\n" + <vault-0 sealed=true JSON>, False)`
   returns sealed True and `["vault-0"]`; same with the warning line after the JSON.
2. `test_store_summary_ignores_kubectl_warning_lines` — a warning line before store JSON with Ready=True gives
   `ClusterSecretStore vault-backend: Ready=True (<reason>)`.
3. `test_vault_summary_unlabelled_pod_does_not_mask_sealed` — vault-0 fully labelled sealed=true, vault-1 with no labels →
   sealed True, `["vault-0"]`, line contains `vault-0 sealed=true` and `vault-1 state unavailable`.
4. `test_vault_summary_all_unlabelled_is_unavailable` — every pod unlabelled → `("Vault pods: state unavailable", False, [])`.
5. `test_analyze_vault_sealed_runs_only_the_two_reads` — sealed, two firing alerts: the recorded argv list equals exactly
   `[vault_cmd, store_cmd]` (whole-list equality, both with `--request-timeout=10s`): no describe, no `get pods -A`,
   no `exec`, no `secret`; `_call_gemini` never called.
6. `test_analyze_describe_passes_double_dash` — unsealed, alert label `name=app1`: the describe argv equals
   `["kubectl", "describe", "application", "-n", "cicd", "--", "app1"]`.

Pre-fix red: 1, 2, 3, 5, 6 fail on the current code (4 is a guard and passes today). Mutations (each must turn the named
test red; apply by hand, run, revert): use plain `json.loads` (1, 2); return unavailable for the whole line on one
unlabelled pod (3); count an unlabelled pod as sealed (4); drop `--request-timeout=10s` (5); drop `--` (6).

## What NOT to Do

- Do NOT change `_posix_spawn_capture` or any other caller of it.
- Do NOT exec into a pod, call the Vault API, or read a Secret.
- Do NOT change routing, posting, `filter_suggestion`, `fence`, the sealed message text, or any other job.
- Do NOT touch `scripts/lib/hermes/`, `bin/k3dm-hermes`, `docs/guides/` or `CHANGELOG.md`.
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

- [ ] Fix 1-5 implemented; `git status` shows only the two files.
- [ ] Pre-fix red recorded for tests 1, 2, 3, 5, 6.
- [ ] Both gates green.
- [ ] Mutation table: mutation → test → red.
- [ ] Report back to Claude: changed files, test output, mutation table. No commit.

## Acceptance

```yaml
must:
  - id: M1
    text: the alert diagnosis detects a sealed Vault when kubectl also prints Warning lines, and when another Vault pod lacks labels
  - id: M2
    text: both Vault/ESO reads carry --request-timeout=10s, and while sealed they are the only kubectl calls in the job
must_not:
  - id: N1
    text: a kubectl Warning line makes a sealed Vault read as not sealed — red today
  - id: N2
    text: an unlabelled Vault pod hides a sealed one — red today
  - id: N3
    text: the alert diagnosis path execs into a pod, calls the Vault API or reads a Secret
evidence:
  - id: E1
    proves: [M1, M2, N1, N2, N3]
    kind: offline
    command: pytest scripts/tests/bin/test_webhook_analyze_routing.py -k "vault or double_dash"
    intent: A harmless kubectl warning no longer hides a sealed Vault, so alert messages keep pointing at Vault during an outage.
interface: none
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** "dispatch two small ones" (fix the review findings in v1.44.2 rather than carry).
