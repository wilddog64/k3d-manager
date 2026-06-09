# Bug: `bin/k3dm-webhook` can still crash on macOS from remaining fork-based helpers

## Summary

The webhook can still hit a macOS `Python quit unexpectedly` / `EXC_BAD_ACCESS (SIGSEGV)` crash because a few remaining helper paths still use fork-based subprocess calls after the process has imported networking code.

## Observed Output

Crash reports showed macOS killing `Python` with `EXC_BAD_ACCESS (SIGSEGV)` instead of a handled Python exception. The failure presented as the webhook dying while handling Slack-triggered jobs or startup lookups.

## Root Cause

`bin/k3dm-webhook` still had fork-based helpers in the hot path:

- startup keychain lookup for `SLACK_SIGNING_SECRET`
- request token lookup for `/slack/events`
- `kubectl get` / `kubectl patch` helpers used by ArgoCD upgrade handling
- cleanup commands after a failed job
- the `make up` launcher in `_run_upgrade`

On macOS, once the process has loaded networking / NEF state, those fork-based subprocess calls can trigger the same atfork crash class seen in the earlier webhook SIGSEGV issue.

## Fix

Replace the remaining fork-based helpers with `os.posix_spawn`-based command execution and keep job output redirection file-based instead of pipe-based so the webhook no longer forks on these paths.
