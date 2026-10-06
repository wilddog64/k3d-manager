# Bug: the data-layer explainer's truncation test can never fail

**Status:** FIXED
**Filed:** 2026-10-05
**Branch:** `k3d-manager-v1.41.0`
**Severity:** Low — test-only; the truncation it claims to guard is unguarded
**Files:** `scripts/tests/bin/cluster_up.bats`

Related: `docs/bugs/2026-10-05-cluster-up-data-layer-wait-silent-on-cause.md` (test 3 of that
spec), fixed in `427f4e0f`.

## Symptom

Claude's verification of `427f4e0f`:

- Against the **pre-fix** `bin/cluster-up` (no `_acg_data_layer_explain` at all), the test
  `acg-up data-layer explanation truncates long operation messages` passes. The spec required
  it to be RED.
- Mutating `${_msg:0:400}` to `${_msg}` (no truncation) leaves it green: `ok 1`.

## Root cause

The test body runs inside `bash -c`, calls `_acg_data_layer_explain data-layer`, and then counts
`x` characters in `"$output"`:

```bash
    _acg_data_layer_explain data-layer
    x_count=$(printf "%s\n" "$output" | tr -cd x | wc -c)
    [ "$x_count" -le 400 ]
```

`$output` is BATS's variable and is only set by `run` in the outer test. Inside the `bash -c`
child it is unset, so the function's output is never captured. `x_count` is always 0, and
`0 -le 400` is always true. An upper bound with no lower bound also passes when nothing is
printed at all.

## Fix spec

### File 1 — `scripts/tests/bin/cluster_up.bats`

In the test `acg-up data-layer explanation truncates long operation messages`, replace:

```bash
    _acg_data_layer_explain data-layer
    x_count=$(printf "%s\n" "$output" | tr -cd x | wc -c)
    [ "$x_count" -le 400 ]
```

with:

```bash
    explain_out=$(_acg_data_layer_explain data-layer 2>&1)
    [[ "$explain_out" == *"last sync operation: "* ]]
    x_count=$(printf "%s\n" "$explain_out" | tr -cd x | wc -c)
    [ "$x_count" -eq 400 ]
```

Before relying on this, confirm by reading `scripts/lib/system.sh` whether `_warn` writes to stdout
or stderr. The `2>&1` covers both. Check that no other word in the `_warn` output contains a
lowercase `x`. The prefix `[acg-up] data-layer last sync operation: ` contains none. If
`_warn` adds a prefix that does contain one, strip the line up to `operation: ` before counting
(for example, `${explain_out#*operation: }`) rather than loosening the assertion.

Change nothing else in the file.

## Definition of Done

- [ ] Mutation 1: change `${_msg:0:400}` to `${_msg}` in `bin/cluster-up`, and the test goes
      **RED**. Restore from a `$TMPDIR` snapshot and prove it with `cmp`.
- [ ] Mutation 2: extract the test against `HEAD~1`'s `bin/cluster-up` (no explainer). Use a temp
      copy of the file, never `git checkout`. The test goes **RED**.
- [ ] `bats scripts/tests/bin/cluster_up.bats` green; paste the counts.
- [ ] This file: flip **Status** to FIXED.
- [ ] Changes left **unstaged**. Claude verifies and commits.

## What NOT to do

- Do NOT modify `bin/cluster-up` (except the temporary mutation, restored and `cmp`-verified).
- Do NOT touch any other test or file. No commit, push, PR or `--no-verify`.
