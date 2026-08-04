# CI regression: stale-ref fixture tests fail on fresh clones after branch cleanup

**Date:** 2026-08-03
**Surfaced by:** PR #110 (v1.21.0 webhook hardening) — first CI run since the v1.20.0 branch cleanup
**Branch:** `k3d-manager-v1.21.0`
**File:** `scripts/tests/lib/stale_test_refs.bats`

---

## Symptom

The `lint` job's BATS suite failed on two tests:

```
not ok 211 stale-ref check flags the f03df202 data-layer rename
  # (in test file scripts/tests/lib/stale_test_refs.bats, line 11)
  #   `[ "${status}" -eq 1 ]' failed
not ok 212 stale-ref check flags the 4c89dabb trivy split
  # (in test file scripts/tests/lib/stale_test_refs.bats, line 17)
  #   `[ "${status}" -eq 1 ]' failed
```

The tests passed locally but failed in CI — the classic "works on my machine" split.

## Root cause

`stale_test_refs.bats` (added in v1.16.0, #106) runs `check-stale-test-refs.sh` against three
**hard-coded historical commit SHAs** — `f03df202`, `4c89dabb`, `e3a75f1f` — and asserts the check's
exit status. Those commits lived on feature branches, **not** on `main`'s linear history (releases are
squash-merged, so the original pre-squash commits are never ancestors of `main`).

The v1.20.0 close-out **deleted 30 merged/superseded branches** (2026-08-01 branch-cleanup pass). That
cleanup removed the last refs reachable to `f03df202` / `4c89dabb` / `e3a75f1f`, **orphaning** them.

- **Locally** the commits survive as loose objects (not yet GC'd), so `git diff f03df202^..f03df202`
  works and the check flags the stale ref → exit 1 → test passes.
- **In CI** (`actions/checkout` with `fetch-depth: 0`) a fresh clone fetches only what is reachable from
  the fetched refs. The orphaned SHAs are unreachable, so `git diff <orphaned-sha>` prints
  `fatal: bad revision` and — because `check-stale-test-refs.sh` wraps the range in `... || true` — the
  check silently finds no diff and **exits 0**, tripping the `[ "${status}" -eq 1 ]` assertion.

#109's CI (headSha `d0084328`, 2026-08-01T11:51) was green because the fixture branches still existed at
that moment; the cleanup ran the same day, so PR #110 is the first CI run to see the orphaned state.

## Fix applied

Guard each fixture test to `skip` when its commit is not reachable in the current clone, so a fresh CI
clone is green while local runs (where the objects still exist) keep exercising the check:

```bash
_require_commit() {
  git rev-parse --verify --quiet "${1}^{commit}" >/dev/null \
    || skip "fixture commit ${1} not reachable in this clone (orphaned by branch cleanup)"
}
```

`_require_commit <sha>` is called at the top of all three fixture tests. The `e3a75f1f` "quiet" test was
guarded too — it had been passing for the *wrong* reason (bad-revision → the check's `|| true` → exit 0
matches the expected 0).

## Process note / follow-up

- **Test-fixture fragility:** hard-coding external historical SHAs couples a test's liveness to branch
  retention. Any branch-cleanup pass can silently orphan them. The durable fix is a **self-contained
  fixture** — build a throwaway git range inside the test (init a temp repo, add an `etc/` string a
  `tests/` file asserts, commit its removal, run the check on that range) so the test never depends on
  repo history. Deferred as follow-up to keep this PR minimal.
- **`check-stale-test-refs.sh` swallows bad ranges:** a bad revision resolves to "no stale references"
  (exit 0) instead of erroring. Harmless for the real pre-commit/pre-push caller (always `HEAD^..HEAD`),
  but it is why the failure was a silent false-pass rather than a loud error. Left unchanged (out of
  scope; changing it risks the hook path).
- **Branch-cleanup checklist:** when deleting branches, note that any test fixture referencing a
  soon-to-be-unreachable SHA will start failing on fresh clones even though it passes locally.
