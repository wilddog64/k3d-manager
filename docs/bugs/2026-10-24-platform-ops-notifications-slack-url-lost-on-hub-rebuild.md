# Bug: the hub's system-notice Slack URL is lost on every rebuild, so notices stop silently

**Status:** FIXED — `a4c90598` (Luna, amended by Claude); live check E2 pending: the operator seeds the Keychain record, then `make platform-ops`
**Priority:** P2
**Severity:** medium — ACG expiry warnings and every rotation notice have not been sent since 2026-10-16; the operator can restore the URL by hand
**Release:** bug (does not count toward the five-plan cap). Restore before the 2026-10-29 hub rebuild drill, and add it to that drill's checklist.
**Filed:** 2026-10-24, by Claude, while checking the v1.43.6 `make platform-ops` run
**Approval:** explicit 2026-10-24 ("sounds like a plan"); dispatch go 2026-10-30 as the blocker for the M5 hub build ("we can move any time as long as commands are ready").
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

### F1. A durable source (revised 2026-10-30: Keychain, not Vault)

The 2026-10-24 draft proposed Vault + ESO. Revised to the pattern platform-ops already uses for its
other hub-only credentials (`argocd_sync_app_rebuild_secret`, `argocd_sync_git_writer_secret`): a
login-Keychain record synced into the cluster by `deploy_argocd_platform_ops`. Reasons: no new Vault
policy on the hub; the record travels to a new hub through `secrets.hub.list` and the machine-setup
`FROM=` copy, which the M5 hub build (`docs/plans/v1.43.12-m5-new-hub-one-command.md`) already uses.

- New Keychain record: service `k3dm-platform-ops-slack-url`, account `k3dm`.
- New function `argocd_sync_notifications_slack_secret [ns]` in `scripts/plugins/argocd.sh`, next to
  `argocd_sync_git_writer_secret` and in the same shape. It reads the record with
  `_argocd_keychain_value`. When present, it sets **only** the key `slack-incoming-webhook-url` of
  the existing Secret `platform-ops-notifications`, leaving its other keys unchanged, under
  `_no_trace`, with the value passed on stdin or in a `mktemp` file removed on return — never in
  argv. (If `_argocd_apply_secret_from_stdin` replaces the whole Secret, do not use it here.) When
  absent, it logs `k3dm-platform-ops-slack-url not in Keychain` and returns 0.
- `deploy_argocd_platform_ops` calls it after the notification Secret scaffold is applied (in the
  "Syncing secrets from Keychain" block), and drops the two `kubectl patch secret
  platform-ops-notifications` lines from the manual-steps message.
- `scripts/etc/machine/secrets.hub.list`: add
  `k3dm-platform-ops-slack-url|k3dm|platform-ops system-notice Slack incoming webhook|operator: see docs/howto/platform-ops-notifications.md`
  (match the existing column format).
- One-time seeding is an operator step in a new `docs/howto/platform-ops-notifications.md`: store
  the URL with `security add-generic-password -U -s k3dm-platform-ops-slack-url -a k3dm -w` (prompts
  at the TTY), then `make platform-ops`.

### F2. Missing is visible

`deploy_argocd_platform_ops` warns `platform-ops-notifications has no slack-incoming-webhook-url —
system notices will not be sent` when the key is absent or empty after the sync. It checks the key
by name or length only, never the value. (`kubectl` template errors on a Secret print its data, so
don't use a go-template here.)

## Tests

BATS with stub `kubectl`. There are no real cluster or Slack calls.

1. With the key absent, `deploy_argocd_platform_ops` prints the warning above.
2. With the key present, no warning, and the stubbed calls never print the value.
3. With the Keychain record present (stub `_argocd_keychain_value` / `security`), the sync sets
   `slack-incoming-webhook-url` on `platform-ops-notifications` without removing its other keys, and
   the value never appears in any stubbed command's argv or in output.
4. `secrets.hub.list` contains the `k3dm-platform-ops-slack-url|k3dm|` row.

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
    text: Operator seeds the Keychain record once; after make platform-ops (and after the 10-29 rebuild drill) kubectl describe secret shows slack-incoming-webhook-url with a nonzero size, and the next ACG expiry or rotation notice arrives in Slack.
interface:
  - make platform-ops (deploy_argocd_platform_ops)
  - kubectl -n platform-ops describe secret platform-ops-notifications
```

**As landed (Claude's review, 2026-10-30).** `argocd_sync_notifications_slack_secret` writes a
`--type=merge` patch of the one key from a `mktemp` file (base64, never argv) under `_no_trace`; the
missing-key warning reads `get secret -o json | jq -e` with all output discarded. Claude restored an
unrelated reworded log line, and strengthened the tests: the patch is `--type=merge` and carries only
`slack-incoming-webhook-url` decoding to the Keychain value; a deploy with the record present runs the
patch. 6/6 pass; the platform-ops bootstrap, rotator and `argocd.bats` suites still pass; shellcheck
clean. Red on the pre-fix `argocd.sh`: tests 1, 2, 4, 5. Mutations, all red: `--type=json`, no base64,
no empty-value check, deploy without the sync call.

## Workaround

The operator patches the URL in by hand from their own shell, as `make platform-ops` prints. Pick
the URL for the channel the v1.43.8 routing plan names.

## Files

- `scripts/plugins/argocd.sh` (`argocd_sync_notifications_slack_secret`, `deploy_argocd_platform_ops`)
- `scripts/etc/machine/secrets.hub.list`
- `scripts/tests/plugins/argocd_platform_ops_notifications_slack.bats` (new)
- `scripts/tests/bin/machine_setup.bats` or `machine_secrets.bats` only if a test counts hub secrets
- `docs/howto/platform-ops-notifications.md` (new), linked from README How-To
- `CHANGELOG.md` (one `### Fixed` line under `[Unreleased]`)

## What NOT to Do

- Do NOT read, print or log the URL; check the key by name or size only.
- Do NOT reuse the Hermes token or any broad credential for the Vault read.
- Do NOT edit `scripts/lib/foundation/`.
- Do NOT add a Vault path, policy or ExternalSecret for this.
- Do NOT touch a real Keychain or cluster in tests; do not run `make platform-ops`.
- Do NOT create a PR, commit to `main`, or skip hooks with `--no-verify`.
- Write the must_not tests first and show N1 red on a temp copy of the pre-fix `argocd.sh`.
