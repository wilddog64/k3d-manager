# Bug: make up fails when GCP instance already exists

**Branch:** `k3d-manager-v1.2.0`
**File:** `scripts/lib/providers/k3s-gcp.sh`

## Root Cause

`_gcp_create_instance` unconditionally calls `gcloud compute instances create` without
checking whether the instance already exists. On a re-run (sandbox still up, partial
failure, or retry), gcloud errors out:

```
ERROR: (gcloud.compute.instances.create) Could not fetch resource:
 - The resource '...instances/k3d-manager-gcp-node' already exists
```

`_gcp_ensure_firewall` already uses the correct idempotent pattern (describe → skip).
`_gcp_create_instance` is missing it.

## Fix

Add an existence check at the top of `_gcp_create_instance`. If the instance already
exists, skip creation and return.

**Old:**
```bash
function _gcp_create_instance() {
  local project="$1" zone="$2" ssh_user="$3" ssh_key_pub="$4"
  _info "[k3s-gcp] Creating instance ${_GCP_INSTANCE_NAME} in ${zone}..."
  gcloud compute instances create "${_GCP_INSTANCE_NAME}" \
    --project="${project}" \
    --zone="${zone}" \
    --machine-type="${_GCP_MACHINE_TYPE}" \
    --image-family="${_GCP_IMAGE_FAMILY}" \
    --image-project="${_GCP_IMAGE_PROJECT}" \
    --tags="${_GCP_NETWORK_TAG}" \
    --metadata="ssh-keys=${ssh_user}:$(cat "${ssh_key_pub}")" \
    --quiet
}
```

**New:**
```bash
function _gcp_create_instance() {
  local project="$1" zone="$2" ssh_user="$3" ssh_key_pub="$4"
  if gcloud compute instances describe "${_GCP_INSTANCE_NAME}" \
      --project="${project}" --zone="${zone}" --quiet >/dev/null 2>&1; then
    _info "[k3s-gcp] Instance ${_GCP_INSTANCE_NAME} already exists — skipping"
    return 0
  fi
  _info "[k3s-gcp] Creating instance ${_GCP_INSTANCE_NAME} in ${zone}..."
  gcloud compute instances create "${_GCP_INSTANCE_NAME}" \
    --project="${project}" \
    --zone="${zone}" \
    --machine-type="${_GCP_MACHINE_TYPE}" \
    --image-family="${_GCP_IMAGE_FAMILY}" \
    --image-project="${_GCP_IMAGE_PROJECT}" \
    --tags="${_GCP_NETWORK_TAG}" \
    --metadata="ssh-keys=${ssh_user}:$(cat "${ssh_key_pub}")" \
    --quiet
}
```
