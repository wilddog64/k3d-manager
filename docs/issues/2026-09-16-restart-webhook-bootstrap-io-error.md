# `make restart-webhook` failed with LaunchAgent bootstrap I/O error

## Symptom

```text
Bootstrap failed: 5: Input/output error
make: *** [restart-webhook] Error 5
```

## Root cause

The target always performed `bootout` followed immediately by `bootstrap`. When the existing LaunchAgent was still loaded or launchd had not finished removing its service registration, the second operation could fail with error 5 even though the webhook process remained healthy.

## Fix

`restart-webhook` now uses `launchctl kickstart -k` for a loaded service. This asks launchd to terminate and relaunch the existing job without tearing down its registration. If the service is not loaded, the target falls back to the previous bootout/bootstrap path.

## Verification

The live target was run successfully and the service returned to `state = running` with a new process ID. The plist remained valid and the webhook log continued to show successful initialization/listening.
