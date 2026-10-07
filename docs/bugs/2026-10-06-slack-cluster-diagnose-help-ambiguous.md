# Slack `/cluster-diagnose` help is too dense

## Status

Fixed on `k3d-manager-v1.42.0`.

## Evidence

The prior help was a single grammar-heavy line:

```text
/cluster-diagnose <hostinger|aws|gcp|az|hub> (all pods) | /cluster-diagnose [hostinger|aws|gcp|az|hub] <pods <namespace>|describe-pod <namespace> <pod>|logs <namespace> <pod> [container]|apps|app <name>|appsets>
```

The operator consequently used the more natural
`/cluster-diagnose hub platform-ops pod <pod>` order.

## Fix

Replace the grammar-only line with readable examples for all request families,
explicitly show the default cluster, and make `pod <namespace> <pod>` the primary
single-pod example. Keep the parser's verb-first compatibility form documented by
the existing detailed guide.

## Verification

- Relay test verifies the help includes the pod and application examples.
- Existing relay and Slack-command tests remain green.
