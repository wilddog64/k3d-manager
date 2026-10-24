# Bug: the monthly Prometheus password rotation never posts its Slack notice

**Status:** LANDED `a54d9489` 2026-10-24. E1 green (bats 25/25, shellcheck clean); the new tests fail on the pre-fix code (the function was missing, exit 127). Review note: test 3's `curl` stub calls `fail`, which the code's `|| true` would hide, so it doesn't fully prove curl is skipped (minor). E2 live pending: next run 2026-11-01 00:00 PDT or an operator run. Was OPEN, filed 2026-10-24.
**Priority:** P3
**Severity:** low — the rotation itself works; only its notice is missing
**Release:** v1.43.5 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-24, by Claude, while writing `docs/plans/v1.43.8-slack-route-system-notices-to-status-channel.md`
**Approval:** explicit 2026-10-24. The operator said: "go ahead and you can file prometheus gap as P3 bug and dispatch it" (filing and dispatch).
**Component:** `scripts/plugins/observability.sh` (`observability_rotate_prometheus_basic_auth`)
**Related:** `docs/plans/v1.43.8-slack-route-system-notices-to-status-channel.md` (routing rule: system-started notices go where `platform-ops-notifications` points)

## Problem

`observability_rotate_prometheus_basic_auth` posts "Monthly service password rotation completed:
Prometheus" only when `SLACK_WEBHOOK_URL` is set. It runs from the LaunchAgent
`com.k3d-manager.prometheus-credential-rotator` (template
`scripts/etc/launchd/com.k3d-manager.prometheus-credential-rotator.plist.tmpl`), whose
`EnvironmentVariables` holds only `HOME` and `PATH`. So the variable is never set and the notice is
skipped silently.

Evidence, 2026-10-24: the installed plist's environment keys are `HOME` and `PATH`. The log
`~/Library/Logs/k3dm-prometheus-credential-rotator.log` (last written 2026-10-01 00:00 PDT) ends with
`Prometheus basic-auth rotated and ACG web config reapplied`, so the 2026-10-01 rotation ran and posted
nothing.

The Grafana, Keycloak, ArgoCD and ACG-expiry notices read the incoming-webhook URL from Secret
`platform-ops/platform-ops-notifications`, key `slack-incoming-webhook-url`, on the hub. The Prometheus
notice should use the same URL, so it goes to the same channel as the other rotation notices
(#grafana-notification after the v1.43.8 Secret swap).

Today's post also puts the URL in `curl`'s argv, where `ps` can see it.

## Fix

### F1. Read the URL from the hub Secret

In `observability_rotate_prometheus_basic_auth`, replace the `SLACK_WEBHOOK_URL` block:

```bash
  if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
    curl -sf --max-time 10 -X POST "${SLACK_WEBHOOK_URL}" \
      -H 'Content-Type: application/json' \
      -d '{"text":"🔐 Monthly service password rotation completed: Prometheus. Password values are not included."}' >/dev/null || true
  fi
```

with a call to a new private helper `_observability_notify_rotation`:

1. The URL is `SLACK_WEBHOOK_URL` when that is set; otherwise, read it from Secret
   `platform-ops-notifications` in namespace `platform-ops`, context `k3d-k3d-cluster`, key
   `slack-incoming-webhook-url`, base64-decoded. Use `_kubectl` with stderr discarded.
2. If there is no URL, or reading the Secret fails, print `_warn "[observability] no Slack incoming
   webhook — rotation notice not sent"` and return 0. The rotation must not fail because of the notice.
3. Post the same text as today with `curl -sf --max-time 10 --config -`, sending
   `url = "<url>"` on stdin, so the URL never appears in argv. A failed post is ignored (`|| true`).
4. Never print, log or trace the URL. Run the helper with xtrace off (`set +x` restored after, as
   `observability.sh:161` does), or with the kubectl and curl calls outside any trace.

No plist change is needed: the LaunchAgent already has `PATH` with `kubectl`, and the function
already reads `vault-root` from the hub the same way.

## Tests

`scripts/tests/lib/observability.bats` (stub `_kubectl` and `curl` as shell functions or on `PATH`,
recording their arguments and stdin to `BATS_TEST_TMPDIR`; no network, no real cluster):

1. `SLACK_WEBHOOK_URL` unset and the stubbed Secret returns a base64 URL: `curl` is called once, the URL
   is on its stdin, and the URL is not in `curl`'s arguments.
2. `SLACK_WEBHOOK_URL` set: that URL is used and `_kubectl` is not asked for `platform-ops-notifications`.
3. The Secret read fails (stub exits 1): the helper prints the warning, returns 0, and `curl` is not called.
4. The URL string never appears in the helper's stdout or stderr in tests 1–3.
5. `_kubectl` is asked for namespace `platform-ops`, context `k3d-k3d-cluster`, Secret
   `platform-ops-notifications`.

Show tests 1 and 4 red on the pre-fix `observability.sh`.

## Files

- `scripts/plugins/observability.sh`
- `scripts/tests/lib/observability.bats`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: With SLACK_WEBHOOK_URL unset, the Prometheus rotation notice is posted to the URL in hub Secret platform-ops/platform-ops-notifications key slack-incoming-webhook-url.
  - id: M2
    text: A set SLACK_WEBHOOK_URL still takes precedence.
  - id: M3
    text: A missing or unreadable Secret prints a warning and the rotation still exits 0.
must_not:
  - id: N1
    text: The webhook URL must not appear in curl's argv, stdout, stderr or logs.
  - id: N2
    text: A notice failure must not fail the rotation.
  - id: N3
    text: Tests must not call a real cluster, Slack or the network.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, N1, N2, N3]
    text: bats scripts/tests/lib/observability.bats green; tests 1 and 4 red on the pre-fix observability.sh.
  - id: E2
    kind: live
    proves: [M1, N1]
    text: The next scheduled run (1st of the month 00:00 PDT), or an operator-run observability_rotate_prometheus_basic_auth, posts the notice to the platform-ops-notifications channel (operator screenshot); Claude checks the rotator log has no hooks.slack.com string.
interface:
  - observability_rotate_prometheus_basic_auth (notice step via _observability_notify_rotation)
  - env SLACK_WEBHOOK_URL
  - Secret platform-ops/platform-ops-notifications key slack-incoming-webhook-url (context k3d-k3d-cluster)
```

## Definition of Done

- [ ] F1 and a CHANGELOG `[Unreleased]` `### Fixed` entry; only the Files above change.
- [ ] `bats scripts/tests/lib/observability.bats` green; `shellcheck scripts/plugins/observability.sh` adds no warnings; paste summaries.
- [ ] Tests 1 and 4 shown red on a temp copy of the pre-fix `observability.sh`.
- [ ] Commit: `fix(observability): post the Prometheus rotation notice from the hub Secret`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT read the real Secret, call Slack, run the rotation, or touch the real LaunchAgent.
- Do NOT add the webhook URL to the plist template.
- Do NOT modify files outside the Files list.
