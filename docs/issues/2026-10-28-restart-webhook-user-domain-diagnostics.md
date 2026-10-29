# User LaunchAgent restart: keep errors, remove root advice

Operator actual output:

```text
Bootstrap failed: 5: Input/output error
Try re-running the command as root for richer errors.
[restart-webhook] reloaded LaunchAgent definition
```

Operator explicitly objects to root guidance. The root line is emitted by
launchctl, not a request from coordinator. Existing recipe retries up to5times;
the final success line is consistent with successful retry. The exact first
bootstrap failure cause was not captured beyond the OS message; do not claim
an established launchd race root cause.

Independent read-only process/filtered launchd state after operator restart:

```text
43179 1 Wed Oct 28 19:22:14 2026 /opt/homebrew/Cellar/python@3.15/3.15.1/Frameworks/Python.framework/Versions/3.15/Resources/Python.app/Contents/MacOS/Python /Users/cliang/src/gitrepo/personal/k3d-manager/bin/k3dm-webhook
43185 1 Wed Oct 28 19:22:14 2026 /opt/homebrew/Cellar/python@3.15/3.15.1/Frameworks/Python.framework/Versions/3.15/Resources/Python.app/Contents/MacOS/Python /Users/cliang/src/gitrepo/personal/k3d-manager/bin/k3dm-cloud-bridge
com.k3d-manager.webhook exit= 0
state = running
runs = 1
pid = 43179
last exit code = (never exited)
com.k3d-manager.cloud-bridge exit= 0
state = running
runs = 90
pid = 43185
last terminating signal = Terminated: 15
```

Both new PIDs started together. Bridge's retained termination signal is not
proof the current process failed; currentstate is running. No root escalation,
coordinator restart, environment dump, credential lookup or service change.

## Targeted recipe fix

Capture bootstrap output and filter only the exact line
`Try re-running the command as root for richer errors.` on failed attempts.
Keep real bootstrap errors and all retry/success/final-failure behavior.
The launchctl invocation stays gui/currentuser; no plist or interpreter change.
Fake launchctl now reproduces the exact two OS diagnostic lines. New BATS
requires original error, absent root hint, retry success and exactly2attempts;
exhaustion case also preserves error/no-root and forbids bridge restart.

Regression on original Makefile, actual full output:

```text
1..1
not ok 1 restart-webhook preserves bootstrap errors without suggesting root for a user agent
# (in test file scripts/tests/bin/restart_webhook.bats, line 84)
#   `[[ "${stderr}" != *'Try re-running the command as root'* ]]' failed
```

Final full focused BATS output under unchanged tripwire:

```text
1..6
ok 1 restart-webhook reloads the plist with bootout then bootstrap, never kickstarting the webhook
ok 2 restart-webhook continues to bootstrap when bootout reports the job is not loaded
ok 3 restart-webhook still restarts the cloud bridge
ok 4 restart-webhook retries bootstrap twice then reports success
ok 5 restart-webhook preserves bootstrap errors without suggesting root for a user agent
ok 6 restart-webhook fails after five bootstrap attempts and skips cloud bridge
```

`ShellCheck scripts/tests/bin/restart_webhook.bats` (lowercase command
`shellcheck`) exited0 with no output; gitdiffcheck clean. All launchctl calls
were fakes; no real restart during tests. Existing5tests preserved, count+1.
No reason to reload live webhook again solely for this Make output change.
Required stagedlint/audit/checkpointhooks before commit. No PR/newplan.

## Separate live count result after successful reload

Operator next ask-docs reply reports a tally timeout. This confirms the current
count route was selected; it does not mean the count succeeded. It is tracked
in the [ask-docs live failure investigation](2026-10-28-ask-docs-live-count-and-thread-failure.md),
not hidden by the launcher output fix or treated as an excuse to use root.
