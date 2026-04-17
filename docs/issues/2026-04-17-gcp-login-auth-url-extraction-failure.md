# Issue: `gcp_login` fails to extract auth URL from `gcloud auth login --no-launch-browser`

## What was tested

Attempted `make up CLUSTER_PROVIDER=k3s-gcp` after the Playwright-based `gcp_login` automation was introduced.

Observed runtime output:

```text
INFO: Found 3 copyable inputs.
INFO: Service account key written to /Users/cliang/.local/share/k3d-manager/gcp-service-account.json
INFO: [gcp] GCP_PROJECT=playground-s-11-5e02fbfc
INFO: [gcp] GOOGLE_APPLICATION_CREDENTIALS=/Users/cliang/.local/share/k3d-manager/gcp-service-account.json
INFO: [k3s-gcp] Ensuring gcloud is authenticated as cloud_user_p_26a63f70@linuxacademygclabs.com...
INFO: [gcp] Authenticating as cloud_user_p_26a63f70@linuxacademygclabs.com via Playwright (automated)...
ERROR: [gcp] gcp_login: could not extract auth URL from gcloud output
make: *** [up] Error 1
```

## Inspection performed

Tried to capture the raw output of:

```bash
gcloud auth login --no-launch-browser --account "cloud_user_p_26a63f70@linuxacademygclabs.com"
```

using the same temp-log + FIFO pattern as `scripts/plugins/gcp.sh`. No auth URL was captured in the log before timeout, which is consistent with the runtime failure path in `gcp_login`.

## Root cause

`gcp_login` in `scripts/plugins/gcp.sh` assumes the auth URL will appear in `gcloud` output matching this pattern:

```bash
grep -oE 'https://accounts\.google\.com[^ ]+'
```

That parsing is too brittle:

- it assumes the auth URL always starts with `https://accounts.google.com`
- it assumes the URL is present as a single whitespace-delimited token
- it assumes the current `gcloud` version emits the URL in a stable, grep-friendly format

In practice, `gcloud auth login --no-launch-browser` did not produce a matchable URL in the expected form, so `_auth_url` stayed empty and `gcp_login` aborted before Playwright could run.

## Recommended follow-up

1. Inspect the exact `gcloud` output format in this environment/version with a more robust capture method.
2. Replace the narrow regex with a parser that tolerates alternate Google auth URL formats and wrapped/multiline output.
3. Consider a fallback path that logs the raw `gcloud` output to a temp file for diagnosis when extraction fails.
4. Add a focused test for auth URL extraction logic if feasible.
