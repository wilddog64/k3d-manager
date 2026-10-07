# Failed Make-job tail omits the diagnostic failure context

## Status

OPEN — queued for follow-up after the live Make-log retrieval fix.

## Evidence

Live verification on 2026-10-07 showed that failed job `ccc20dc9` now returns a
non-empty `body.output`, but the bounded tail ends with:

```text
Test log saved to scratch/test-logs/all/20261006-093931.log
Collected artifacts in scratch/test-logs/all/20261006-093931
[tripwire] blocked 244 call(s) to host tools; none reached a real binary:
...
make: *** [test] Error 1
```

The returned tail proves the job failed, but omits the earlier `not ok` test name,
assertion, and surrounding diagnostics needed to investigate the failure.

## Impact

Cloud and Slack requestors can see that `make-test-all` failed but cannot determine
which test failed from `job-status`, `logs`, or `diagnosis` output. Operators must
manually locate the host-side scratch log or rerun the suite.

## Scope

Improve failure evidence without publishing raw unbounded logs. Candidate approaches
include a failure-aware bounded excerpt, preserving the first failing test plus the
final tail, and links or references to retained redacted artifacts. Keep credentials,
tripwire noise, and high-cardinality raw logs out of permanent cloud responses.

## Acceptance criteria

- A failed Make job returns the failing target/test name and a bounded relevant error
  excerpt, plus the existing final tail when useful.
- Passing jobs retain the current compact tail behavior.
- Output is redacted, size-bounded, and consistent across `job-status`, Slack `logs`,
  and Slack `diagnosis`.
- Tests cover a failure whose cause appears before the final 2,000 characters.
- The failure-evidence design is coordinated with
  `docs/plans/v1.43.0-e2e-failure-artifacts.md` where artifact retention overlaps.
