# Slack `/cluster-diagnose` rejects namespace-first pod syntax

## Status

Fixed on `k3d-manager-v1.42.0`.

## Evidence

Slack showed:

```text
/cluster-diagnose hub platform-ops pod acg-expiry-check-29855580-ssvb
k3d-manager APP Unsupported diagnostic. Use pods, describe-pod, logs, apps, app, or appsets.
```

## Root cause

The relay parser only accepted the documented verb-first form
`describe-pod <namespace> <pod>`. It did not recognize the common namespace-first
form `<namespace> pod <pod>`, nor the singular `pod` shorthand.

## Fix

Accept namespace-first `pod` as an alias for `describe-pod`, while preserving the
existing verb-first grammar and action allowlist. Document the shorthand and add a
relay regression test for the exact reported command.

## Acceptance

- The reported command dispatches `describe-pod` for provider `hub`, namespace
  `platform-ops`, and the requested pod name.
- Existing `pods`, `describe-pod`, `logs`, `apps`, `app`, and `appsets` forms remain
  unchanged.
- Unsupported diagnostic text remains rejected.
