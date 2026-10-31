# Platform-ops system-notice Slack webhook

`deploy_argocd_platform_ops` stores the system-notice Slack webhook in the
`platform-ops/platform-ops-notifications` Secret. The deployment reads its
durable source from the hub Mac's login Keychain and warns when the record is
missing or the Secret has no nonempty webhook value.

## Seed the Keychain record

Run this once on the hub Mac. `security` prompts for the webhook URL at the
terminal, so it does not enter shell history or command arguments:

```bash
security add-generic-password -U -s k3dm-platform-ops-slack-url -a k3dm -w
```

Then sync it into the cluster:

```bash
make platform-ops
```

Confirm that `kubectl -n platform-ops describe secret platform-ops-notifications`
lists `slack-incoming-webhook-url` with a nonzero size. The URL is never printed
by the deployment. The Keychain record is included in the hub machine-secrets
manifest so it can be copied during a hub rebuild.
