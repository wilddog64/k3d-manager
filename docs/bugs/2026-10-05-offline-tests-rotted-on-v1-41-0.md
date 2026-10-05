# Bug: two offline tests rotted on `k3d-manager-v1.41.0`, and the nightly run caught them

**Status:** FIXED
**Filed:** 2026-10-05
**Branch:** `k3d-manager-v1.41.0`
**Severity:** Medium. `OfflineSuiteFailing` and `OfflineSuiteCaseCountDropped` fire on
`ubuntu-hostinger`, and CI will be red when the release PR opens.
**Files:** `scripts/tests/plugins/hub_pushgateway.bats`, `scripts/tests/bin/make_lifecycle.bats`

## Symptom

The nightly `make test-metrics` run (launchd `com.k3d-manager.test-metrics`) at 2026-10-05 04:37
pushed `k3dm_test_cases_failed=1` and `k3dm_test_cases_total=1354`. The log is
`$TMPDIR/k3dm-test-all-1791199805.log`:

```
not ok 902 only the two vectordb publishers left the app-cluster Pushgateway
# (in test file scripts/tests/plugins/hub_pushgateway.bats, line 52)
make[1]: *** [test] Error 1
```

`make test` failed, so `test-bin` and the Python suites never ran. That alone explains the drop
to 1354 cases: `OfflineSuiteCaseCountDropped` is a consequence of this failure, not a separate
defect.

The 10-04 run (`k3dm-test-all-1791113405.log`) also reached `test-bin` and failed there:

```
not ok 188 make down gates stale cleanup behind CLEANUP_STALE
#   `[[ "$output" == *'_keep_hub_flag=--keep-hub'* ]]' failed
```

That one still reproduces: `bats scripts/tests/bin/make_lifecycle.bats` gives `not ok 14`.
The other 10-04 failure (`k3dm_cleanup.bats`, `stat -c`) no longer reproduces.

## Root cause

Both tests assert exact source text that a later commit on this branch changed on purpose:

1. **`hub_pushgateway.bats:52`** pins the exact list of files containing `localhost:9091`.
   `4547e696` (2026-10-05 04:34, three minutes before the nightly run) moved the sandbox
   Pushgateway port-forward to `9092`, and `smoke.py` now builds the port at runtime. Those two
   files left the list, as intended. The test was not updated.
2. **`make_lifecycle.bats:17–18`** asserts two recipe lines that `435c95a1` replaced when
   `make down` began keeping the hub by default (`_DOWN_HUB_FLAG`). The behaviour the test protects,
   "`CLEANUP_STALE=1` preserves the hub", still holds; only the text moved:

   ```
   make -s down-hub-flag                              -> ""
   make -s down-hub-flag CLEANUP_STALE=1 DELETE_HUB=1 -> ""
   make -s down-hub-flag DELETE_HUB=1                 -> "--delete-hub"
   make -s down-hub-flag KEEP_LOCAL=0                 -> "--delete-hub"
   ```

Neither commit ran the full `test` + `test-bin` gate, and branch pushes don't trigger CI, so
the nightly run was the first thing to notice.

## Fix spec

### File 1 — `scripts/tests/plugins/hub_pushgateway.bats`

Replace:

```bash
  [ "${output}" = "$(printf '%s\n' bin/cluster-up bin/k3dm-test-metrics scripts/lib/webhook/config.py scripts/lib/webhook/smoke.py)" ]
```

with:

```bash
  [ "${output}" = "$(printf '%s\n' bin/k3dm-test-metrics scripts/lib/webhook/config.py)" ]
  run git grep -n 'localhost:9091' -- bin/cluster-up
  [ "${status}" -ne 0 ]
```

### File 2 — `scripts/tests/bin/make_lifecycle.bats`

In `make down gates stale cleanup behind CLEANUP_STALE`, replace:

```bash
  [[ "$output" == *'_keep_hub_flag=--keep-hub'* ]]
  [[ "$output" == *'if [ "$(KEEP_LOCAL)" = "1" ] || [ "$(CLEANUP_STALE)" = "1" ]; then'* ]]
}
```

with:

```bash
  run make -s down-hub-flag
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run make -s down-hub-flag CLEANUP_STALE=1 DELETE_HUB=1
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run make -s down-hub-flag DELETE_HUB=1
  [ "$status" -eq 0 ]
  [ "$output" = "--delete-hub" ]
}
```

Flip this file's **Status** to FIXED. No CHANGELOG entry is needed, because this change is
test-only.

## Definition of Done

- [ ] Both tests are RED at `HEAD` before the change (paste output).
- [ ] Mutation 1: temporarily add `# localhost:9091` as a comment line at the end of
      `bin/cluster-up`. The pushgateway test goes red. Restore from a `$TMPDIR` snapshot and
      prove it with `cmp`.
- [ ] Mutation 2: in `Makefile`, make `_DOWN_HUB_FLAG` ignore `CLEANUP_STALE` by deleting the
      outer `$(if $(filter 1,$(CLEANUP_STALE)),,` wrapper and its matching `)`. The lifecycle
      test goes red. Restore from a snapshot and prove it with `cmp`.
- [ ] `make test` and `make test-bin` are both green. They take about 15 minutes, so run them in
      the background and read the counts, not the exit code alone. Paste the `1..N` and the
      `not ok` lines (none expected).
- [ ] Changes are left **unstaged**. Claude verifies and commits.

## What NOT to do

- Do NOT change `Makefile`, `bin/cluster-up` or `smoke.py`, except for the mutations, which must
  be restored and `cmp`-verified.
- Do NOT delete either test or loosen it to a status-only check.
- Do NOT touch files outside those listed. No commit, push, PR or `--no-verify`.
