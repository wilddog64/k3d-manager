# Issue: ACG Provisioning failure during KeyPair import

**Date:** 2026-03-29
**Branch:** `k3d-manager-v1.0.0`

## Problem
During the `v1.0.0` E2E smoke test, `acg_provision` failed with a fatal error when attempting to import the SSH key pair.

## Analysis
- **Command:** `aws ec2 import-key-pair --region us-west-2 --key-name k3d-manager-key --public-key-material fileb://...`
- **Behavior:** The AWS CLI returned exit code 1 because a key pair with the name `k3d-manager-key` already existed in the sandbox account.
- **Root Cause:** In `scripts/plugins/acg.sh`, the `_acg_provision_stack` function calls `_run_command` for the key import without the `--soft` flag. Since `_run_command` defaults to failing fast on non-zero exit codes, the entire provisioning process was terminated.

## Impact
Blocked the automated deployment path (`deploy_cluster`) for the `k3s-aws` provider when re-running on an existing sandbox.

## Recommended Follow-up
Add the `--soft` flag to the `aws ec2 import-key-pair` call in `scripts/plugins/acg.sh` to make the operation idempotent.
