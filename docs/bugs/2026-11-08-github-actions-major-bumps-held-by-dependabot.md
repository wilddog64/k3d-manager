# Bug: three GitHub Actions major bumps wait as Dependabot PRs; one would float Wrangler to `latest`

**Status:** OPEN — filed; batch with other P3s into the release
**Priority:** P3
**Waiting on:** operator decision — since 2026-11-12 (capture-first triage; nothing dispatched)
**Introduced by:** pre-existing (pins set before the upstream majors: checkout v5 2025-08-11, setup-kubectl v5 2026-03-25, wrangler-action v4 2026-05-12)
**Should have been caught by:** none
**Severity:** low — nothing is broken today; the pins age, and #158 as opened would replace a pinned Wrangler with `latest`
**Approval:** operator, 2026-11-08 ("let's file a P3 to have these batched into release")
**Intent approved:** operator, 2026-11-08 ("apporved"), E1–E3
**Filed:** 2026-11-08
**Detected by:** operator, Dependabot PR list (#157, #158, #159, each 4/4 checks green)
**Affected:** `.github/workflows/ci.yml`, `.github/workflows/deploy-worker.yml`, `.github/actions/vcluster-e2e-setup/action.yml`
**Related:** memory `reference_deploy_worker_workflow_overwrites_relay_secrets` (the deploy-worker workflow re-uploads `WEBHOOK_TOKEN` and `SLACK_SIGNING_SECRET`; stale copies broke every Slack command on 2026-10-01)

## Symptom

Dependabot opened three PRs against `main` on 2026-11-07:

| PR | Bump | Used in | Exercised by the 4 PR checks? |
|---|---|---|---|
| #157 | `actions/checkout` v4 → v7 | `ci.yml` (2), `deploy-worker.yml` (1) | `ci.yml` yes; `deploy-worker.yml` no |
| #158 | `cloudflare/wrangler-action` v3 → v4 | `deploy-worker.yml` | no |
| #159 | `azure/setup-kubectl` v4 → v5 | `.github/actions/vcluster-e2e-setup/action.yml` | no |

The four checks are lint, alertmanager-behaviour, CodeQL and GitGuardian. Their green proves #157 for `ci.yml`
only.

## Upstream changes (release notes, `gh release view`, 2026-11-08)

- `actions/checkout` v5.0.0: Node 24 runtime, with a minimum runner version. v6.0.0: credentials persisted to a
  separate file. v7.0.0: dependency bumps only.
- `azure/setup-kubectl` v5.0.0: Node 24 runtime; kubectl downloaded from `cdn.dl.k8s.io`, no redirects.
- `cloudflare/wrangler-action` v4.0.0: installs Wrangler v4 (`latest`) when `wranglerVersion` is unset. This
  workflow does not set it, so #158 as opened floats the Wrangler version, against the supply-chain pin rule.

## Fix

One change on the release branch, instead of merging the three PRs:

- `actions/checkout@v7` in both workflows.
- `azure/setup-kubectl@v5` in the vcluster composite action.
- `cloudflare/wrangler-action@v4` with `wranglerVersion` set to an exact Wrangler 4.x version. The dispatch
  records which version was chosen and its npm publish date.
- After the release merges, close #157–#159 if Dependabot has not closed them itself.

## Acceptance

```yaml
must:
  - id: M1
    text: every actions/checkout reference in .github/ is @v7
  - id: M2
    text: every azure/setup-kubectl reference in .github/ is @v5
  - id: M3
    text: deploy-worker.yml uses cloudflare/wrangler-action@v4 with wranglerVersion set to an exact x.y.z version
  - id: M4
    text: after the next deploy-worker run, Slack slash commands still answer
must_not:
  - id: N1
    text: wrangler-action is used without wranglerVersion, or with a range, "latest" or a major-only value
  - id: N2
    text: any action in .github/ is referenced at @main, @master or @latest
  - id: N3
    text: the deploy-worker workflow is run as part of this fix (it re-uploads the relay secrets; the operator decides when)
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    intent: a test reads the workflow files and fails if any of these pins is wrong or Wrangler floats
  - id: E2
    proves: [M1]
    kind: live
    intent: CI on the release branch runs green with checkout v7
  - id: E3
    proves: [M4]
    kind: live
    intent: the operator runs one Slack command (for example /cluster-status) after the next deploy-worker run and it answers
interface:
  - .github/workflows/ci.yml
  - .github/workflows/deploy-worker.yml
  - .github/actions/vcluster-e2e-setup/action.yml
```

## Notes

- No workflow in this repo calls `vcluster-e2e-setup`, and a code search of the owner's repos (2026-11-08) found
  only docs naming it. #159 cannot be proven live until something calls the action again; E1 covers the pin.
- Not a hub change: GitHub Actions only, so no `make hub-promote` is involved.
