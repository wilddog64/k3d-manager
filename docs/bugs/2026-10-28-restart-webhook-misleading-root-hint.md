# Bug: user LaunchAgent restart prints misleading root advice

**Status:** VERIFIED — targeted output filter and stubbed retry/error tests pass; no new live restart required
**Priority:** P3
**Filed:** 2026-10-28
**Branch:** `k3d-manager-v1.43.9`
**Approval:** operator explicitly said the user LaunchAgent restart should not ask to use root

Operator's restart printed a transient bootstrap error and launchctl's generic
root suggestion before reporting successful retry. This target operates in
the current user gui domain; repeating it as root is inappropriate guidance.
The actual launchctl error must remain visible. Scope: Makefile restart-webhook
recipe and existing restart_webhook.bats, verification documentation only.

Capture bootstrap output and remove exactly the generic root-advice line from
failed attempts. Preserve every other diagnostic, successful output, current
gui user domain, five-attempt cap, final failure and success behavior, and
bridge restart only after webhook bootstrap success. No sudo or root domain,
plist/interpreter/credential/service changes. Tests use fake launchctl/sleep/
HOME, never the actual services. New regression is red on original recipe;
all6BATS and rawShellCheck pass after the filter.

[Actual user output, red/green and runtime-state evidence](../issues/2026-10-28-restart-webhook-user-domain-diagnostics.md).
