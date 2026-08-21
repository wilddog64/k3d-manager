# Bug: make status shows "AWS Credentials" section for GCP provider

**Branch:** `k3d-manager-v1.2.0`
**Files:** `bin/acg-status`, `Makefile` (status target)

## Root Cause

`bin/acg-status` always runs `aws sts get-caller-identity` at the end, regardless of which
cluster provider is active. When `CLUSTER_PROVIDER=k3s-gcp`, AWS credentials are not
present and the section shows a misleading error:

```
=== AWS Credentials ===
AWS credentials invalid or expired — run bin/acg-refresh
```

## Fix

Pass `CLUSTER_PROVIDER` from the Makefile `status` target and gate the AWS section in
`bin/acg-status` on `CLUSTER_PROVIDER != k3s-gcp`.

**Makefile** — add `CLUSTER_PROVIDER=$(CLUSTER_PROVIDER)` to the status target:
```makefile
status:
	APP_CONTEXT=$(if $(filter k3s-gcp,$(CLUSTER_PROVIDER)),ubuntu-gcp,ubuntu-k3s) CLUSTER_PROVIDER=$(CLUSTER_PROVIDER) bin/acg-status
```

**bin/acg-status** — add `CLUSTER_PROVIDER` variable and gate the AWS section:
```bash
CLUSTER_PROVIDER="${CLUSTER_PROVIDER:-k3d}"
```
And wrap the `=== AWS Credentials ===` block:
```bash
if [[ "${CLUSTER_PROVIDER}" != "k3s-gcp" ]]; then
  echo ""
  echo "=== AWS Credentials ==="
  if aws sts get-caller-identity --output table 2>/dev/null; then
    :
  else
    echo "AWS credentials invalid or expired — run bin/acg-refresh"
  fi
fi
```
