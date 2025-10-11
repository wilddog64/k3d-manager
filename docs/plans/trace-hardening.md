# Trace Hardening (ENABLE_TRACE)

## Goal
Prevent sensitive material from leaking into `/tmp/k3d.trace` when `ENABLE_TRACE=1` by ensuring base64 encodes and similar helpers run with tracing disabled.

## Immediate Tasks
- Update the Jenkins plugin to capture base64 output with tracing temporarily disabled.
- Audit the current call sites in `scripts/plugins/jenkins.sh` that generate inline manifests for the cert-rotator job.
- Keep existing behaviour and validation intact; only adjust tracing boundaries.

## Validation
- Re-run the Jenkins plugin BATS suite to confirm no regressions (`bats scripts/tests/plugins/jenkins.bats`).
- Manually spot-check `/tmp/k3d.trace` after invoking `deploy_jenkins` with `ENABLE_TRACE=1` to ensure base64 blobs are absent.
