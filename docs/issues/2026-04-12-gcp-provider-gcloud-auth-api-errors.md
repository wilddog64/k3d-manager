# Issue: GCP provider — `gcloud auth activate-service-account` triggers Cloud Resource Manager API; `compute.instances.create` permission denied

**Date:** 2026-04-12
**Branch:** `k3d-manager-v1.0.7`
**File:** `scripts/lib/providers/k3s-gcp.sh`

---

## Symptoms

Two sequential errors observed during `make up CLUSTER_PROVIDER=k3s-gcp` against a live ACG GCP sandbox:

**Error 1 — Cloud Resource Manager API not enabled:**
```
reason: SERVICE_DISABLED
Cloud Resource Manager API has not been used in project 651563715037 before
or it is disabled. Enable it by visiting
https://console.developers.google.com/apis/api/cloudresourcemanager.googleapis.com/overview?project=651563715037
```

**Error 2 — compute.instances.create permission denied:**
```
ERROR: (gcloud.compute.instances.create) Could not fetch resource:
 - Required 'compute.instances.create' permission for
   'projects/playground-s-11-2342684b/zones/us-central1-a/instances/k3s-gcp-server'
```

---

## Root Cause

`_provider_k3s_gcp_deploy_cluster` currently activates gcloud credentials using:

```bash
gcloud auth activate-service-account --key-file="${key_file}" --quiet || return 1
gcloud config set project "${project}" --quiet || return 1
```

`gcloud auth activate-service-account` and the subsequent project validation call the
**Cloud Resource Manager API** (`cloudresourcemanager.googleapis.com`) internally. ACG GCP
sandbox projects do not pre-enable this API, and the sandbox service account does not have
`serviceusage.services.enable` permission to enable it.

Without a working CRM API, gcloud cannot resolve IAM bindings, so the `compute.instances.create`
call fails with `permission denied` even though the service account has compute rights.

---

## Fix

Replace the `gcloud auth` + `gcloud config set project` flow with **Application Default
Credentials (ADC)**. `gcp.sh` already exports `GOOGLE_APPLICATION_CREDENTIALS` pointing to the
service account JSON key. When `GOOGLE_APPLICATION_CREDENTIALS` is set, `gcloud` uses ADC
automatically without calling the Cloud Resource Manager API.

Remove the two auth/project lines and instead pass `--project` explicitly on every subsequent
`gcloud` command.

### Before

```bash
  _info "[k3s-gcp] Activating service account for project ${project}..."
  gcloud auth activate-service-account --key-file="${key_file}" --quiet || return 1
  gcloud config set project "${project}" --quiet || return 1

  _info "[k3s-gcp] Checking for existing instance ${_GCP_INSTANCE_NAME}..."
  local existing
  existing=$(gcloud compute instances describe "${_GCP_INSTANCE_NAME}" \
    --zone="${_GCP_ZONE}" --format="value(name)" 2>/dev/null || true)
  if [[ -n "${existing}" ]]; then
    _info "[k3s-gcp] Instance already exists — skipping create"
  else
    _info "[k3s-gcp] Creating compute instance ${_GCP_INSTANCE_NAME}..."
    gcloud compute instances create "${_GCP_INSTANCE_NAME}" \
      --zone="${_GCP_ZONE}" \
      --machine-type="${_GCP_MACHINE_TYPE}" \
      --image-family=ubuntu-2204-lts \
      --image-project=ubuntu-os-cloud \
      --tags=k3s-server \
      --metadata="ssh-keys=ubuntu:$(<"${_GCP_SSH_KEY_FILE}.pub")" \
      --quiet || return 1
  fi

  _info "[k3s-gcp] Ensuring firewall rule for k3s API (tcp:6443)..."
  gcloud compute firewall-rules describe k3s-api --quiet 2>/dev/null \
    || gcloud compute firewall-rules create k3s-api \
         --allow=tcp:6443 \
         --target-tags=k3s-server \
         --description="k3s API server" \
         --quiet || return 1

  _info "[k3s-gcp] Fetching instance external IP..."
  local external_ip
  external_ip=$(gcloud compute instances describe "${_GCP_INSTANCE_NAME}" \
    --zone="${_GCP_ZONE}" --format="value(networkInterfaces[0].accessConfigs[0].natIP)") || return 1
```

### After

```bash
  _info "[k3s-gcp] Configuring ADC credentials for project ${project}..."
  export CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE="${key_file}"
  export CLOUDSDK_CORE_PROJECT="${project}"

  _info "[k3s-gcp] Checking for existing instance ${_GCP_INSTANCE_NAME}..."
  local existing
  existing=$(gcloud compute instances describe "${_GCP_INSTANCE_NAME}" \
    --project="${project}" \
    --zone="${_GCP_ZONE}" --format="value(name)" 2>/dev/null || true)
  if [[ -n "${existing}" ]]; then
    _info "[k3s-gcp] Instance already exists — skipping create"
  else
    _info "[k3s-gcp] Creating compute instance ${_GCP_INSTANCE_NAME}..."
    gcloud compute instances create "${_GCP_INSTANCE_NAME}" \
      --project="${project}" \
      --zone="${_GCP_ZONE}" \
      --machine-type="${_GCP_MACHINE_TYPE}" \
      --image-family=ubuntu-2204-lts \
      --image-project=ubuntu-os-cloud \
      --tags=k3s-server \
      --metadata="ssh-keys=ubuntu:$(<"${_GCP_SSH_KEY_FILE}.pub")" \
      --quiet || return 1
  fi

  _info "[k3s-gcp] Ensuring firewall rule for k3s API (tcp:6443)..."
  gcloud compute firewall-rules describe k3s-api \
    --project="${project}" --quiet 2>/dev/null \
    || gcloud compute firewall-rules create k3s-api \
         --project="${project}" \
         --allow=tcp:6443 \
         --target-tags=k3s-server \
         --description="k3s API server" \
         --quiet || return 1

  _info "[k3s-gcp] Fetching instance external IP..."
  local external_ip
  external_ip=$(gcloud compute instances describe "${_GCP_INSTANCE_NAME}" \
    --project="${project}" \
    --zone="${_GCP_ZONE}" --format="value(networkInterfaces[0].accessConfigs[0].natIP)") || return 1
```

**Why `CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE` + `CLOUDSDK_CORE_PROJECT`:**
- These env vars configure gcloud at the process level without touching the global config store
- No CRM API call is made; gcloud uses the JSON key directly via ADC
- `--project` flags on every command make the project explicit, avoiding any ambient config

**Also remove from destroy:** `_provider_k3s_gcp_destroy_cluster` calls gcloud without a project flag. Add `--project="${_GCP_PROJECT_ID}"` to the `gcloud compute instances delete` line. Because `_GCP_PROJECT_ID` may not be set at destroy time (no credentials extraction), read it from the kubeconfig context or from a cached file. Simplest: add `local project="${GCP_PROJECT:-}"` at the top of destroy and pass `--project="${project}"` if non-empty; otherwise let gcloud use ambient config (destroy is best-effort).

---

## Files to Change

| File | Change |
|------|--------|
| `scripts/lib/providers/k3s-gcp.sh` | Remove `gcloud auth activate-service-account` + `gcloud config set project`; set `CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE` + `CLOUDSDK_CORE_PROJECT`; add `--project="${project}"` to all gcloud compute/firewall commands in deploy |

## Definition of Done

- [ ] `gcloud auth activate-service-account` removed from `_provider_k3s_gcp_deploy_cluster`
- [ ] `gcloud config set project` removed from `_provider_k3s_gcp_deploy_cluster`
- [ ] `CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE="${key_file}"` set before first gcloud call
- [ ] `CLOUDSDK_CORE_PROJECT="${project}"` set before first gcloud call
- [ ] `--project="${project}"` added to all gcloud compute/firewall commands in deploy
- [ ] shellcheck passes: `shellcheck scripts/lib/providers/k3s-gcp.sh`
- [ ] BATS passes: `bats scripts/tests/providers/k3s_gcp.bats`
- [ ] Committed to `k3d-manager-v1.0.7`; SHA reported
- [ ] Pushed to `origin/k3d-manager-v1.0.7`
- [ ] Commit message: `fix(gcp): use ADC env vars instead of gcloud auth activate-service-account to avoid CRM API`
