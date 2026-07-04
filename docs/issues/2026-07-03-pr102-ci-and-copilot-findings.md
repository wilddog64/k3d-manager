# PR #102 (v1.12.0) — CI + Copilot/CodeQL review findings

**Date:** 2026-07-03
**PR:** [#102](https://github.com/wilddog64/k3d-manager/pull/102) — v1.12.0 release
**Branch:** `k3d-manager-v1.12.0`

The first CI run on PR #102 failed the `lint` job and Copilot/CodeQL raised
review comments. This records each finding, the fix (or deferral), and the
process note.

---

## 1. CI lint failure — observability tests not OS-portable (FIXED)

**Symptom:** `lint` job failed on `not ok 128/129/130` in
`scripts/tests/lib/observability.bats`:

```
128 deploy_observability calls envsubst ... -> "com.k3d-manager.alertmanager-port-forward" not in output
129 deploy_observability_acg ...           -> "Alertmanager port-forward agent installed" not in output
130 deploy_observability_acg falls back ... -> "Alertmanager port-forward agent installed" not in output
```

These passed locally on macOS but failed on the Linux CI runner.

**Root cause:** `_observability_install_alertmanager_port_forward()` (and the
auth-proxy installer) early-return on non-macOS (`if ! _is_mac; then return 0`).
The launchd LaunchAgent path is macOS-only by design. Tests 128–130 relied on
the real `_is_mac`, so on Linux the install path was skipped and the asserted
output never appeared. Test 129 also relied on the real macOS `launchctl`
binary.

**Fix:** Force `_is_mac() { return 0; }` (and stub `launchctl`) in those three
tests — mirroring the already-passing "restores alertmanager access layer"
test. The production `_is_mac` guard is intentional and unchanged.

**Process note:** Tests that assert output from a macOS/launchd-guarded code
path MUST stub `_is_mac` so they are deterministic on the Linux CI runner.

---

## 2. CodeQL — HTTP Response Splitting in `bin/alertmanager-auth-proxy:113` (FIXED)

**Finding:** The auth proxy forwarded backend response header names/values
verbatim via `self.send_header(key, value)`. CodeQL flags this as HTTP Response
Splitting because a header could carry CR/LF.

**Fix:** Strip `\r` and `\n` from both the forwarded header name and value
before re-emitting them:

```python
safe_key = key.replace("\r", "").replace("\n", "")
safe_value = value.replace("\r", "").replace("\n", "")
self.send_header(safe_key, safe_value)
```

---

## 3. Copilot — `scripts/etc/observability/promtail.yaml` used `fluent-bit:latest` (FIXED)

**Finding:** The promtail DaemonSet pinned `fluent/fluent-bit:latest`, which is
non-reproducible and violates the repo supply-chain rule (container images must
use a pinned tag, not `latest`). This image reference is net-new in v1.12.0.

**Fix:** Pinned to `fluent/fluent-bit:3.1.9`.

**Note:** Confirm `3.1.9` matches the intended Fluent Bit line for this
observability stack; bump the pin if a different release is preferred.

---

## 4. Copilot — `scripts/plugins/acg.sh` `acg_watch_start` ignored underlying exit code (FIXED)

**Finding:** `acg_watch_start` ran the underlying start, then unconditionally
retargeted logs and returned success, masking a failed start.

**Fix:** Capture the underlying exit code and return early on failure before
retargeting logs.

---

## 5. Copilot — `scripts/plugins/vault.sh:210` Vault token in `kubectl exec` argv (RESOLVED in v1.13.0)

**Finding:** `_vault_exec` previously injected the session token into the
`kubectl exec` argument vector before `sh -lc "$cmd"` ran. The token was out of
the logged command string but still visible in process argv (`ps`,
`/proc/*/cmdline`).

**Resolution:** Fixed on `k3d-manager-v1.13.0` in commit `fded6575`
(`fix(vault): deliver VAULT_TOKEN via stdin, never process argv`).

**What changed:**
- `_vault_exec` now sends the cached/session token as the first stdin line and
  loads it inside the pod before `sh -lc` execs the real Vault command.
- `_vault_exec_stream` now supports `--stdin` so policy writes and other piped
  payloads receive the token first and the original payload second.
- `_vault_login` now caches the token before verification so the standard
  stdin-delivery path is exercised there too, and unsets the cache on failure.
- `__vault_exec_kubectl` now supports `--exec-stdin` to buffer/replay stdin
  across the existing "container not found" retry loop.

**Validation:** `shellcheck -S warning scripts/plugins/vault.sh`, `bats
scripts/tests/plugins/vault.bats scripts/tests/plugins/vault_app_auth.bats
scripts/tests/plugins/vault_app_auth_enable_idempotent.bats
scripts/tests/plugins/vault_token_stdin.bats scripts/tests/plugins/vault_failover.bats
scripts/tests/plugins/vault_seed_hub.bats`, and `./scripts/k3d-manager
_agent_audit` all passed on the fix branch before push.

---

## 6. GitGuardian check — 1 secret uncovered (RESOLVED — false positive)

**Finding:** The server-side GitGuardian GitHub App check failed with
"1 secret uncovered": a `generic_password` in
`scripts/tests/plugins/shopping_cart_seed_idempotent.bats` (incident
`34353947`, GitGuardian auto-tag `TEST_FILE`).

**Root cause:** Dev-only test fixture. The repo `.gitguardian.yaml`
(`ignored_paths: scripts/tests/`, plus an explicit SHA `ignored_matches`
entry added via `ggshield secret ignore`) keeps the **ggshield CLI** clean, but
the GitGuardian **GitHub App** does not read the repo config — it uses the
workspace/dashboard state.

**Resolution:** Incident `34353947` marked **IGNORED** with reason
`test_credential` via the GitGuardian API (`POST /v1/incidents/secrets/34353947/ignore`),
using the `incidents:write`-scoped ggshield token. Only this one incident was
touched.

**Process note:** GitGuardian is **not a required status check** on `main`, so
this never blocked the merge. In-repo `.gitguardian.yaml` ignores cover the CLI
only; server-side check state must be resolved on the dashboard/API.
