# Bug: the hub's system-notice Slack URL is lost on every rebuild, so notices stop silently

**Status:** OPEN — filed 2026-10-24; not dispatched
**Priority:** P2
**Severity:** medium — ACG expiry warnings and every rotation notice have not been sent since 2026-10-16; the operator can restore the URL by hand
**Release:** bug (does not count toward the five-plan cap). Restore before the 2026-10-29 hub rebuild drill, and add it to that drill's checklist.
**Filed:** 2026-10-24, by Claude, while checking the v1.43.6 `make platform-ops` run
**Approval:** explicit 2026-10-24, as part of the bug cleanup the operator approved ("sounds like a plan"). The hub is critical, so dispatch needs the operator's go.
**Component:** `scripts/plugins/argocd.sh` (`deploy_argocd_platform_ops`), `scripts/etc/argocd/platform-ops/notification-secret.yaml.tmpl`
**Related:** `docs/bugs/2026-10-24-prometheus-rotator-never-posts-slack-notice.md` (its fix reads this key), `docs/bugs/2026-10-24-sandbox-reaper-slack-notice-always-fails.md`, `docs/plans/v1.43.8-slack-route-system-notices-to-status-channel.md` (routes system notices through this Secret), `memory-bank` drill `project_hub_rebuild_drill_2026_10_29`

## Problem

The Grafana, Keycloak and ArgoCD rotation notices, the ACG expiry check, and since `a54d9489` the
Prometheus rotation notice read the Slack incoming-webhook URL from Secret
`platform-ops/platform-ops-notifications`, key `slack-incoming-webhook-url`.

Evidence, 2026-10-24, from read-only checks after the v1.43.6 `make platform-ops`:

- `kubectl describe secret` lists only `notification-email` (0 bytes), `notification-from`,
  `pagerduty-routing-key` (0 bytes) and `sendgrid-api-key` (0 bytes). There is no
  `slack-incoming-webhook-url`.
- The Secret was created 2026-10-16T02:12:28Z. Its only field manager is one
  `kubectl-client-side-apply` from that time, so no patch has ever added the key. Today's
  platform-ops run did not remove it; it has been missing since the 10-16 rebuild.

`deploy_argocd_platform_ops` applies `notification-secret.yaml.tmpl`, which has no Slack key, and
then prints the `kubectl patch` as a manual step "with no durable local source". So a rebuild loses
the URL, and nothing alerts when it is missing: each notifier skips quietly when the key is empty.
The 2026-10-29 rebuild drill will lose it again.

## Fix

### F1. A durable source

Store the URL in Vault and sync it into `platform-ops-notifications` with an ExternalSecret (key
`slack-incoming-webhook-url`), the same way the hub's other platform-ops credentials sync. Pick the
Vault path and policy following the least-privilege rules in `CLAUDE.md` (read-only for ESO).
`deploy_argocd_platform_ops` stops printing the manual patch step. The one-time seeding of Vault is
an operator step in `docs/howto/`. The URL is never in git, argv or a log.

### F2. Missing is visible

`deploy_argocd_platform_ops` warns `platform-ops-notifications has no slack-incoming-webhook-url —
system notices will not be sent` when the key is absent or empty after the sync. It checks the key
by name or length only, never the value. (`kubectl` template errors on a Secret print its data, so
don't use a go-template here.)

## Tests

BATS with stub `kubectl`. There are no real cluster or Slack calls.

1. With the key absent, `deploy_argocd_platform_ops` prints the warning above.
2. With the key present, no warning, and the stubbed calls never print the value.
3. The rendered manifests contain an ExternalSecret that targets `platform-ops-notifications` with
   key `slack-incoming-webhook-url`, and no literal URL.

## Acceptance

```yaml
must:
  - id: M1
    text: After a hub rebuild and make platform-ops, platform-ops-notifications has slack-incoming-webhook-url, with no manual patch.
  - id: M2
    text: make platform-ops warns when the key is absent or empty.
must_not:
  - id: N1
    text: A missing key must not pass silently (red on the pre-fix deploy, which prints only the manual-step hint).
  - id: N2
    text: The URL must not appear in git, argv, trace or logs.
  - id: N3
    text: No test may contact a cluster, Vault or Slack.
evidence:
  - id: E1
    kind: offline
    proves: [M2, N1, N2, N3]
    text: BATS green; N1 red on the pre-fix code in a temp copy.
  - id: E2
    kind: live
    proves: [M1]
    text: Operator seeds Vault once; after make platform-ops (and after the 10-29 rebuild drill) kubectl describe secret shows slack-incoming-webhook-url with a nonzero size, and the next ACG expiry or rotation notice arrives in Slack.
interface:
  - make platform-ops (deploy_argocd_platform_ops)
  - kubectl -n platform-ops describe secret platform-ops-notifications
```

## Workaround

The operator patches the URL in by hand from their own shell, as `make platform-ops` prints. Pick
the URL for the channel the v1.43.8 routing plan names.

## What NOT to Do

- Do NOT read, print or log the URL; check the key by name or size only.
- Do NOT reuse the Hermes token or any broad credential for the Vault read.
- Do NOT edit `scripts/lib/foundation/`.
