# Bug: Bugs dashboard shows "not yet" in Live-verified for bugs whose Acceptance has no live evidence item

**Status:** OPEN
**Priority:** P3
**Classified:** P3 by gemini-4-argon-medium, 2026-11-12 (Cosmetic/hygiene display issue where the Bugs dashboard shows "not yet" instead of "n/a" for fixed bugs that only have offline acceptance checks); Claude proposed P3. Agreed.
**Triage:** passed over, 1st (out of v1.44.0 at the 10-P3 cap) — grooming 2026-11-12, operator.
**Waiting on:** operator decision — since 2026-11-12
**Introduced by:** unknown
**Should have been caught by:** spec
**Severity:** low — two v1.43.15 test-only P2s sit orange "not yet" for ever, as if a live check were owed; workaround: read the doc's Acceptance block
**Approval:** operator 2026-11-11: "go ahead to file a P3 bug and dispatch to Flash 3.8 when allow"
**Intent approved:** operator, 2026-11-11 ("P3: intent approved")
**Prior art:** none (Pass 1: no slug match; Pass 2 `make find-similar-docs` not run: vector store unreachable from the M4, context `k3d-k3d-cluster` missing)
**Assigned:** Gemini Flash 3.8 (`AGENT=agy MODEL=gemini-3.8-flash-medium`)
**Filed:** 2026-11-11
**Detected by:** operator, Bugs dashboard, 2026-11-11 (10 v1.43.15 P2 rows "not yet")
**Affected:** `bin/k3dm-vectordb-metrics` (`:699-748`)
**Branch:** `k3d-manager-v1.43.15`

## Symptom

A fixed bug whose `## Acceptance` evidence is all `kind: offline` can never turn green in the Live-verified column:
the exporter sets `live_verified="false"` for every fixed doc whose Status does not start `LIVE-VERIFIED`
(`bin/k3dm-vectordb-metrics:729`). Examples on 2026-11-11:
`docs/bugs/2026-11-08-codex-dispatch-tests-fail-after-intent-rule-date.md` and
`docs/bugs/2026-11-08-dashboard-query-test-rejects-label-replace-built-columns.md`, both VERIFIED by tests, no live item.

## Fix

In `bin/k3dm-vectordb-metrics`, where `verified`/`live_verified` are set for `status == "fixed"` (`:727-739`):

- When the release is at least 1.43.2, `doc_verification(text) != "live"`, the doc has a `## Acceptance` section
  (heading exactly `## Acceptance`, the regex at `bin/k3dm-dispatch-metrics:1062`), that section has at least one
  `kind:` line, and none of them is `kind: live` (the regex at `bin/k3dm-dispatch-metrics:1063`): set
  `live_verified = "n/a"` and `value = -2`. `verified` and `live_evidence` are unchanged.
- Everything else is unchanged: a doc with no `## Acceptance` section, a doc with a `kind: live` item, a
  `LIVE-VERIFIED` doc (stays `true` even with no live item), and open, deferred or unknown docs.
- The aggregate `k3dm_bug_status_docs` carries the same value, as it already does for the pre-1.43.2 `n/a`.

Copy the two regexes; do not import from `bin/k3dm-dispatch-metrics`.

## Files

- `bin/k3dm-vectordb-metrics`
- `scripts/tests/bin/test_vectordb_bug_metrics.py`

## Contract readers

The `live_verified` label value of `k3dm_bug_info` / `k3dm_bug_status_docs` (found with
`git grep -n "live_verified\|k3dm_bug_info\|k3dm_bug_status_docs"`):

- `bin/k3dm-vectordb-metrics:729-732,771-777,808` — **writer**; changes: emits `n/a` in the new case. It already emits `n/a` for pre-1.43.2 docs.
- `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml:1225` — Live-verified value mapping; unchanged: `n/a` already renders grey "n/a".
- `grafana-dashboard-bugs.yaml:1018` — Live-verified tile sums `live_verified="true"`; unchanged: `n/a` rows are not counted, which is correct.
- `grafana-dashboard-bugs.yaml:79` — `$verified` variable, "Hide live-verified : ^(false|-)?$"; unchanged: `n/a` rows are hidden under that filter, which is intended (no live work owed), as for pre-1.43.2 rows today.
- `grafana-dashboard-bugs.yaml:1098` — table query `live_verified=~"$verified"`; unchanged.
- `grafana-dashboard-bugs.yaml:2049,2194` — plan panels read `k3dm_plan_*`, not this label; not affected.
- `bin/k3dm-dispatch-metrics:1063` — reads `kind: live` from the docs, not from the metric; unchanged.
- `scripts/lib/hermes/prior_art.py` `doc_status`/`doc_verification` — the Status contract; unchanged, Status is not reinterpreted.

No other writer of these series exists.

## Do not

- Change `prior_art.py`, the dashboard JSON, any bug doc's Status, or `bin/k3dm-dispatch-metrics`.
- Mark a doc `n/a` because its Acceptance section is missing or has no `kind:` lines.
- Commit, push, or skip hooks.

## Acceptance

```yaml
must:
  - id: M1
    text: "a fixed, VERIFIED doc (release >= 1.43.2) whose Acceptance has only kind: offline items gets live_verified=\"n/a\" on k3dm_bug_info and on k3dm_bug_status_docs, with value -2"
  - id: M2
    text: "a fixed, VERIFIED doc with a kind: live item keeps live_verified=\"false\" (paired control for N1)"
  - id: M3
    text: "a LIVE-VERIFIED doc with no kind: live item keeps live_verified=\"true\""
  - id: M4
    text: "a fixed doc with no ## Acceptance section keeps live_verified=\"false\""
must_not:
  - id: N1
    text: "a doc whose Acceptance has a kind: live item (written as '    kind: live' or '  - kind: live') is never reported n/a"
  - id: N2
    text: "an open, deferred or unknown doc is never reported n/a"
  - id: N3
    text: "a doc whose Acceptance section has no kind: line at all, or only a superseded heading such as '## Acceptance (initial triage, superseded)', is never reported n/a"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1, N2, N3]
    kind: offline
    intent: "tests run the real bug-metrics exporter on a scratch docs tree: a bug whose acceptance has no live check shows n/a, while bugs that do have one, or have no acceptance at all, show what they show today"
  - id: E2
    proves: [M1]
    kind: live
    intent: "after the fix reaches the M5 checkout and the next Hermes tick runs, the Bugs dashboard shows n/a in Live-verified for the two test-only v1.43.15 P2s, while the ACG key-import row still shows not yet"
interface:
  - "bin/k3dm-vectordb-metrics, loaded with runpy as in scripts/tests/bin/test_vectordb_bug_metrics.py (the metrics fixture), run over a tmp_path repo with docs/bugs/"
```

## Definition of done (worker)

Before your last message, do all of these and paste the evidence:
1. Run every test suite that covers a file you changed (`python3 -m pytest scripts/tests/bin/test_vectordb_bug_metrics.py`), with the command, exit code and every error line. An error you can't explain is a failure, not a pass.
2. For each `must_not`: break the guard, show its test red, restore it, show it green. List any that stayed green.
3. One read-only real-data run: run the exporter's bug scan over this repo's real `docs/bugs/` with output to stdout only (no Pushgateway push) and paste the `k3dm_bug_info` lines for the two example docs and for `2026-11-01-acg-new-hub-ec2-key-import-and-extend-profile`.
4. List every choice the spec did not decide.

## Notes

- Delivery: the exporter runs on the Hermes tick from the M5 checkout, so the fix reaches the hub through checkout sync; no promote is needed.
- Filed during WIP 3/3 (P3 batching rule): dispatch when a slot frees.
