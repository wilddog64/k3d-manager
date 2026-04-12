# Issue: GCP provider — use ADC access token to authenticate gcloud without CRM API

**Date:** 2026-04-12
**Branch:** `k3d-manager-v1.0.7`
**File:** `scripts/lib/providers/k3s-gcp.sh`
**Follows:** `docs/issues/2026-04-12-gcp-provider-gcloud-auth-api-errors.md`

---

## Symptoms

After the previous fix (CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE + CLOUDSDK_CORE_PROJECT),
`gcloud compute instances create` still returns:

```
ERROR: (gcloud.compute.instances.create) Could not fetch resource:
 - Required 'compute.instances.create' permission for
   'projects/playground-s-11-2342684b/zones/us-central1-a/instances/k3s-gcp-server'
```

---

## Root Cause

`CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE` is for gcloud's internal OAuth2 user credential
format, not for service account JSON key files. gcloud was not actually authenticated as
the service account — compute calls ran unauthenticated or as no identity.

Research findings (Gemini, 2026-04-12):
- `gcloud auth activate-service-account` is the canonical method but calls
  `cloudresourcemanager.googleapis.com` (disabled in ACG sandbox)
- `CLOUDSDK_CORE_ACCOUNT` alone cannot substitute for credential activation
- The sandbox service account cannot enable any APIs (`PERMISSION_DENIED`)
- IAM policy APIs are also disabled — cannot confirm SA roles via gcloud

---

## Fix

Use `gcloud auth application-default print-access-token` with `GOOGLE_APPLICATION_CREDENTIALS`
set to the SA JSON key file. ADC reads the key, signs a JWT, and exchanges it with
`oauth2.googleapis.com/token` — this is pure OAuth2, no CRM API involved.

Inject the resulting token via `CLOUDSDK_AUTH_ACCESS_TOKEN` so all subsequent `gcloud`
commands use it directly.

### Before (`scripts/lib/providers/k3s-gcp.sh`, current state)

```bash
  _info "[k3s-gcp] Configuring ADC credentials for project ${project}..."
  export CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE="${key_file}"
  export CLOUDSDK_CORE_PROJECT="${project}"
```

### After

```bash
  _info "[k3s-gcp] Obtaining access token from service account key..."
  local _gcp_access_token
  _gcp_access_token=$(GOOGLE_APPLICATION_CREDENTIALS="${key_file}" \
    gcloud auth application-default print-access-token 2>/dev/null) || {
    _err "[k3s-gcp] Failed to obtain access token from service account key: ${key_file}"
    return 1
  }
  if [[ -z "${_gcp_access_token}" ]]; then
    _err "[k3s-gcp] Access token is empty — service account key may be invalid"
    return 1
  fi
  export CLOUDSDK_AUTH_ACCESS_TOKEN="${_gcp_access_token}"
  export CLOUDSDK_CORE_PROJECT="${project}"
  unset _gcp_access_token
```

This is the only change to `k3s-gcp.sh`. The `--project` flags and `CLOUDSDK_CORE_PROJECT`
set in the previous fix remain in place.

---

## Files to Change

| File | Change |
|------|--------|
| `scripts/lib/providers/k3s-gcp.sh` | Replace `CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE` block with ADC access token block (exact Before→After above) |

---

## Before You Start

1. `git pull origin k3d-manager-v1.0.7`
2. Read this file in full
3. Read `scripts/lib/providers/k3s-gcp.sh` in full — confirm the current "Before" block matches before editing

Branch: `k3d-manager-v1.0.7` — never commit to `main`.

---

## What NOT to Do

- Do NOT use `gcloud auth activate-service-account` — calls CRM API, disabled in sandbox
- Do NOT use `CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE` — wrong format for SA JSON keys
- Do NOT add `gcloud services enable` — service account lacks `serviceusage.services.enable`
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files other than `scripts/lib/providers/k3s-gcp.sh`

---

## Rules

- shellcheck must pass: `shellcheck scripts/lib/providers/k3s-gcp.sh`
- BATS must pass: `bats scripts/tests/providers/k3s_gcp.bats`

---

## Definition of Done

- [ ] `CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE` line removed
- [ ] ADC access token block present with exact code above
- [ ] `CLOUDSDK_AUTH_ACCESS_TOKEN` exported before first gcloud compute call
- [ ] `shellcheck scripts/lib/providers/k3s-gcp.sh` passes
- [ ] `bats scripts/tests/providers/k3s_gcp.bats` passes
- [ ] Committed to `k3d-manager-v1.0.7`; SHA reported
- [ ] Pushed to `origin/k3d-manager-v1.0.7`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with SHA
- [ ] Commit message: `fix(gcp): obtain ADC access token from SA key to authenticate gcloud without CRM API`
