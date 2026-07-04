# Issue: `/cluster-status` could fail silently because the webhook passed `provider=` into `_run_hostinger_status()`

**Date:** 2026-07-02  
**Branch:** `k3d-manager-v1.12.0`  
**Area:** `bin/k3dm-webhook`, `workers/slack-relay/index.js`

## Symptom

Issuing `/cluster-status` in Slack did not produce a visible response.

## Investigation

The local webhook log showed the real failure:

```text
Exception in thread Thread-144 (_run_hostinger_status):
Traceback (most recent call last):
  File "/opt/homebrew/Cellar/python@3.13/3.13.14/Frameworks/Python.framework/Versions/3.13/lib/python3.13/threading.py", line 1044, in _bootstrap_inner
    self.run()
  File "/opt/homebrew/Cellar/python@3.13/3.13.14/Frameworks/Python.framework/Versions/3.13/lib/python3.13/threading.py", line 995, in run
    self._target(*self._args, **self._kwargs)
TypeError: _run_hostinger_status() got an unexpected keyword argument 'provider'
```

The `/api/v1/cluster-status` handler dispatched `provider` to both status paths,
but `_run_hostinger_status()` did not accept that keyword argument.

## Root Cause

The hostinger status path had a signature mismatch. The Slack relay correctly
sent the provider field, but the webhook background thread crashed before it
could post the status back to Slack.

## Fix

`_run_hostinger_status()` now accepts the optional `provider` keyword argument
so the shared `/api/v1/cluster-status` dispatcher can call either path without
raising.

`scripts/tests/lib/webhook.bats` now guards the signature and dispatch wiring.
