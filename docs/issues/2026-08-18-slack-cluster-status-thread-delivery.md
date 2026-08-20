# Slack cluster-status detail and thread delivery

## Symptoms

- `/cluster-status` posted only a one-line count summary instead of the per-service checks shown by
  `make status`.
- A reply in the status thread was accepted by the webhook but produced no visible agent response.

## Findings

The status formatter intentionally emitted only the overall state plus failed/warning checks. It
did not include healthy checks, unlike `make status`.

The owner event was eventually accepted after the role map was provisioned:

```text
[slack/events] type='message' thread_ts='1787099182.579369' ... user='U4C9LDQP2' role='admin'
[slack/events] thread reply — thread_ts='1787099182.579369' job_id=None cmd='codex'
[slack/events] orphan thread — anchor_id='570b70a8' cmd='codex'
```

The job completed successfully, but the configured bot could not post because it was not a member
of the private `#acg-automation` channel:

```text
chat.postMessage ok= False error= channel_not_found
```

After inviting bot user `U0B78FPN8B1` to channel `C0B7ZHG2LR4`, the same thread post succeeded:

```text
chat.postMessage ok= True error= <none>
```

## Fix

`_run_hostinger_status` now passes every per-service check to the Slack formatter, which renders
the same healthy/warning/error lines as `make status`. The bot was invited to the private channel;
future thread replies can now use `chat.postMessage` with the configured channel and thread.
