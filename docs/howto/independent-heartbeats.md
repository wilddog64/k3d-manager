# Independent outbound heartbeats

The sender and generated config are disabled by default. It never installs or enables itself, contacts Healthchecks.io during rendering, or performs remote recovery. The original webhook outage remains undiagnosed. Healthchecks.io currently documents a 20-check free account; verify the actual account limit and alert destination when enrolling.

## Checks and interpretation

| Check | Period / grace | Evidence |
|---|---:|---|
| `m4-host` | 1m / 3m | Scheduler ran and outbound path reached provider. A missed ping means host or network unknown, not proven power loss. |
| `m4-hermes` | 1m / 30m | Fresh private completed-cycle timestamp. Hermes normally runs every 300s; the 1200s freshness window gives a full 15m for a long cycle plus jitter before one heartbeat reports failure, and the 30m provider grace prevents a one-minute outage alert. |
| `m4-webhook` | 1m / 3m | Reader-authenticated loopback `/api/v1/health?quick=1` returned bounded, schema-valid JSON. Handler responsiveness is the check; `all_ok` separately reports downstream dependency health. A timeout cannot distinguish host from network failure. |
| `m4-cloud-bridge` | 2m / 6m | Fresh private timestamp after a successful poll tick. |
| `hostinger` | 2m / 6m | Its local scheduler/outbound path sent directly to the external provider; it makes no calls to m4/m2. |

Healthchecks.io sends a failure state after a `/fail` ping and applies its configured missed-ping grace to silent checks. A later success ping restores the check. Sender errors are not retried immediately; the next attempt is at that identity's configured interval. Set periods, grace, and notification channels manually; never enable auto-provisioning. Provider delivery and provider availability are external dependencies.

## Enrollment and credentials

Create five checks manually in the provider UI, configure periods/grace as above, and verify an alert destination using the provider's own test facility. Keep UUID ping URLs out of shell arguments, source control, logs, and tickets. On m4, store each complete HTTPS ping URL in a named login-Keychain item `k3dm-heartbeat-<identity>` for account `k3dm`. The webhook probe uses the separate reader credential `k3dm-webhook-token-reader`; it never uses the admin webhook token. On Hostinger, store its one URL in an owner-only (`0600`) file, owned by the service account.

Copy `scripts/etc/heartbeat/checks.example.json` to m4's protected config. It contains exactly the four m4 identities and no URL or credential. Create a separate Hostinger config with `role: "hostinger"`, `enabled: false`, one disabled `hostinger` entry at 120s / 360s, its protected file source, and a writable owner-only `state_dir`. The sender rejects mixed or incomplete role sets; m4 cannot run Hostinger and Hostinger cannot run m4 checks. After manual enrollment and credential provisioning, an operator can run `bin/k3dm-heartbeat --config <path> --validate-credentials` to validate every provider URL and the separate m4 reader credential without printing secrets, probing services, or pinging the provider. Then explicitly set top-level `enabled: true` and enable only enrolled entries.

Use `--check` to run one identity. A private state directory records each identity's last attempt and holds a nonblocking OS lock across probe and report, preventing concurrent duplicate pings. `bin/k3dm-heartbeat --dry-run` validates config and prints the plan without reading credentials, state, markers, or probing/network access. `bin/k3dm-heartbeat-setup --dry-run` previews rendering without reading config or writing files. Normal setup rendering validates the selected role and a Python 3.9+ interpreter, then creates candidate config/unit files only; it refuses to overwrite existing candidates and does not load launchd/systemd jobs. Review candidates, install through a separately approved operator action, and verify scheduler state.

## Investigation and maintenance

For an explicit failing check, inspect that machine's local logs and the component's own status. For missing pings, classify the cause as host, scheduler, outbound network, or provider unknown until evidence separates them. Check provider status and alert delivery independently. Hermes/bridge marker freshness means last completed cycle/poll, not process existence. The webhook route can fail due to dependencies even when its process accepts requests.

For planned downtime, disable the individual check in provider UI (or set local `disabled: true` / a numeric `maintenance_until` epoch in its config) before stopping the service, then restore it after maintenance. Do not leave duplicated senders active: each identity should have exactly one scheduler. Disable/load the local schedule only through the operator's normal launchd or systemd procedure.

There is no watchdog restart, remote reboot, or automatic infrastructure mutation. A powered-off m4 cannot report its own failure or recover itself; Hostinger is an independent observer, not a control path to m4. A provider outage can make all reports unavailable. Operator live validation of failure, recovery, alert delivery, and maintenance suppression is still required before claiming end-to-end alerting works.
