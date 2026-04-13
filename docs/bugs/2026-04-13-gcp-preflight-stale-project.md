# Bug: GCP pre-flight fails when cached SA key points to expired sandbox

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `scripts/lib/providers/k3s-gcp.sh`

---

## Summary

`make up CLUSTER_PROVIDER=k3s-gcp` exited during the Compute IAM pre-flight guard with:

```
ERROR: [k3s-gcp] Compute access check failed on project playground-s-11-6dffb9dd.
make[1]: *** [up] Error 1
```

The cached service-account key at `~/.local/share/k3d-manager/gcp-service-account.json`
still referenced a previous sandbox project. `_gcp_load_credentials` accepted the cached
`project_id` without verifying that the project still exists, so every `gcloud` call ran
against the expired project and failed immediately.

---

## Reproduction Steps

1. Finish an earlier ACG GCP sandbox session (project `playground-s-11-6dffb9dd`).
2. Start a brand-new sandbox with a different project ID.
3. Run `make up CLUSTER_PROVIDER=k3s-gcp` without deleting the cached key file.
4. `_gcp_load_credentials` logs `SA key valid on disk — skipping Playwright extraction`.
5. `_gcp_preflight_check_compute` uses the stale project and fails with the error above.

Manual workaround: `rm ~/.local/share/k3d-manager/gcp-service-account.json` and rerun
`make up ... URL=<new sandbox>` so Playwright re-extracts credentials.

---

## Root Cause

The cached SA key was considered valid solely because the JSON file existed with a
non-null `project_id`. `_gcp_load_credentials` never probed whether the project still
responds to `gcloud projects describe`, so the handler reused the dead project ID and
passed it to `_gcp_preflight_check_compute`, which then aborted.

---

## Proposed Fix

Update `_gcp_load_credentials` to run `gcloud projects describe <cached_project>` before
trusting the cache. If the command fails, delete the stale key and fall through to
`gcp_get_credentials` so new sandbox credentials (with the new project ID) are extracted
via Playwright automatically. (Spec drafted separately as `docs/bugs/v1.1.0-bugfix-gcp-stale-sa-key-project-probe.md`.)

---

## Impact

Any engineer who provisions a fresh ACG GCP sandbox while the previous key remains on
 disk hits this failure until they manually delete the file. This blocks the entire
`make up CLUSTER_PROVIDER=k3s-gcp` workflow and prevents provisioning for v1.1.0 smoke
 tests.
