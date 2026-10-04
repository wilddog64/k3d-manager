# Bug: the Hermes LaunchAgent template has no approval drain URL, so a reinstall turns Slack approvals off

**Filed:** 2026-10-04, Claude
**Branch:** `k3d-manager-v1.41.0`
**Status:** OPEN
**Severity:** low. Slack approvals silently stop working after any Hermes reinstall.

## Observed

`docs/guides/hermes.md` § "Slack approvals (opt-in)" step 4 has the operator add
`K3DM_HERMES_APPROVAL_DRAIN_URL` to the installed plist by hand. The operator did this on 2026-10-04 with
`PlistBuddy`.

`bin/k3dm-hermes-setup` → `_install_hermes_agent` (lib-foundation) re-renders
`~/Library/LaunchAgents/com.k3d-manager.hermes.plist` from
`scripts/etc/launchd/com.k3d-manager.hermes.plist.tmpl`. The template has no drain-URL key, so every
reinstall drops it. When that happens there is no drain and no Approve/Deny buttons, and nothing is
logged.

## Why the URL cannot simply be hard-coded today

`bin/k3dm-hermes` `_poll` gates the Approve/Deny buttons on `drain_url` alone:

```python
        if drain_url and event.get("proposals"):
            blocks = interactive_blocks(event["text"], event["proposals"], event["nonce"])
```

On an install where `make hermes-approvals-setup` was never run, a template-supplied URL would post
buttons that do nothing. The drain fails closed in `fetch_approvals` because the token is empty, but
the buttons still appear.

The fix moves the opt-in from "the URL is set" to "the drain token is in the Keychain". The token
exists only after `make hermes-approvals-setup`.

## Fix spec

### File 1 — `scripts/etc/launchd/com.k3d-manager.hermes.plist.tmpl`

After the `K3DM_HERMES_APP_CONTEXT` key/string pair, insert:

```xml
    <key>K3DM_HERMES_APPROVAL_DRAIN_URL</key>
    <string>https://k3dm-slack-relay.k3dm.workers.dev/hermes/approvals</string>
```

The value is static, like `K3DM_HERMES_APP_CONTEXT`. It is not a secret. Do not add a `{{…}}`
placeholder, because the renderer lives in lib-foundation.

### File 2 — `bin/k3dm-hermes`, `_poll`

Replace

```python
    drain_url = os.environ.get("K3DM_HERMES_APPROVAL_DRAIN_URL", "")
```

with

```python
    drain_url = os.environ.get("K3DM_HERMES_APPROVAL_DRAIN_URL", "")
    if drain_url and not _keychain_secret(APPROVAL_DRAIN_SERVICE):
        drain_url = ""
```

With no drain token, Hermes now behaves as if the URL were unset: no buttons and no drain. Do not
change `_drain_approvals` or `approvals.py`.

### File 3 — `bin/k3dm-hermes-setup`

The template now always sets the URL, so the `if [[ -n "${K3DM_HERMES_APPROVAL_DRAIN_URL:-}" ]]` guard
at setup time is wrong.

- Remove that outer `if`/`fi` and keep the inner Keychain check.
- Keep the "present" line as is.
- Replace the "missing" note with:
  `[k3dm-hermes-setup] note: k3dm-hermes-approval-drain-token not found — Slack approvals stay off until you run make hermes-approvals-setup (docs/guides/hermes.md#slack-approvals-opt-in).`
  It still goes to stderr, and the script still exits 0.

### File 4 — tests

**`scripts/tests/hermes/test_app_health.py`.** Extend
`test_launchagent_template_enables_app_health_for_ubuntu_hostinger`, or add a sibling test in the same
style, to assert:

```python
environment["K3DM_HERMES_APPROVAL_DRAIN_URL"] == "https://k3dm-slack-relay.k3dm.workers.dev/hermes/approvals"
```

**`scripts/tests/hermes/test_approvals.py`.** Add two `_poll` tests, modelled on `_stub_status_poll` in
`test_hermes.py`. Both:

- set `K3DM_HERMES_APPROVAL_DRAIN_URL=https://drain`;
- produce an event with proposals;
- monkeypatch `_keychain_secret`, `post_interactive`, `post_summary` and `fetch_approvals` on the
  `k3dm_hermes` module.

The tests:

1. `_keychain_secret` returns `""` for `k3dm-hermes-approval-drain-token`. Assert that
   `post_interactive` is not called, `post_summary` is called, and `fetch_approvals` is not called.
2. `_keychain_secret` returns a 64-character token. Assert that `post_interactive` is called.

If driving `_poll` to emit proposals needs more than about 30 lines of stubbing, stop and report
rather than refactoring `_poll`.

### File 5 — `docs/guides/hermes.md`

Replace step 4 of "Operator setup" with: the LaunchAgent template sets `K3DM_HERMES_APPROVAL_DRAIN_URL`.
Approvals turn on once the drain token is in the Keychain (step 1). Run `bin/k3dm-hermes-setup` to
re-render the agent after pulling this change.

Update the `K3DM_HERMES_APPROVAL_DRAIN_URL` row of the env-var table. Its default becomes
`https://k3dm-slack-relay.k3dm.workers.dev/hermes/approvals` (template). Its description becomes:
"Relay drain URL. Approvals are active only when Keychain `k3dm-hermes-approval-drain-token` also
exists."

### File 6 — `CHANGELOG.md`

Add one entry under `## [Unreleased]` → `### Fixed`. It says that the LaunchAgent template now carries
the drain URL, so a reinstall no longer turns approvals off, and that the opt-in is now the Keychain
drain token, which also stops buttons appearing that can't do anything.

## Rules

- Modify only Files 1–6. Do not touch `scripts/lib/foundation/` or `~/Library/LaunchAgents`.
- Do not run `bin/k3dm-hermes-setup`, `launchctl`, or real Keychain reads.
- Run and paste:
  - `python3 -m pytest scripts/tests/hermes -q`
  - `plutil -lint` on the template, with the three `{{…}}` placeholders replaced by `dummy` in a
    temp copy
  - `bash -n bin/k3dm-hermes-setup` and `shellcheck bin/k3dm-hermes-setup`
- Mutation (snapshot, then restore and check with `cmp`): remove the two new gate lines from
  `bin/k3dm-hermes` and show test 1 red.
