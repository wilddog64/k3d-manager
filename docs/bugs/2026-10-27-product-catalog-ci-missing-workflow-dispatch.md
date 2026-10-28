# Bug: product-catalog CI cannot accept scanner rebuild dispatch

**Status:** OPEN — application workflow configuration confirmed; implementation not authorized
**Priority:** P2
**Filed:** 2026-10-27 (operator local date)
**Repository:** wilddog64/shopping-cart-product-catalog
**Affected file:** .github/workflows/ci.yml on main

## Evidence and impact

Operator scanner Job app-cve-scan-manual-1793151640 successfully scanned the candidate, found5 HIGH/CRITICAL findings and blocked promotion, then logged:

```text
[app-cve-scan] STAGE shopping-cart-product-catalog: rebuild dispatch FAILED — will retry next run
```

Scanner maps this service toci.yml and requests workflow dispatch onrefmain. GitHub read-only API confirms Python CI is active at.github/workflows/ci.yml. Its current trigger declaration is:

```yaml
name: Python CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
```

No workflow_dispatch trigger is declared, so this workflow cannot accept the intended workflow dispatch operation. Actual failing POST HTTP response is suppressed; a simultaneous permission/transport issue is not excluded. No further live POST was issued to diagnose this.

## Follow-up scope and workaround

In the application repository, add workflow_dispatch while retaining existing push/pull_request behavior. Review manual-trigger job conditions, permissions, image publication and signing/attestation so a manual run builds the intended main revision safely. Validate workflow syntax/conditions offline, use that repo's instructions and commit/PR workflow. A live dispatch or rebuilt image rollout is a separate operator step, after review. Do not change k3d-manager scan policy or broaden PAT permissions based only on this log.

Workaround: a normal reviewed main-branch application fix triggers existing push CI. Rebuilding unchanged vulnerable dependencies is not proof of remediation; exact candidate findings/dependency updates require separate application work. Missing automatic rebuild degrades remediation but does not prevent the manual application workflow.

The intended whole-Job success on per-service dispatch failure was recorded in docs/bugs/2026-08-01-app-cve-scan-nonzero-exit-and-missing-pod-labels.md; do not silently reverse it. Bounded dispatch-response diagnostics would be a separately scoped manager follow-up.

[Full operator output and live verification](../issues/2026-10-27-app-cve-scan-fail-closed-verification.md). No application code or workflow was changed, no credential accessed or mutated, and no follow-up worker dispatched.
