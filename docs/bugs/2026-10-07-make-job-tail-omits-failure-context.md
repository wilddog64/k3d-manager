# Failed Make-job tail omits the diagnostic failure context

## Status

FIXED and live-verified on `k3d-manager-v1.42.0`.

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
  `docs/plans/v1.48.0-e2e-failure-artifacts.md` where artifact retention overlaps.

## Resolution

`read_job_output` now recognizes failed Make jobs, preserves a bounded early failure
context excerpt, and appends the final output tail. Passing jobs and non-Make jobs keep
their existing tail behavior. The result is still redacted and size-bounded, so the
same selector serves cloud `job-status`, Slack `logs`, and Slack `diagnosis` safely.

Verification: focused output/lifecycle/status tests passed 24/24; `make test-python-unit`
passed; `make test-pytest` passed 696 with 2 skipped. An initial focused run exposed a
fixture without a `status` file; the selector was corrected to treat that as a non-failed
job, and the full focused suite then passed.

Live verification then queried failed job `ccc20dc9` after restarting the webhook and
cloud bridge. The returned `body.output` included:

```text
not ok 198 deploy_observability calls envsubst with $ARGOCD_NAMESPACE and $K3D_MANAGER_BRANCH
not ok 200 deploy_observability_acg falls back to generated Prometheus config when Vault bootstrap write fails
```

followed by the final `make: *** [test] Error 1` tail. The bug is closed; any underlying
test failures are separate defects.
