# Bug: 4 `vcluster.bats` orphan tests fail because their seed is still the old table listing

**Filed:** 2026-10-02
**Status:** FIXED (bd88be39)
**Branch:** `k3d-manager-v1.40.0`
**File:** `scripts/tests/plugins/vcluster.bats` (`_seed_orphan_listing`)
**Introduced by:** `5706eb21 fix(vcluster): reconcile orphans from vcluster list JSON, not the table`

## Symptom

`bats scripts/tests/plugins/vcluster.bats` (30 tests) reports 4 failures, on `7ce184e5` and on the commit
before it:

```
not ok vcluster_create deletes an orphan occupying the shared namespace
not ok vcluster_create deletes the orphan before creating the new vCluster
not ok vcluster_create warns when it clears an orphan so a teardown regression stays visible
not ok orphan cleanup falls back to helm uninstall when vcluster delete fails
```

## Root cause

`5706eb21` changed `_vcluster_reconcile_namespace` to read `vcluster list --output json` and parse
`.[]?.Name` with `jq`. It added new tests in `vcluster_reconcile_namespace.bats`, but left
`_seed_orphan_listing` in `vcluster.bats` producing the old table:

```bash
export VCLUSTER_LIST_OUTPUT="NAME                  NAMESPACE   STATUS    AGE
${1} vclusters   Running   131m"
```

`jq` cannot parse that, so no orphan is found and nothing is deleted. The test
"does not delete a vCluster matching the name being created" passes only because nothing is ever
parsed, so today it proves nothing.

The production code is correct. The reconcile fix was confirmed live in run 1790958376-31051. Only the
test seed is stale. When `5706eb21` was verified, only `vcluster_reconcile_namespace.bats` was run, so this
was missed.

## Fix

In `scripts/tests/plugins/vcluster.bats`:

Old:
```bash
_seed_orphan_listing() {
  export VCLUSTER_LIST_OUTPUT="NAME                  NAMESPACE   STATUS    AGE
${1} vclusters   Running   131m"
}
```
New:
```bash
_seed_orphan_listing() {
  export VCLUSTER_LIST_OUTPUT="[{\"Name\":\"${1}\",\"Namespace\":\"vclusters\",\"Status\":\"Running\"}]"
}
```

Leave the table outputs at the `vcluster_list` tests (around lines 114 and 130) as they are. Those test
the human-readable listing, not reconcile.

## Gate

- `bats scripts/tests/plugins/vcluster.bats`: **0 failures** (30/30); paste the summary.
- `bats scripts/tests/plugins/vcluster_reconcile_namespace.bats`: still green.

**Mutation check (must report):** in `scripts/plugins/vcluster.sh`, temporarily change `.[]?.Name` to
`.[]?.name`. The orphan tests must go red, which proves they now exercise the JSON path. Restore it,
check with `git diff --quiet scripts/plugins/vcluster.sh`, and the suite is green again.

## Definition of Done

- [ ] Fix applied exactly as written
- [ ] Both suites green; mutation result reported
- [ ] Status line set to `FIXED (<short sha>)`
- [ ] Commit message: `test(vcluster): seed the orphan listing as vcluster list JSON`
- [ ] Pushed to `origin/k3d-manager-v1.40.0`; report `git rev-parse origin/k3d-manager-v1.40.0`

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify `scripts/plugins/vcluster.sh` (except for the temporary mutation, which must be restored)
- Do NOT modify files other than `vcluster.bats` and this doc
- Do NOT run `make e2e`
- Do NOT commit to `main`
