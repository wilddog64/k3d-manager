# Bug: aggregate health timeout is classified as webhook outage

**Status:** VERIFIED — bounded budget and truthful recovery inference fixed; current direct health passed
**Priority:** P2
**Filed:** 2026-10-27, operator live timeout after successful credential lookup
**Branch:** `k3d-manager-v1.43.9`
**Fix commit:** `eafe42da71f6243f9613dc85f53f92f9e7ae0182`
**Related:** `docs/bugs/2026-10-26-webhook-unresponsive-minimal-diagnosis-recovery.md`

Doctor gave aggregate quick health four seconds while downstream probes can
take eight, then recommended webhook recovery on timeout with a listener
present. That cannot establish handler failure. Independent current401 and
authenticated healthy response were received without a restart.

Health now has15 seconds, with body using remaining budget; a timeout with
listening/unknown socket is health_check_timeout without recovery. Missing
job/listener remains independent evidence. Four pre-fix failures;35 Python
and5 BATS, Ruff, audit/lint passed. No live service or credential changes.
[Full actual output and limitations](../issues/2026-10-27-webhook-doctor-health-timeout-restart-inference.md).
