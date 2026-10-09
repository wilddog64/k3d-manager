# ArgoCD infra upgrade executes without confirmation

**Filed:** 2026-10-07
**Severity:** High — shared infrastructure mutation could be triggered accidentally
**Status:** FIXED
**Component:** Slack relay and webhook `/api/v1/argocd-upgrade`

## Evidence

The command accepted:

```text
/argocd-upgrade 7.9.1 infra
```

without a confirmation token. The `infra` stage changes the shared infrastructure ArgoCD
configuration. The `acg` stage is lower-risk in this workflow and remains confirmation-free.

## Fix and acceptance

`infra` now requires `confirm` in the Slack command and `confirm: true` in the authenticated
webhook payload. The relay, thread dispatcher, and direct webhook API enforce the same rule.
`acg` remains runnable without confirmation. Regression coverage verifies both stages and
rejects unconfirmed infra requests before queuing a job.
