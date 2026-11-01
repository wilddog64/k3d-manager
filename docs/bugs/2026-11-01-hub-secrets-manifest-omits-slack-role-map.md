# Bug: hub secrets manifest omits `k3dm-slack-role-map`, so the new hub's webhook maps every Slack user to `reader`

**Status:** OPEN
**Priority:** P2
**Severity:** medium — after the M5 cutover every Slack command above `reader` is refused (`/cluster-up`: "forbidden: cluster-up requires role admin"); workaround: add the Keychain item on the hub by hand and restart the webhook
**Approval:** operator, 2026-11-01 (Slack screenshot 515, "seems this come from machine-setup for m5"; hub-migration gaps are filed as found)
**Filed:** 2026-11-01
**Detected by:** operator (/cluster-up from Slack), root cause by Claude
**Affected:** `scripts/etc/machine/secrets.hub.list`; `bin/k3dm-machine-setup` (`check_secrets`, `FROM=` pull); `bin/k3dm-webhook-doctor`
**Branch:** `k3d-manager-v1.43.13`
**Related:** `docs/bugs/2026-11-01-acg-up-on-dev-node-restarts-retired-local-hub.md`; `docs/plans/v1.43.12-m5-new-hub-one-command.md`; `memory: project_m5_air_new_hub`

## Observed failure

2026-11-01 07:18 PST, Slack `/cluster-up` twice: "⚠️ forbidden: cluster-up requires role admin". M5
`~/.local/share/k3d-manager/audit/remote-operator.jsonl`:
`{'path': '/api/v1/cluster', 'actor': 'slack:wilddog64:U4C9LDQP2', 'role': 'reader', 'allowed': False, 'reason': 'requires admin'}` (×2, 15:18:38 and 15:18:54 UTC).
`security find-generic-password -s k3dm-slack-role-map` → rc 44 (not found) on the M5, rc 0 on the M4 (account `k3dm`).

## Root cause

The webhook caps a relayed request at the caller's role from `K3DM_SLACK_ROLE_MAP` or Keychain `k3dm-slack-role-map`
(account `k3dm`; `scripts/lib/webhook/auth.py:_load_slack_role_map`); a user who is not in the map is `reader`. The hub's secrets
manifest `scripts/etc/machine/secrets.hub.list` lists the Slack signing secret and bot token but not the role map,
so `make machine-setup ROLE=hub FROM=<old hub>` never copied it and `--check` never reported it missing.

## Fix

1. Add `k3dm-slack-role-map|k3dm|Slack user → webhook role map (U…:admin,…)|operator: see docs/howto/slack-slash-commands.md`
   to `secrets.hub.list`, so `--check` reports it and `FROM=` pulls it.
2. `bin/k3dm-webhook-doctor`: report the role map as `missing` when it parses to zero entries, with no IDs or roles printed.
3. `docs/howto/slack-slash-commands.md`: name the Keychain item and say the webhook reads it at start (restart after a change).

## Files

- `scripts/etc/machine/secrets.hub.list`
- `bin/k3dm-webhook-doctor`
- `scripts/tests/bin/` (machine-setup and webhook-doctor suites)
- `docs/howto/slack-slash-commands.md`
- `CHANGELOG.md`

## What NOT to do

- Do not default unmapped users to anything above `reader`; fail closed stays.
- Do not print the map's contents (user IDs, roles) in any check or doctor output.
- Tests use a scratch HOME and a stub `security` whose output is captured from a real read-only run (host and date in a comment).

## Acceptance

```yaml
must:
  M1: bin/k3dm-machine-setup --role hub --check reports secret:k3dm-slack-role-map ok when the item exists and as a failure when it is missing
  M2: machine-setup FROM=<host> treats a missing k3dm-slack-role-map as missing and pulls it (the manifest lists it for role hub)
  M3: k3dm-webhook-doctor reports the role map present when it parses to at least one entry (paired positive control for N1)
must_not:
  N1: k3dm-webhook-doctor never reports the role map healthy when it is absent or parses to zero entries
  N2: no check or doctor output contains a Slack user ID or role taken from the map
  N3: an unmapped Slack user still resolves to reader
evidence:
  E1:
    proves: [M1, M2, M3, N1, N2, N3]
    kind: offline
    intent: >-
      You will see BATS/pytest with a stub security: --check fails on a missing role map (red on the pre-fix manifest)
      and passes with it; doctor says missing for absent/empty and present for one entry, with no IDs in output.
    what: bats scripts/tests/bin/machine_setup.bats; pytest on the webhook doctor tests
  E2:
    proves: [M1, N3]
    kind: live
    intent: You will see on the M5 --check report secret:k3dm-slack-role-map ok and Slack /cluster-up accepted (audit role admin).
    what: operator /cluster-up; Claude reads the M5 audit log
interface:
  - bin/k3dm-machine-setup --role hub --check
  - make machine-setup ROLE=hub FROM=<host>
  - bin/k3dm-webhook-doctor
  - Keychain item k3dm-slack-role-map (account k3dm)
  - ~/.local/share/k3d-manager/audit/remote-operator.jsonl
```

## Workaround applied (2026-11-01)

The operator added `k3dm-slack-role-map` (account `k3dm`) on the M5 and restarted `com.k3d-manager.webhook`. The next
`/cluster-up` (job `ec9ce66c`) was accepted: audit `2026-11-01T15:23:38Z /api/v1/cluster actor slack:wilddog64:U4C9LDQP2
role admin allowed True`. The manifest fix is still open.
