# Bug: e2e harness — dispatch

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-30 by k3dm-hermes
**Status:** FIXED — Codex, verified by Claude 2026-10-04: the gate uses the mean of 5 CPU samples, and only `capacity_*` refusals are retried (`E2E_M2_CAPACITY_RETRIES=2`, 120 s apart). `e2e_remote.bats` 87/87; both mutations (gate on the minimum; retry every refusal) turn tests red.
**Run:** `unknown`, runner `m2`, tier `vcluster`, 0 passed / 1 failed / 1 total
**Runner commit:** `unknown`

## Failing tests (1)
- …and 1 more

## Sample errors
- running under bash version 5.3.20(1)-release
reason=CPU idle 64.4%/31.92% below floor 35%
status=capacity_cpu
ERROR: [e2e-remote] runner m2 not available (status=capacity_cpu); not dispatching, no local fallback (rc=1)

## Triage hint
the run did not reach Playwright; read the dispatch transcript.

## Next step
A human (or Claude) verifies the root cause, then writes the fix spec here before any code change.

## Recurrence 2026-10-03 (run unknown)

1 failing test(s).
- …and 1 more

- running under bash version 5.3.20(1)-release
reason=CPU idle 71.74%/32.98% below floor 35%
status=capacity_cpu
ERROR: [e2e-remote] runner m2 not available (status=capacity_cpu); not dispatching, no local fallback (rc=1)

## Root cause (Claude, 2026-10-04)

The run is not failing; it is never dispatched. `_e2e_remote_eval_gates`
(`scripts/plugins/e2e_remote.sh:215`) refuses the runner when **either** of two CPU samples is
below `E2E_M2_MIN_CPU_IDLE` (35%). `_e2e_remote_probe` takes those samples with
`top -l 3 -n 0 -s 1`, so each one covers a single second. Both recorded refusals had one sample
well above the floor and one just below it: 64.4/31.92 on 2026-09-30, and 71.74/32.98 on
2026-10-03. A one-second dip on a mostly idle Mac skipped the run, and the next slot is three
or four days later.

## Fix spec

### File 1 — `scripts/plugins/e2e_remote.sh`

1. **More samples.** In `_e2e_remote_probe`, change `top -l 3 -n 0 -s 1` to
   `top -l 6 -n 0 -s 1`. The loop already drops the first (since-boot) reading, so it now emits
   `cpu_idle2` … `cpu_idle6`.
2. **Gate on the mean.** In `_e2e_remote_eval_gates`, replace the `cpu2` / `cpu3` reads and the
   CPU `if` with a mean over every `cpu_idle<N>=` line in the blob:

```bash
  local cpu_samples cpu_mean
  cpu_samples="$(awk -F= '/^cpu_idle[0-9]+=/{printf "%s%s", sep, $2; sep="/"}' <<<"$blob")"
  cpu_mean="$(awk -F= '/^cpu_idle[0-9]+=/{s+=$2; n++} END{if (n) printf "%.1f", s/n; else print 0}' <<<"$blob")"
```

   and

```bash
  if _e2e_num_lt "$cpu_mean" "$E2E_M2_MIN_CPU_IDLE"; then
    printf 'reason=%s\nstatus=capacity_cpu\n' "CPU idle mean ${cpu_mean}% (samples ${cpu_samples:-none}) below floor ${E2E_M2_MIN_CPU_IDLE}%"
    return 1
  fi
```

   The `available` line becomes
   `printf 'cpu_idle=%s (samples %s)\nmem_free=%s\ndisk_gb=%s\nstatus=available\n' "${cpu_mean}" "${cpu_samples}" "${mem}" "${disk}"`.
   Remove the now-unused `cpu2 cpu3` locals.
3. **Retry a capacity refusal.** Add, after `e2e_runner_preflight`:

```bash
# Capacity is transient (a Spotlight or backup burst); docker_down, busy and
# unreachable are not, so only capacity_* refusals are retried.
function _e2e_remote_preflight_with_retry() {
  local pf status attempt=0
  while :; do
    if pf="$(e2e_runner_preflight)"; then
      printf '%s\n' "$pf"
      return 0
    fi
    status="$(_e2e_kv "$pf" status)"
    if [[ "$status" != capacity_* ]] || (( attempt >= E2E_M2_CAPACITY_RETRIES )); then
      printf '%s\n' "$pf"
      return 1
    fi
    attempt=$(( attempt + 1 ))
    _warn "[e2e-remote] runner ${E2E_M2_SSH_HOST} refused (status=${status}); retry ${attempt}/${E2E_M2_CAPACITY_RETRIES} in ${E2E_M2_CAPACITY_RETRY_INTERVAL}s" >&2
    sleep "$E2E_M2_CAPACITY_RETRY_INTERVAL"
  done
}
```

   In `e2e_runner_dispatch`, change `if ! pf="$(e2e_runner_preflight)"; then` to
   `if ! pf="$(_e2e_remote_preflight_with_retry)"; then`. Nothing else in dispatch changes.
4. **Config.** Next to `E2E_M2_MIN_DISK_GB=` add
   `E2E_M2_CAPACITY_RETRIES="${E2E_M2_CAPACITY_RETRIES:-2}"` and
   `E2E_M2_CAPACITY_RETRY_INTERVAL="${E2E_M2_CAPACITY_RETRY_INTERVAL:-120}"`, and add both names
   to the `export E2E_M2_MIN_CPU_IDLE …` line.

### File 2 — `scripts/tests/plugins/e2e_remote.bats`

1. Replace the test "eval_gates fails on low CPU idle in either sample" with
   "eval_gates fails when the mean CPU idle is below the floor": samples `40 20 30 25 30`
   (mean 29) → non-zero, `status=capacity_cpu`, output contains `mean 29.0%`.
2. New: "one dipped sample does not refuse a mostly idle runner": `cpu_idle2=64.4`,
   `cpu_idle3=31.92` (the 2026-09-30 values; mean 48.2) → status 0, `status=available`.
3. New: a blob with no `cpu_idle` lines → `status=capacity_cpu`.
4. New: `_e2e_remote_preflight_with_retry` with a stub `e2e_runner_preflight` that returns
   `status=capacity_cpu` (rc 1) on the first call and `status=available` (rc 0) on the second
   (count calls in a file under `$BATS_TEST_TMPDIR`), `E2E_M2_CAPACITY_RETRY_INTERVAL=0` →
   status 0 and 2 calls.
5. New: same helper, the stub always returns `status=busy` → status 1 after exactly 1 call.
6. New: the stub always returns `capacity_mem`, `E2E_M2_CAPACITY_RETRIES=2` → status 1 after
   exactly 3 calls.
7. Static: `e2e_runner_dispatch` calls `_e2e_remote_preflight_with_retry`, and `_e2e_remote_probe`
   contains `top -l 6`.

Keep `_healthy_blob` and the other existing tests unchanged.

### File 3 — `docs/guides/vcluster-e2e-harness.md`

No guide documents the M2 runner's capacity gate today. Add a short section
`## M2 runner capacity gate` at the end of the file: it lists the four refusal statuses
(`docker_down`, `busy`, `capacity_cpu` / `capacity_mem` / `capacity_disk`, `unreachable`), says the
CPU floor `E2E_M2_MIN_CPU_IDLE` (35) is compared with the mean of 5 one-second samples, and that
only `capacity_*` refusals are retried, `E2E_M2_CAPACITY_RETRIES` (2) times,
`E2E_M2_CAPACITY_RETRY_INTERVAL` (120) seconds apart. Link this bug doc.

## Rules

- Modify only Files 1–3. Do not touch `scripts/lib/foundation/` or other plugins.
- Do not commit or push; leave changes unstaged.
- Run and paste: `shellcheck scripts/plugins/e2e_remote.sh` (no new warnings versus
  `git show HEAD:scripts/plugins/e2e_remote.sh | shellcheck -`), `bats scripts/tests/plugins/e2e_remote.bats`,
  `bats scripts/tests/lib/bats_negation_lint.bats`.
- Mutations (snapshot to `$TMPDIR`, restore, `cmp`):
  1. Gate on the minimum sample instead of the mean → test 2 red.
  2. Retry every refusal, not only `capacity_*` → test 5 red.
- Do not run `make test`. Never SSH to the runner.

## Done when

A single dipped sample no longer refuses the runner, a capacity refusal is retried twice with a
pause before the run is given up, other refusals are not retried, and the tests and mutations
above hold.
