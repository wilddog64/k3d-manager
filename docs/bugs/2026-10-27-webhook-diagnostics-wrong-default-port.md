# Bug: webhook doctor and heartbeat probe wrong default port

**Status:** VERIFIED — default/override correction tested; doctor current local health confirmed, heartbeat enrollment still pending
**Priority:** P2
**Filed:** 2026-10-27, during operator live verification
**Branch:** `k3d-manager-v1.43.9`
**Fix commit:** `2b93434e893ff0417946c550deecbecb1443021d`
**Related:** `docs/bugs/2026-10-26-webhook-unresponsive-minimal-diagnosis-recovery.md`; `docs/bugs/2026-10-26-independent-heartbeat-healthchecks-monitoring.md`

New diagnostic defaults used9000 while the server defaults to7443. The doctor
could falsely report no_listener/unresponsive and recommend recovery even
though the live webhook PID4295 was listening on7443. Operator's result also
had auth_unavailable, which is a separate unknown credential-context issue.

Corrected default/example to7443 and honored validated loaded-job port
overrides in both doctor probes. Invalid config stays unknown. Added
production-default consistency, custom/invalid port and heartbeat URL fixtures.
Six regressions red; final161 Python +8 BATS, Ruff, ShellCheck, audit/lint pass.

[Full actual evidence and corrected direct live check](../issues/2026-10-27-webhook-doctor-live-port-mismatch.md).
No restart, credential change, provider enrollment or deployment performed.
Do not treat the original incident or external reply delivery as resolved.
