# Review: v1.46.0 plan 3 — Operator acceptance automation (combine review of three children)

**Filed:** 2026-11-26
**Repo / branch:** `k3d-manager` / `k3d-manager-v1.46.0`
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Neon (agy, `gemini-4-neon-high`), role review — the combine reviewer named in
[`v1.46.0-model-experiment.md`](v1.46.0-model-experiment.md)

## Task

Three child specs of one plan were implemented separately by three different models and landed on this branch:

- [`v1.46.0-p3a-acceptance-offline-runner.md`](v1.46.0-p3a-acceptance-offline-runner.md) — commits `bc5cfbe8`, `155f15e1`
- [`v1.46.0-p3b-acceptance-live-profile.md`](v1.46.0-p3b-acceptance-live-profile.md) — commit `0e500bcb`
- [`v1.46.0-p3c-acceptance-docs.md`](v1.46.0-p3c-acceptance-docs.md) — commit `42063f90`

The umbrella is [`v1.46.0-operator-acceptance-automation.md`](v1.46.0-operator-acceptance-automation.md). Review the
three changes **together** against the umbrella (`git show <sha>`, then read the current files). Do not edit any file;
write your review as your final answer. No network calls; never read or print Keychain values.

Look specifically for what separate implementers miss at the seams:

1. **Contract drift:** p3b imports p3a's runner, redaction and report schema. Do scenario/report/outcome fields, cause
   values (`product_contract`, `harness_error`, ...), run-directory layout and exit codes agree between p3a, p3b and the
   p3c guide?
2. **Isolation end to end:** can a default (non-live) run reach a real Slack endpoint, the real Pushgateway, the hub,
   Keychain, or production cleanup tools? Can the live profile submit anything outside its closed list, run without
   `K3DM_ACCEPTANCE_LIVE=1` and a TTY, or leak the Grafana token (argv, logs, report, drafts)? Name the file:line that
   stops each, or say it is missing.
3. **Duplicated or diverging helpers** (two redaction paths, two report writers, two lock or run-root resolvers) and dead
   code.
4. **Umbrella requirements no child implemented**, or implemented differently.
5. **Docs (p3c) claims that disagree with the code** (flags, targets, variables, scenario ids, deadlines, outcomes).
6. **Tests:** any `must_not` in the three child Acceptance blocks whose test cannot actually fail on the landed code;
   any test that writes outside a scratch directory (one p3b mutant wrote drafts into the real `docs/bugs/`).

## Files

| File | Change |
|---|---|
| `docs/plans/v1.46.0-operator-acceptance-automation.md` | read only (start here; read anything else you need) |
| `scripts/lib/acceptance/runner.py` | read only |
| `scripts/lib/acceptance/live.py` | read only |
| `scripts/lib/acceptance/drafts.py` | read only |
| `docs/guides/operator-acceptance.md` | read only |

## What NOT to Do

- Do not edit, create, stage or commit any file. Do not run the live profile or any cloud request.

## Output

Findings most severe first, each tagged BLOCKER / MAJOR / MINOR, with file:line evidence and a concrete fix. Then a
verdict for the combined plan: PASS, PASS WITH FIXES, or FAIL.

## Acceptance

```yaml
must:
  - id: M1
    text: every finding cites file:line and a concrete fix; the report ends with a combined-plan verdict
must_not:
  - id: N1
    text: the reviewer changes any file or makes a network call
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: git status --short in the review worktree is empty; report has findings and a verdict
    intent: A second model checks that the three separately built pieces of the acceptance checker fit together and match the plan you approved, before the release PR.
interface: none
```

**Intent approved:** operator, 2026-11-26
**Approval words and scope:** "you can have Fable/Neno help you to combine them back" (combine review of each plan)
