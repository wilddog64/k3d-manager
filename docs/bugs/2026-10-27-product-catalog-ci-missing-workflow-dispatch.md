# Bug: product-catalog CI cannot accept scanner rebuild dispatch

**Status:** VERIFIED — fix merged in product-catalog `8e7b751a` (PR #65); live scanner `workflow_dispatch` on main pending
**Priority:** P2
**Fix commit:** 85945891b6234e5efcbd06b767baea4c84592816
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

## Files

- `.github/workflows/ci.yml`

## Authorized implementation and acceptance

Operator approved GPT-6-Luna dispatch with “go ahead”. Target repository
wilddog64/shopping-cart-product-catalog; isolated target branch
fix/cve-manual-rebuild starts at origin/main ae982f0. Existing application
checkout fix/automerge-app-token must remain untouched. Add workflow_dispatch
with no required inputs, since scanner sends only refmain. Also adjust the
publish job condition to allow push OR workflow_dispatch only on
refs/heads/main. Leave pull-request publication and non-main publication
blocked. Existing publish is push-only, so adding just the trigger is
insufficient.

Preserve lint/build/integration/security checks, job dependencies, reusable
workflow SHAc7ff88aa9bc899876a41b9ddf33fd0606c9ce690, signing/attestation secret
forwarding, existing permissions, image metadata and push/pull_request
triggers. Do not change application dependencies, reusable infra workflow,
image pins, credentials, deployment manifests or any other file. No production
scan, GitHub workflow dispatch, image push or rollout. The pinned reusable
workflow already handles build/scan/push/sign/attest and promotion on valid
inputs; do not bypass its gates. This narrowly enables intended manual main
rebuild, not a promise that current dependencies are fixed.

Read CLAUDE.md and both memory-bank files first. Worker must not stage,
commit, push, create/merge PRs, or modify memory-bank/spec files. Coordinator
will review, commit/push only to the fix branch, verify SHA via GitHub API,
and leave merge to the repo owner/Claude under the session's no-PR rule.
Application activeContext cannot be changed until CI completed success;
record pending state in manager memory-bank meanwhile. No pytest/mypy/ruff
needed for this YAML-only change; follow repo virtualenv restrictions.

Run actionlint on the workflow; compare the parent workflow to prove only
trigger/publication condition changed; evaluate publication truth table:
main+push true, main+workflow_dispatch true, PR false, non-main push/manual
false. Confirm all required upstream jobs remain required. Paste actual
commands/results and list changed files. Offline only, no network/credential
access. The parent code-review-graph tools are not available in this session
(discovery returned none), so direct file review is the documented fallback.

## Implementation handoff

GPT-6-Luna changed onlyci.yml: added workflow_dispatch and main-only push/manual publish. Actual current-main reusableSHA c7ff88aa… preserved (initial task text named an older checkout SHA98b10f…; corrected without changing application pin). Independently actionlint/6-case condition matrix/exact two-edit parent comparison and landing gates passed. Remote fix/cve-manual-rebuild SHA verified through GitHub API. No PR created/merged, no CI run on non-main push, no live dispatch. Claude/owner PR/merge precedes live scanner retry. [Full actual output](../issues/2026-10-27-product-catalog-manual-rebuild-workflow-verification.md).

## 2026-10-28 verification recheck

Coordinatorre-ranactionlint(exit0/nooutput), exacttwoeditparentcomparison and
6eventpublicationmatrix(allPASS) on85945891. FreshGitHubmainstilllacks
workflow_dispatch; branchonecommitahead/0behind, noPRfound, all-eventActions
queryexactfixSHAhas0runs. OfflineVERIFIED, liveNOTYET. Thisdoesnotestablish
mainfixappliedorCIpassed. Claude/ownerPR+CI+mergeisnext, thenoneoperator
scannerretryandactualdispatch/workflowevidence. No automaticliveaction.
[Actual re-verification and handoff](../issues/2026-10-27-product-catalog-manual-rebuild-workflow-verification.md).

### Fix merged — 2026-10-29

Product-catalog PR #65 merged as `8e7b751a`: it adds the `workflow_dispatch` trigger, and publishing runs only on `refs/heads/main` for a push or a dispatch. The post-merge push run (40970448931) passed every job, including `Build, Scan & Push / build-push`. Still open for closure: one `workflow_dispatch` run on `main`, triggered by the app-cve-scan rebuild path, with `build-push` succeeding.
