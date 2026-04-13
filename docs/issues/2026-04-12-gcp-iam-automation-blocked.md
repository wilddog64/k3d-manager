# Issue: GCP IAM Automation Blocked by Sandbox Permissions

**Date:** 2026-04-12
**Status:** BLOCKED / ABANDONED
**Project:** k3d-manager (GCP Provider)

## Description

Attempts to automate the granting of `roles/compute.admin` to the GCP Service Account in the ACG Sandbox have failed across all technical paths (API, CLI, and Browser UI).

## Root Cause

The ACG Sandbox user identity (`cloud_user_p_...`) is provisioned with restricted custom roles (`StudentLabAdmin1-3`, `Viewer`). These roles explicitly lack the `resourcemanager.projects.setIamPolicy` permission. 

In the current sandbox environment:
1.  **CLI:** `gcloud projects add-iam-policy-binding` fails with `Policy update access denied`.
2.  **GCP Console:** The "Grant access" button in the IAM dashboard is grayed out (`aria-disabled="true"`) even when logged in as the sandbox user.

## Evidence

### CLI Failure:
```text
ERROR: (gcloud.projects.add-iam-policy-binding) [cloud_user...] does not have permission to access projects instance [playground...:setIamPolicy]: Policy update access denied.
```

### UI Failure (Playwright Logs):
```text
locator.click: Timeout 30000ms exceeded.
Call log:
  - waiting for locator('button:has-text("Grant Access")')
  - locator resolved to <button ... aria-disabled="true" ... class="... mat-mdc-button-disabled ...">
  - element is not enabled
```

## Impact

Automated `make up` for the GCP provider is currently impossible without manual intervention from an account with higher privileges (which is not available in the ACG sandbox). Users must manually verify if their specific sandbox allows IAM modifications; if not, the `k3s-gcp` provider will fail at the pre-flight check.

## Recommended Follow-up

-   Abandon Playwright and CLI-based IAM automation for GCP.
-   Update `k3s-gcp.sh` to provide clear "Permission Denied" instructions to the user.
-   Consider using a pre-provisioned project with Owner permissions if full automation is required for CI/CD testing.
