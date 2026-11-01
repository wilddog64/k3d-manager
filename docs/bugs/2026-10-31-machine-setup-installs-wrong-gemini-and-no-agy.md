# Bug: machine setup installs MacPaw's "Gemini" disk cleaner instead of the Gemini CLI, and never installs agy

**Status:** OPEN
**Priority:** P2
**Severity:** medium — the hub's Slack AI analysis is unavailable ("agy: not-installed; gemini: not-installed"); workaround is a manual install and login on the hub
**Approval:** operator, 2026-10-31 ("go ahead" to dispatch, after choosing the make machine-setup route over a manual install)
**Filed:** 2026-10-31
**Detected by:** operator (Slack ask-docs reply on the M5 hub), root cause by Claude
**Affected:** `scripts/etc/machine/brew.hub.list`, `scripts/etc/machine/brew.worker.list`, `bin/k3dm-machine-setup`, `docs/howto/m5-hub-migration.md`
**Branch:** `k3d-manager-v1.43.13`
**Related:** `docs/bugs/2026-10-31-hub-migration-drops-webhook-slack-bot-config.md` (another hub-migration gap); `docs/howto/gemini.md`

## Observed failure

On 2026-10-31 an ask-docs question the count matcher did not take ("how may P2 bugs…") reached the AI path on
the M5 hub and answered "AI analysis unavailable — agy: not-installed; gemini: not-installed". The webhook's
LaunchAgent PATH (`~/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin`) is fine; neither binary exists on
the M5.

## Root cause

1. `brew.hub.list` and `brew.worker.list` line 82 hold `cask:gemini`. That cask is MacPaw's Gemini duplicate-file
   cleaner (`brew info --cask gemini`: "Disk space cleaner that finds and deletes duplicated and similar files"),
   not Google's CLI. On the M4, `gemini` is `@google/gemini-cli`, which Homebrew ships as the `gemini-cli` formula.
   Machine setup therefore installed a disk cleaner on the M5 and reported `brew:gemini ok`.
2. The manifests list `cask:antigravity` (the desktop app), which does not contain `agy`. The CLI is the separate
   `antigravity-cli` cask. On the M4 `agy` (1.4.12) sits in `~/.local/bin` from its own installer, so the manifest
   derived from the M4's brew leaves never saw it.
3. Both CLIs need an interactive Google login per machine; setup does not say so, and nothing checks the webhook
   can find them.

## Fix

1. In `brew.hub.list` and `brew.worker.list`, replace `cask:gemini` with the formula `gemini-cli` and add
   `cask:antigravity-cli`. Leave `cask:antigravity` (the app) as it is.
2. `bin/k3dm-machine-setup` adds one report line per AI CLI on the hub and worker roles: `ai:agy` and `ai:gemini`,
   `ok` when the command resolves on the webhook LaunchAgent's PATH (the same PATH list the webhook plist template
   sets), else `missing`. It does not log in, read credentials or run a model call.
3. `docs/howto/m5-hub-migration.md` gets a step: after setup, log in once with `agy` and with `gemini` in the
   operator's shell on the new hub, then ask the Slack bot a question the count matcher does not take.
4. Setup never uninstalls anything. Removing the MacPaw app already installed on the M5 is left to the operator
   (one line in the howto).

## Files

- `scripts/etc/machine/brew.hub.list`, `scripts/etc/machine/brew.worker.list`
- `bin/k3dm-machine-setup`
- `scripts/tests/bin/machine_setup.bats`
- `docs/howto/m5-hub-migration.md`
- `CHANGELOG.md`

## What NOT to do

- Do not install either CLI with `npm`, `curl | sh` or a copied binary.
- Do not script the Google login or store a token.
- Do not run `brew uninstall` from setup.

## Acceptance

```yaml
must:
  M1: the hub and worker manifests install the gemini-cli formula and the antigravity-cli cask, and no manifest contains cask:gemini
  M2: on the hub and worker roles, setup reports ai:agy and ai:gemini as ok when the commands resolve on the webhook PATH, and missing when they do not (paired)
  M3: the migration howto names the per-machine login for agy and gemini and a Slack check of the AI path
must_not:
  N1: setup never reports an AI CLI ok when it is absent from the webhook PATH, even if it exists elsewhere (for example only on the interactive shell's PATH)
  N2: setup never runs brew uninstall, a login, or a model call for agy or gemini, and never reads a Keychain item for them
evidence:
  E1:
    proves: [M1, M2, N1, N2]
    kind: offline
    intent: >-
      You will see machine_setup.bats grep both manifests for gemini-cli and cask:antigravity-cli and find no
      cask:gemini; then run setup in a scratch HOME (the fixture first asserts HOME and the brew stub are under the
      test tmpdir) with stub agy/gemini placed once on the webhook PATH (report says ok) and once only on a
      different directory on the caller's PATH (report says missing). A command log from the brew, agy, gemini and
      security stubs shows no uninstall, login, prompt or find-generic-password call. It failed if N1's
      elsewhere-only case reports ok.
    what: bats scripts/tests/bin/machine_setup.bats
  E2:
    proves: [M2, M3]
    kind: live
    intent: >-
      You will see, on the M5 after brew install gemini-cli and --cask antigravity-cli and one login each, the setup
      report show ai:agy ok and ai:gemini ok, and a Slack ask-docs question outside the count matcher return an AI
      answer instead of "AI analysis unavailable".
    what: operator on the M5 hub, then Claude reads the report
interface:
  - bin/k3dm-machine-setup (role hub/worker; scratch HOME; PATH; manifests under scripts/etc/machine/)
  - scripts/etc/machine/brew.hub.list, brew.worker.list
```
