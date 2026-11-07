# Platform-ops system-notice Slack webhook

There are two independent Slack webhook values to replace when rotating the
webhook:

| Consumer | Source that must be replaced | Synced destination |
| --- | --- | --- |
| Hermes summaries, pages, and E2E results | Hub Mac login Keychain item `k3dm-slack-webhook` (account `k3dm`) | None; Hermes reads this item directly |
| Platform-ops system notices | Hub Mac login Keychain item `k3dm-platform-ops-slack-url` (account `k3dm`) | Secret `platform-ops/platform-ops-notifications`, key `slack-incoming-webhook-url` |

Updating one item does not update the other. The deployment reads its durable
source from the hub Mac's login Keychain and warns when the record is missing or
the Secret has no nonempty webhook value.

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

## Replace and verify both values

After Slack issues a replacement URL, update both Keychain items at the hub Mac
in Terminal. Each command prompts for the value without putting it in shell
history or process arguments:

```bash
security add-generic-password -U -s k3dm-slack-webhook -a k3dm -w
security add-generic-password -U -s k3dm-platform-ops-slack-url -a k3dm -w
```

Test delivery using Hermes' Keychain item:

```bash
printf 'Webhook replacement test\n' | bin/k3dm-slack-notify
```

Exit 0 means Slack accepted the post; confirm that the message arrives in
Slack. A refusal exits 1 and logs the HTTP status and Slack's reply to stderr.

Sync the platform-ops item and compare the Secret with the Keychain item using
SHA-256 digests. The comparison strips the trailing newline added by
`security -w`:

```bash
make platform-ops
python3 - <<'PY'
import base64
import hashlib
import hmac
import subprocess
import sys

keychain = subprocess.check_output([
    "security", "find-generic-password", "-s", "k3dm-platform-ops-slack-url",
    "-a", "k3dm", "-w",
]).removesuffix(b"\n")
secret = base64.b64decode(subprocess.check_output([
    "kubectl", "-n", "platform-ops", "get", "secret", "platform-ops-notifications",
    "-o", "jsonpath={.data.slack-incoming-webhook-url}",
]), validate=True)
if not keychain or not secret or not hmac.compare_digest(
        hashlib.sha256(keychain).digest(), hashlib.sha256(secret).digest()):
    sys.exit("Keychain item and Secret are empty or do not match")
print("Keychain item and Secret match")
PY
```

The first check proves delivery. The second proves the Secret holds the same
value as the platform-ops Keychain item; it does not prove Slack accepts that
value. Neither check prints the webhook URL.
