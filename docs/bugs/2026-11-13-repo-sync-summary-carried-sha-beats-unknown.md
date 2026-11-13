# Bug: hub-sync summary shows a carried-forward promotable SHA instead of `unknown` after a failed lookup

**Status:** LANDED — b4290ee9 on k3d-manager-v1.44.0 2026-11-13 (Claude verified: pre-fix red, mutant red, Fable review no high/medium); originally captured 2026-11-13 from the independent Acceptance verification of plan 3 (Opus verifier, item N2; Claude reproduced)
**Priority:** P3 (summary line only; metrics are correct)
**Introduced by:** `c763e239` (v1.44.0 plan 3 `deploy-hub-behind-alert`)
**Should have been caught by:** offline test (E5/E10 in repo_sync_promote_backlog.bats assert metrics, never the summary)
**Prior art:** exact-slug glob: none. `make find-similar-docs` not run
**Approval:** operator, 2026-11-13: "go ahead for those three fix intents"
**Dispatch go:** operator, 2026-11-13: "go ahead for those three fix intents"
**Intent approved:** operator, 2026-11-13
**Intent approval words:** "go ahead for those three fix intents", in reply to Claude's three proposed intents

## Symptom

Plan 3 Acceptance N2 (with its round-1 and round-2 amendments): after a GitHub lookup failure or a fetch failure the summary says `unknown`. `bin/k3dm-repo-sync:325` computes `promotable = state.get("promotable_sha") or ("unknown" if state.get("promotable_unknown") else "none")`; `carry_forward_promotable` sets `promotable_sha`, so a carried SHA wins and the summary shows e.g. `promotable: 042d73e`.

## Fix

Test `promotable_unknown` first in that expression; metrics unchanged.

## Acceptance

```yaml
must:
  M1: when promotable_unknown is set, the hub-sync summary says "promotable: unknown" even if a SHA was carried forward
must_not:
  N1: the published metrics change (carried SHA series, lookup_failed value) in any scenario
  N2: the summary stops showing the short SHA when the lookup succeeded, or "none" when nothing is promotable
evidence:
  - {id: E1, proves: [M1], kind: offline, intent: "You will see a test where a failed GitHub lookup follows a cycle that found a SHA: the summary says promotable: unknown. Today it shows the old SHA."}
  - {id: E2, proves: [N1, N2], kind: offline, intent: "You will see the same scenario's metrics unchanged, and the found-SHA and none cases still print as before."}
interface:
  - "bin/k3dm-repo-sync --hub-summary"
```

## Files

| File | Change |
|---|---|
| `bin/k3dm-repo-sync` | summary precedence (~325) |
| `scripts/tests/bin/repo_sync_promote_backlog.bats` | E1, E2 |

## Worker definition of done

- Change only the files above. Stub `gh`, `curl`, `ssh` on PATH; set `PUSHGATEWAY_URL` to `http://127.0.0.1:9`; scratch HOME. Show E1 red on today's code, then green. Run `bats scripts/tests/bin/repo_sync_promote_backlog.bats scripts/tests/bin/repo_sync.bats` from the repo root and paste command, rc and proving lines. Leave changes uncommitted.

## Residual lows (P3 batch candidates)

- Low (Fable): the fetch-failure carry path (E10, `repo_sync_promote_backlog.bats:293`) has no `promotable: unknown` summary assertion; code is correct (flag set at `bin/k3dm-repo-sync:472`).
- Low (Fable): the new assertion (`:176`) skips `[ "$status" -eq 0 ]`; harmless.
