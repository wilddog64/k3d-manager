# Bug: Bug Tracking "Fix commit" shows the docs commit that marked a bug fixed, not the fix

**Status:** FIXED 2026-10-25 — `8a23a66b`; pytest 103/103, validate-manifests 85/85; Luna showed tests 1, 2 and 6 red on pre-fix copies. Live E2 pending the next bug scan and dashboard sync.
**Fix commit:** `8a23a66b`
**Review note:** Claude ran `doc_fix_commit` over all 95 real `**Fix commit:**` headers: every one parses, including the three in the Problem table (`79fab0b1`, `9cb1fa09`, `f11e0c6e`).
**Priority:** P3
**Severity:** low — the column points a reader at a status-flip docs commit instead of the code fix
**Release:** v1.43.7 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-25, by Claude, from the operator's Bug Tracking screenshot 284
**Approval:** not required — non-critical spec (operator rule: dispatch approval only for critical specs); metrics exporter and parser only.
**Component:** `bin/k3dm-vectordb-metrics` (`k3dm_bug_info` `fix_sha` label), `scripts/lib/hermes/prior_art.py` (`doc_fix_commit`)
**Related:** `docs/plans/v1.43.4-bug-table-fix-and-verified-commits.md` (defined `fix_sha`), `docs/bugs/2026-10-18-live-evidence-stale-when-fix-commit-defaults-to-squash-merge.md` (added the `**Fix commit:**` header)

## Problem

v1.43.4 defined `fix_sha` as the commit that changed the doc's Status to FIXED, read from
`fixed_in[path]["commit"]`. The `**Fix commit:**` header came later and names the code fix; 95 bug docs
now carry it. The table still ignores it. On 2026-10-25 (screenshot 284):

| Bug | Table shows | Header says |
|---|---|---|
| claude-tokens-per-day-no-cache-kind-breakdown | `32f1ee64` (docs: fix recorded) | `79fab0b1` |
| codex-activity-files-dispatch-worktrees-under-other | `be51473b` (docs) | `9cb1fa09` |
| deploy-vault-rejected-unseal-cache-triggers-destructive-reinit | `20b02234` (docs) | `f11e0c6e` |

Separately, `_FIX_COMMIT_RE` requires the line to end after the SHA, so three headers return `None`:
`` `a8909477` (v1.43.4 squash; ...) ``, `17c7cda5, 152f7978`, and `` `f11e0c6e` (Claude moved ...) ``.
The live-evidence check then falls back to the status-flip commit too.

## Fix

### F1. Parse a header with a trailing note or a list

`doc_fix_commit` returns the first SHA on the `**Fix commit:**` line when the value starts with a
SHA (optionally in backticks), whatever follows it: a parenthesised note, or `, <sha>`. A value
that does not start with a 7–40 character lowercase hex SHA still returns `None`.

### F2. `fix_sha` prefers the header

In `bin/k3dm-vectordb-metrics`, for a fixed bug, `fix_sha` = the first 8 characters of
`doc_fix_commit(text)` when it returns a SHA, else today's `fixed_in[path]["commit"]`. Keep the existing
`[0-9a-f]{8}|-` validation. **Fixed in** (release) and `verified_sha` are unchanged.

### F3. Wording

The Bug Tracking **Bugs** panel description and `docs/guides/grafana-dashboards.md`: Fix commit is the
`**Fix commit:**` header when the doc has one, otherwise the commit that marked it fixed.

## Tests

In `scripts/tests/bin/test_vectordb_bug_metrics.py`:

1. A fixed doc with `` **Fix commit:** `79fab0b1` `` and a `fixed_in` commit `32f1ee64...` → `fix_sha="79fab0b1"`.
2. Same, header `` **Fix commit:** `f11e0c6e` (a note) `` → `fix_sha="f11e0c6e"`; header `17c7cda5, 152f7978` → `17c7cda5`.
3. A fixed doc with no header → today's `fixed_in` commit (the existing `01234567` test stays green).
4. A header whose value is not a SHA (`**Fix commit:** pending`) → falls back to `fixed_in`.
5. An open doc with a header → `fix_sha="-"`.
6. `doc_fix_commit` on the three header forms in F1, and `None` for `pending`.

Tests 1, 2 and 6 must be red on a temp copy of the pre-fix files.

## Files

- `bin/k3dm-vectordb-metrics`
- `scripts/lib/hermes/prior_art.py`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml` (Bugs panel description only)
- `scripts/tests/bin/test_vectordb_bug_metrics.py`
- `docs/guides/grafana-dashboards.md`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: For a fixed bug whose doc has a **Fix commit:** header starting with a SHA, k3dm_bug_info fix_sha is the first 8 characters of that SHA.
  - id: M2
    text: A header with a trailing note or a comma-separated list yields its first SHA.
  - id: M3
    text: A fixed bug with no usable header keeps today's fix_sha (the commit that marked it fixed).
  - id: M4
    text: The Bugs panel description and the guide say where Fix commit comes from.
must_not:
  - id: N1
    text: No change to fixed_in, verified_sha, live_evidence for docs whose header already parsed, or any other label or series.
  - id: N2
    text: An open bug never gets a fix_sha other than "-".
  - id: N3
    text: A non-SHA header value never becomes a label value.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, M4, N1, N2, N3]
    text: pytest scripts/tests/bin/test_vectordb_bug_metrics.py green with K3DM_VECTORDB_PUSHGATEWAY_URL=http://127.0.0.1:9; tests 1, 2 and 6 red on a temp copy of the pre-fix files; make validate-manifests passes.
  - id: E2
    kind: live
    proves: [M1, M2]
    text: After the next bug scan and dashboard sync, the operator's Bug Tracking screenshot at v1.43.7 shows Fix commit 79fab0b1, 9cb1fa09 and f11e0c6e for the three bugs in the Problem table.
interface:
  - scripts/lib/hermes/prior_art.py doc_fix_commit(text)
  - bin/k3dm-vectordb-metrics bug metrics rendering, as test_vectordb_bug_metrics.py drives it
  - k3dm_bug_info label fix_sha
```

## Definition of Done

- [ ] F1–F3 and a CHANGELOG `[Unreleased]` `### Fixed` entry; only the Files above change.
- [ ] E1 green; paste the summaries.
- [ ] Tests 1, 2 and 6 shown red on a temp copy of the pre-fix files.
- [ ] Commit: `fix(bugs): Fix commit column prefers the doc's Fix commit header`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT edit any `docs/bugs/` file to normalise its header.
- Do NOT push to the real Pushgateway; tests use `http://127.0.0.1:9`.
- Do NOT change or remove existing tests or assertions.
- Do NOT modify files outside the Files list.
