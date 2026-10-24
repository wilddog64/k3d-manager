# Bug: a LIVE-VERIFIED doc reads "stale proof" when its fix commit defaults to the release's squash merge

**Filed:** 2026-10-18 (Claude, from the operator's question about the Bugs dashboard's Open for column)
**Status:** FIXED
**Fix commit:** `6d8bd118`
**Priority:** P3 — a dashboard row reports correct proof as stale; no runtime impact
**Severity:** low
**Approval:** approved — operator, 2026-10-18: "go ahead to open P3 bug"
**Branch:** `k3d-manager-v1.43.5`
**Release:** v1.43.5
**Component:** `scripts/check-bug-evidence.py`, `scripts/tests/bin/test_check_bug_evidence.py`,
`docs/guides/grafana-dashboards.md`, and two bug docs (F2)

## Symptom

On the k3dm Bug Tracking dashboard, two v1.43.4 bugs that were live-verified on 2026-10-18 keep counting
in **Open for** (1 d), while a LIVE-VERIFIED row with accepted proof shows `—`:

- `docs/bugs/2026-10-17-grep-q-pipeline-sigpipe-false-absent.md` — evidence commit `0fc16826`
- `docs/bugs/2026-10-17-hostinger-vault-sealed-after-reboot-no-unseal-watchdog.md` — evidence commit `a1c2f800`

Both evidence commits **are** the code fix. The proof is correct, and the dashboard calls it stale.

## Root cause

`bin/k3dm-vectordb-metrics` decides `live_evidence` by asking whether an evidence commit contains the
fix commit (`git merge-base --is-ancestor <fix> <evidence>`). The fix commit is the doc's
`**Fix commit:**` header if present, else the tally's proxy from `bug-tally.py`, which for a
squash-merged release is the squash commit on `main` (`a8909477` for v1.43.4).

Neither doc has a `**Fix commit:**` header. Their evidence commits are release-branch commits from
before the squash, and a pre-squash branch commit can never have the squash commit as an ancestor. So
both scan `stale`, and per the v1.43.4 rule a stale LIVE-VERIFIED row keeps counting Open for.

The header that prevents this already exists (added in the v1.43.4 verification notes for exactly
this case). Nothing requires it: `scripts/check-bug-evidence.py`, the pre-commit gate, checks only
that a well-formed `**Live evidence:**` line is present, not that it would scan `ok`. An author
verifying after the release merged gets a green commit and a red dashboard row.

## Fix

### F1. Pre-commit gate rejects proof that would scan stale

In `scripts/check-bug-evidence.py`, for a doc that newly becomes LIVE-VERIFIED (the existing
`HEAD` comparison), after the existing presence check:

- Resolve the fix commit the same way the exporter does: `doc_fix_commit(text)` from
  `scripts/lib/hermes/prior_art.py`. If the doc has none, fail with:
  `<path>: LIVE-VERIFIED needs a **Fix commit:** <sha> line naming the commit that fixed it`.
  (The tally proxy is not available at commit time and is the cause of this bug, so the gate does not
  fall back to it.)
- For each well-formed evidence line, run `git merge-base --is-ancestor <fix> <evidence-commit>`.
  rc 0 for any line passes. rc 1 for every line fails with
  `<path>: no **Live evidence:** commit contains the fix commit <fix>`.
- rc other than 0/1 (a commit git cannot resolve, such as an evidence commit in another repo) does not
  fail the gate. This matches the exporter's `unchecked`.
- `K3DM_SKIP_BUG_EVIDENCE=1` keeps bypassing the whole gate, unchanged.

Reuse the exporter's ancestry semantics; do not import from `bin/`. A small helper in
`scripts/check-bug-evidence.py` is fine.

### F2. Backfill the two docs

Add directly under `**Priority:**`:

- grep doc: `**Fix commit:** \`0fc16826\``
- Vault doc: `**Fix commit:** \`a1c2f800\``

Both are on `origin/k3d-manager-v1.43.4` and the `v1.43.4` tag's branch history, so they stay resolvable.

### F3. Guide

In `docs/guides/grafana-dashboards.md`, in the paragraph on `**Fix commit:**`, state that the
pre-commit gate now requires it for a new LIVE-VERIFIED doc and checks that an evidence commit
contains it.

## Files

- `scripts/check-bug-evidence.py`
- `scripts/tests/bin/test_check_bug_evidence.py`
- `docs/guides/grafana-dashboards.md`
- `docs/bugs/2026-10-17-grep-q-pipeline-sigpipe-false-absent.md`
- `docs/bugs/2026-10-17-hostinger-vault-sealed-after-reboot-no-unseal-watchdog.md`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: A doc newly made LIVE-VERIFIED with a **Fix commit:** that is an ancestor of (or equal to) an evidence commit passes the gate (exit 0).
  - id: M2
    text: After F2, the grep and Vault docs scan live_evidence="ok" and Open for value -2 in bin/k3dm-vectordb-metrics on the real tree.
  - id: M3
    text: An evidence commit git cannot resolve (rc not 0/1) does not fail the gate.
  - id: M4
    text: The guide sentence in F3 exists.
must_not:
  - id: N1
    text: A doc newly made LIVE-VERIFIED without a **Fix commit:** line must not pass the gate (red on pre-fix, which passes it).
  - id: N2
    text: A doc whose evidence commits all resolve but none contains the fix commit must not pass the gate (red on pre-fix).
  - id: N3
    text: A doc already LIVE-VERIFIED at HEAD must not be re-checked; existing docs must not start failing commits that do not change their Status.
  - id: N4
    text: K3DM_SKIP_BUG_EVIDENCE=1 must still bypass the gate.
evidence:
  - id: E1
    proves: [M1, M3, N1, N2, N3, N4]
    kind: offline
    text: pytest on the hook with a throwaway git repo built in tmp_path (fix commit, evidence commit after it, an unrelated commit, an unknown SHA); N1 and N2 shown red against the pre-fix scripts/check-bug-evidence.py.
  - id: E2
    proves: [M2]
    kind: offline
    text: run the exporter's row function against the real tree for the two docs and print live_evidence and value.
  - id: E3
    proves: [M2]
    kind: live
    text: after Hermes's next poll on k3d-manager-v1.43.5, both rows on the hub Bugs dashboard show Open for "—".
interface:
  - python3 scripts/check-bug-evidence.py <paths...> (exit code, stderr)
  - env K3DM_SKIP_BUG_EVIDENCE
  - doc headers **Status:**, **Fix commit:**, **Live evidence:**
  - make check-bug-evidence
```

## Definition of Done

- [ ] F1–F3 on `k3d-manager-v1.43.5`; only the Component files changed.
- [ ] E1 and E2 pass; N1 and N2 shown red against the pre-fix hook.
- [ ] `make check-bug-evidence` still exits 0 on the whole tree.
- [ ] Commit message: `fix(bug-evidence): require a fix commit the live evidence contains`
- [ ] Pushed to `origin/k3d-manager-v1.43.5`; report the SHA.

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT change `bin/k3dm-vectordb-metrics` or the dashboard's stale/unchecked semantics.
- Do NOT modify files outside the Component list.
- Do NOT commit to `main`.

## Notes

- An evidence commit from another repo (the Dependabot bug cites `shopping-cart-frontend`'s
  `bf119607`) scans `unchecked` and shows `—`, the same as `ok`. That is the documented v1.43.4 rule
  and is out of scope here.
- 2026-10-18: fix `6d8bd118` (Codex) and test fix `9be4f2e3` had landed earlier; the dispatcher re-run added only the missing CHANGELOG entry (`a4c9b426`). `test_check_bug_evidence.py` passes on landing.
