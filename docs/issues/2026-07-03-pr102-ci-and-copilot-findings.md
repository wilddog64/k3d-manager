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

## 5. Copilot — `scripts/plugins/vault.sh:210` Vault token in `kubectl exec` argv (DEFERRED — follow-up)

**Finding:** `_vault_exec` passes the session token via
`kubectl exec ... -- env "VAULT_TOKEN=..." sh -lc "$cmd"`. The token is out of
the logged command string but still visible in process argv (`ps`,
`/proc/*/cmdline`).

**Why deferred, not fixed in this PR:**
- This is **pre-existing behavior on `main`** (same `env VAULT_TOKEN=` argv
  pattern appears in three places in `main`'s `_vault_exec`).
- The v1.12.0 commit `300009487` ("stop inlining vault tokens in refresh auth
  commands") actually **improved** hygiene here — it removed the token from the
  logged `sh -lc` command string.
- Fully removing argv exposure (pass the token via stdin or a file inside the
  pod) is a change to a core exec helper shared with `main` and warrants its own
  spec, test coverage, and live verification rather than being folded into a
  165-commit release PR.

**Follow-up:** Track a dedicated v1.13.0 bugfix to pass `VAULT_TOKEN` to
`kubectl exec` via stdin/file instead of argv, across all `_vault_exec` paths.
