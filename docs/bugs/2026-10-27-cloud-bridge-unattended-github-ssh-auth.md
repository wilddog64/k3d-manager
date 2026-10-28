# Bug: cloud-bridge lacks unattended Keychain-backed GitHub SSH authentication

**Status:** OPEN — controlled gap reproduced; operator-authorized Luna dispatch pending
**Priority:** P2
**Filed:** 2026-10-27
**Branch:** k3d-manager-v1.43.9
**Related:** docs/bugs/2026-10-26-webhook-unresponsive-minimal-diagnosis-recovery.md; docs/bugs/2026-10-26-hermes-launchagent-github-fetch-misses-ssh-agent.md

## Investigation and limits

Operator asked to investigate/dispatch the three open screenshot bugs. During
incident investigation, retained cloud-bridge logs around Oct26 07:20PDT
(13:50–14:50UTC window) contained60 SSH connect-to-github.com port22 errors
with the fixed message Undefined error:0. Webhook structured window records
were14 INFO, not proof of end-to-end availability; unstructured lines were
not interpreted. Existing later bridge responses have HTTP200/202; current
doctor is healthy/all_oktrue with no recovery recommendation. No historical
host outage or exact SSH/network root cause is inferred.

Controlled read-only branch lookup without SSH_AUTH_SOCK:

```json
[
  {"mode":"no_agent","exit":128,"branch_head_present":false,"permission_denied_publickey":true,"ssh_connect_failure":false},
  {"mode":"keychain_no_agent","exit":0,"branch_head_present":true,"permission_denied_publickey":false,"ssh_connect_failure":false}
]
```

Commands differ only in Apple's SSH UseKeychain=yes option, both BatchMode=yes
and ConnectTimeout=8, reading refs/heads/cloud-requests via git ls-remote.
No credentials emitted or changed. This proves an unattended-auth gap; the
original Undefined error:0 was NOT reproduced. Related Hermes fix3aae7adc
already uses the same bounded macOS fallback. Bridge _git currently forwards
its env argument to the subprocess without that fallback. Workaround is an
operator-approved interactive session or explicit stable SSH override; do not
copy a transient SSH_AUTH_SOCK into a plist. A locked Keychain still requires
operator unlock; no policy change or automatic unlock authorized.

## Files

- `bin/k3dm-cloud-bridge`
- `scripts/tests/bin/test_cloud_bridge.py`
- `docs/howto/cloud-session-requests.md`

## Authorized bounded implementation

GPT-6-Luna: on macOS, bridge Git subprocesses should default to Apple
/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=8 -o UseKeychain=yes only when
no explicit GIT_SSH_COMMAND override is supplied. Respect inherited and
caller-provided overrides including explicit empty strings; preserve existing
explicit env semantics, copy rather than mutate caller/os.environ, and do not
lose unrelated env settings. Non-macOS behavior must not gain Apple-only
options. Reuse the established Hermes policy concept without refactoring
Hermes or the shared subprocess library.

Fixtures prove macOS/no-agent fallback, override preservation, env immutability,
non-macOS behavior and Git failure remains observable. Demonstrate new fallback
regression red on old bridge. Run full test_cloud_bridge + test_restart_cloud_bridge
pytest, Ruff (/private/tmp/k3dm-review-tools/bin/ruff --no-cache), Python syntax
and diff check. New/refactored functions <=8ifs; no broad cleanup or dependencies.

Document safe operator restart-cloud-bridge then one benign cloud health
request as separate later live steps, with an unlocked Keychain and sanitized
results. Neither existing history nor a successful current read proves the
original offsite cause resolved. Preserve incident OPEN unless all evidence
supports closure.

Read instructions/memory-bank first. Only Files may change; no spec/memory
edits, stage/commit/push/PR, provider/network/Keychain/SSH/log/live access,
process/service changes, installing credentials or editing SSH/plist config.
Coordinator owns actual staged lint/audit/review/landing and operator live
follow-up. No new plan. [Sanitized investigation](../issues/2026-10-27-three-open-bugs-investigation-and-luna.md).
