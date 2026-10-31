# Bug: machine setup installs live-hub agents on a new Mac before cut-over, and misses two Hermes credentials

**Status:** LIVE-VERIFIED 2026-10-30 — `30d1aab6` (Luna, amended by Claude); E2 live on the M5 at `9e59379c`: secrets ok, no agent installed with AGENTS=skip
**Fix commit:** 30d1aab6
**Live evidence:** 2026-10-30 · run machine-setup-role-hub-agents-skip · env m5-air · scenario hub-agents-not-installed-before-cutover · commit 9e59379c · proves E2
**Priority:** P2
**Approval:** operator, 2026-10-30 ("go ahead to file a bug and dispatch to Luna")
**Filed:** 2026-10-30
**Detected by:** Claude (reading the operator's M5 `make machine-setup ROLE=hub FROM=m4-air.local SECRETS=skip` output)
**Affected:** `bin/k3dm-machine-setup` agent stage; `scripts/etc/machine/agents.hub.list`, `secrets.hub.list`, `not-installed.list`; `Makefile` `machine-setup`
**Branch:** `k3d-manager-v1.43.12`
**Related:** `docs/bugs/2026-10-30-machine-secrets-pull-fails-on-locked-local-keychain.md` (added `SECRETS=skip`); `docs/bugs/2026-10-09-launchd-agents-hardcode-homebrew-python3-hermes-down.md` (same launchd PATH class)

## Observed failure

On the M5, which is not the hub yet, setup's agent stage installed every hub LaunchAgent and ran
`bin/k3dm-webhook-setup` while the M4 still runs the hub. `SECRETS=skip` covers only secret prompts.

1. **Token rotator.** `com.k3d-manager.webhook-token-rotate` (every 6 h) was loaded on the M5. The M5 has
   `npx`, so its first run would push a new token to the Cloudflare Slack relay and the M5 keychain only.
   The M4 webhook, which still serves the hub, keeps the old token and rejects every relayed command.
2. **The rotator has never worked on the M4.** Its log shows 174 runs ending `npx: command not found`
   (launchd's PATH has no Homebrew). The script exits before changing anything, so nothing broke. A PATH
   fix alone would make it rotate, but it does not update the `cicd/k3dm-webhook-token` Secret
   (Alertmanager → webhook), the `K3DM_WEBHOOK_TOKEN` GitHub secret, or the relay copy that
   `deploy-worker.yml` re-uploads from that secret. Turning it on would break those three consumers.
   The webhook token is static in practice.
3. **Hermes credentials.** `bin/k3dm-hermes-setup` failed: `k3dm-hermes-gh-token` and `k3dm-slack-webhook`
   (account `k3dm`) are missing on the M5. Both exist on the M4, but neither is in `secrets.hub.list`,
   so `FROM=` never copies them. Setup ended with `Error 1`.

## Fix

### `bin/k3dm-machine-setup` and `Makefile`

- New option `--agents install|skip` (default `install`). Any other value: usage error, exit 2 (same
  shape as `--secrets`).
- `skip`, in setup mode: no agent target is installed and no `bin/*-setup` command runs.
  `smartcd-install` is a shell tool, not an agent, and still runs. Each agent not already present is reported `skipped (AGENTS=skip)` through `record_failure`,
  as `skipped (hub only)` is today. An agent already installed still reports `ok`.
- `Makefile` `machine-setup` forwards `$(if $(AGENTS),--agents "$(AGENTS)")`.
- Usage line names `[--agents install|skip]`.

### Manifests

- `secrets.hub.list`: add
  - `k3dm-hermes-gh-token|k3dm|Hermes R4 CI re-run PAT|operator: see docs/guides/hermes.md`
  - `k3dm-slack-webhook|k3dm|Hermes Slack summary relay|operator: see docs/guides/hermes.md`
- `agents.hub.list`: remove `install-token-rotator`.
- `not-installed.list`: add `install-token-rotator|not installed by setup: rotation updates only the Cloudflare relay and Keychain, not the cicd Secret or GitHub secret (docs/bugs/2026-10-30-machine-setup-installs-hub-agents-before-cutover.md)`.
- Leave `is_hub_agent` and `agent_label` as they are.

### Docs

- `docs/howto/machine-setup.md`: in the M5 cut-over steps, run setup with `SECRETS=skip AGENTS=skip`
  before cut-over, and rerun without `AGENTS=skip` at cut-over, after the old Mac's agents are stopped.
  Name `AGENTS=skip`.
- `docs/howto/launchd-daemons.md`, section `com.k3d-manager.webhook-token-rotate`: correct the Action
  (it pushes a new token to the Cloudflare Worker and the Keychain and restarts the webhook; it does not
  use Vault), and say machine setup does not install it and why (the three consumers above). Change its
  table row on line 14 to match.

**As landed (Claude's review, 2026-10-30).** Luna had moved the `skipped (hub only)` check below the
installed-plist check and duplicated it into check mode; Claude restored the original order, so worker
and console output is unchanged. Test amendments: the M1/N3 test now lists `bin/k3dm-webhook-setup` and
asserts it reports `skipped (AGENTS=skip)` (the skip runs before the TTY gate); its three mid-test
`! grep` lines end with `|| false`; the installed-agent assertion is a whole-line match
(`^agent:install-cleanup +ok$`), because the old glob matched any later `ok`. 52/52 pass; shellcheck
clean. Mutations red on temp copies: no skip branch, skip before the installed check, default `skip`,
no value check.

**Live check E2 (2026-10-30, 09:3x PDT).** The operator ran `make machine-setup ROLE=hub
FROM=m4-air.local SECRETS=skip AGENTS=skip` on the M5 at `9e59379c`. `k3dm-hermes-gh-token` and
`k3dm-slack-webhook` were exported and `copied`; every `secret:` line read `ok`. No agent was installed:
the agents installed by the earlier pre-fix run reported `ok` (plist present, N3), and
`bin/k3dm-hermes-setup` and `bin/k3dm-heartbeat-setup` reported `skipped (AGENTS=skip)`. Make still exits
1, because an `AGENTS=skip` skip goes through `record_failure`, as the spec asked. The pre-fix run's 12
LaunchAgents (installed 08:54) are still loaded on the M5, including `webhook`, `cloud-bridge` and
`webhook-token-rotate` (6 h interval, not yet run); the operator is booting them out.

## Files

- `bin/k3dm-machine-setup`
- `Makefile`
- `scripts/etc/machine/agents.hub.list`
- `scripts/etc/machine/secrets.hub.list`
- `scripts/etc/machine/not-installed.list`
- `scripts/tests/bin/machine_setup.bats`
- `docs/howto/machine-setup.md`
- `docs/howto/launchd-daemons.md`
- `CHANGELOG.md` (one `### Fixed` line under `[Unreleased]`)

## What NOT to do

- Do not change `bin/rotate-webhook-token`, the rotator plist template, or the `install-token-rotator`
  Make target. Do not add a PATH to the rotator.
- Do not change `--secrets`, the secrets copy (`bin/k3dm-machine-secrets`), or check mode.
- Do not run `make machine-setup`, `launchctl`, or any install target outside test fixtures; tests use
  the existing fixture root and stubs (`setup_machine_fixture`, `run_machine`, `tty_machine`).
- Do not read or print keychain values.
- Do not create a PR, commit to `main`, or skip hooks with `--no-verify`.
- Write the must_not tests first and show them red against the pre-fix code on a temp copy.

## Acceptance

```yaml
must:
  M1: setup --role hub --agents skip installs no agent and runs no bin/*-setup command, and reports each agent not already installed as "skipped (AGENTS=skip)".
  M2: make machine-setup ROLE=<role> AGENTS=skip passes --agents skip to bin/k3dm-machine-setup.
  M3: secrets.hub.list lists k3dm-hermes-gh-token and k3dm-slack-webhook with account k3dm, so a FROM pull copies them.
  M4: install-token-rotator is not in any agents.*.list and is in not-installed.list with a reason.
  M5: The machine-setup how-to names AGENTS=skip for the pre-cut-over run; launchd-daemons.md says setup does not install the rotator and describes what it actually updates.
must_not:
  N1: --agents with a value other than install or skip exits 2.
  N2: Without --agents, setup still installs a missing agent (install is the default).
  N3: With --agents skip, an agent whose LaunchAgent plist already exists still reports ok, and smartcd-install still runs.
evidence:
  E1: {proves: [M1, M2, M3, M4, N1, N2, N3], kind: offline, what: "bats scripts/tests/bin/machine_setup.bats (fixture root, stub make and bin/*-setup); N1-N3 red on the pre-fix setup"}
  E2: {proves: [M1, M3], kind: live, what: "operator on the M5: make machine-setup ROLE=hub FROM=m4-air.local SECRETS=skip AGENTS=skip copies both Hermes items and installs no agent; operator or Claude reads it"}
interface:
  - bin/k3dm-machine-setup --role ROLE [--from HOST] [--secrets ask|skip] [--agents install|skip]
  - make machine-setup ROLE=<role> [FROM=<host>] [SECRETS=skip] [AGENTS=skip]
  - scripts/etc/machine/{agents,secrets}.hub.list, scripts/etc/machine/not-installed.list
```
