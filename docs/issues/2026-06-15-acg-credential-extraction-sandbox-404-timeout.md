# Issue: ACG credential extraction times out after Pluralsight sandbox 404, parent webhook SIGTERMs make

**Date:** 2026-06-15
**Component:** lib-acg / acg_credentials (Pluralsight sandbox extraction) + bin/k3dm-webhook
**Status:** Filed (not fixed — root-cause investigation only)

## Symptom

`/cluster-up` (job `4570a5e0`) running `make up CLUSTER_PROVIDER=k3s-aws` failed at Step 1/12 (credential extraction):

```
INFO: Navigating to https://app.pluralsight.com/cloud-playground/cloud-sandboxes...
INFO: Waiting for page content to load...
INFO: Looking for AWS sandbox buttons...
INFO: Sandbox route not active (https://s2.pluralsight.com/404.html) — retrying directly via targetUrl...
WARN: Timed out waiting for sandbox buttons or credentials — proceeding anyway
make: *** [up] Terminated: 15
ERROR: make up CLUSTER_PROVIDER=k3s-aws exited -15
```

The extractor detected the `s2.pluralsight.com/404.html` redirect, attempted a direct `targetUrl` retry, but the retry never recovered — sandbox buttons / credentials never appeared. The parent webhook then SIGTERM'd the `make` process (exit -15).

## Investigation

- Output above is the entire failure window — no kubectl calls are relevant because the cluster never started; credentials never reached `make up`.
- Pre-existing related issues (none cover this exact retry-timeout path):
  - `2026-04-06-acg-up-sandbox-expired.md` — expired sandbox, different signal
  - `2026-04-08-acg-extend-stale-session-ghost-state.md` — extend flow ghost state
  - `2026-06-10-sandbox-js-addlocatorhandler-strict-mode-violation.md` — Playwright handler bug
  - `2026-06-12-copilot-pr43-lib-acg-sandbox-delete-restart.md` — delete/restart path
- The `s2.pluralsight.com/404.html` redirect indicates the sandbox route was not active at the moment of navigation (likely sandbox not yet provisioned, or Pluralsight CDN routing glitch). The retry-via-targetUrl path exists but did not actually recover before the watchdog fired.

## Root Cause

Two-layer failure:

1. **lib-acg credential extraction:** the "retry directly via targetUrl" branch in the sandbox extractor does not actually re-run sandbox-button discovery effectively after a `s2.pluralsight.com/404.html` redirect — it logs the retry and then proceeds to `WARN: Timed out waiting for sandbox buttons or credentials — proceeding anyway` without re-driving the page. The extractor exits successfully (warn-only) with no credentials.
2. **bin/k3dm-webhook supervision:** because the extractor exits "successfully but empty," downstream `make up` hangs (no AWS creds) until the webhook's per-step timeout fires SIGTERM (exit -15). The user only sees `Terminated: 15` with no actionable signal.

## Fix Applied

None — investigation/file-only. This is filed for triage. Recommended fixes (out of scope for this entry):

- lib-acg: on `s2.pluralsight.com/404.html` detect, force a full `sandbox restart` (sandbox-expired path) rather than a silent retry-then-warn; treat empty-credentials as a hard error (non-zero exit), not a warn.
- bin/k3dm-webhook: distinguish "credential extraction empty" from "make timeout" so SIGTERM produces an actionable error instead of `exited -15`.

## Notes

- Failure surfaced via Slack `/cluster-up` job `4570a5e0`.
- Separate from the slash-command routing bug (cluster-up/cluster-down/cluster-refresh not registered in webhook) — that one is tracked separately.
- Related: `scripts/lib/acg/acg_credentials.js`, `bin/k3dm-webhook` `_run_cluster`.
