# Bug: Slack slash commands trust command role instead of caller authorization

**Filed:** 2026-10-08
**Status:** OPEN
**Severity:** HIGH (authenticated Slack user privilege escalation)
**Branch:** k3d-manager-v1.42.0
**Reviewed revision:** 6e54ca66bddf47973eff57216d290b5df821b529
**Component:** workers/slack-relay/index.js; bin/k3dm-webhook; scripts/lib/webhook/policy.py
**Evidence:** [Offline security review](../issues/2026-10-08-webhook-cloud-bridge-security-review.md)

## Problem

The relay verifies Slack signatures, then selects COMMAND_ROLES[command] regardless of userId.
For /cluster-down that is admin. Its payload contains action/provider/response_url, but not
slack_user_id. The relay sends its configured webhook token with X-K3DM-Role: admin.
The webhook calls _request_role(headers, token_role), applying _effective_make_role only to
the Make handler. With an admin-bound relay token, cluster-down therefore passes the admin
policy even if the Slack caller is mapped reader or is unmapped. This differs from /k3dm
and /slack/events, which consult the caller role map.

Other similarly relayed privileged commands include cluster-up, cluster-resume,
cluster-refresh, cleanup-stale-sandbox and argocd-upgrade. Review each rather than assuming
one route fix protects all. Hermes approvals have a separate flow and are not established
as affected by this reproduction.

## Preconditions and impact

Requires a valid Slack-signed slash request and a relay token with the necessary privileges;
an unauthenticated internet request cannot forge that signature. Workspace command visibility
and the deployed relay/token setup remain unverified. A Slack user allowed to invoke these
commands, including a compromised low-privilege account, may request cluster mutation beyond
their mapped role. This is not proof of arbitrary host execution or an incident.

## Evidence

Offline AST extraction executed the current policy functions with an admin relay token,
admin command header, and Slack lookup stub returning reader:

```text
Relayed cluster-down role, caller mapped reader: admin admin policy permits: True
Relayed k3dm role, caller mapped reader: reader
```

No cluster worker was run. Source tracing supplies the relay-to-handler connection;
the fixture itself tests the policy seam, not a live Slack end-to-end exploit.

## Required fix and acceptance

- Carry the signed Slack caller identity through every relayed action and enforce its
  mapped role centrally, capped by the bearer credential and route/target capability.
- Unknown Slack callers must be refused, not promoted by COMMAND_ROLES.
- Keep direct-token/bridge callers working under their token-bound roles. Do not apply a
  missing Slack identity rule indiscriminately to internal direct-token requests.
- Treat relay identity metadata as trusted only through an authenticated relay boundary;
  retain direct admin credentials as explicitly admin-capable.
- Add reader/operator/admin/unmapped coverage for every privileged slash route, asserting
  denial occurs before any worker or subprocess starts. Preserve /k3dm and thread behavior.
- Verify signature failure, token-role ceilings, cloud-runner capabilities and audit attribution.

## Related

[Earlier role normalizer bug](2026-09-24-normalize-role-defaults-unknown-actor-to-admin.md)
is fixed and is a different mechanism. This defect uses a valid admin command role.
