# Bug: no standalone make trust-vault-ca / webhook cluster-up --trust-vault-ca path and headless LaunchDaemon sudo probes fail when timestamp cache expires

**Status:** OPEN
**Priority:** P2
**Severity:** medium — after Option A (`0b11c1f9`) skips System Keychain trust in headless/SSH `acg-up` runs, operators have no `make trust-vault-ca` (`bin/cluster-up --trust-vault-ca`) or corresponding webhook endpoint support to export and trust the Hub Vault PKI root CA once from the Mac console, and headless `cluster-up`/`cluster-down` runs after the 60-minute sudo timestamp expires fail `sudo -n true` (`a password is required ; COMMAND=/usr/bin/true`) even when `/etc/sudoers.d/k3d-manager` is installed
**Filed:** 2026-11-03
**Detected by:** M5 unified log forensics (`job c38c3855` `COMMAND=/usr/bin/true` alerts) and Option A wider-fix review (`2026-11-03`)
**Branch:** `k3d-manager-v1.43.14`
**Approval:** Operator requested filing wider-fix bug spec (including corresponding webhook endpoint support for the new `cluster-up` flag) and dispatching to Luna on `2026-11-03`
**Related:** `docs/bugs/2026-11-02-acg-up-stalls-at-system-keychain-trust.md`

## Evidence

1. **No standalone `bin/cluster-up --trust-vault-ca` / `make trust-vault-ca` or webhook endpoint support:**
   - Option A (`0b11c1f9`) skips `security add-trusted-cert` in headless/SSH `acg-up` runs because macOS `com.apple.trust-settings.admin` (`SecTrustSettingsSetTrustSettings`) requires an interactive GUI `SecurityAgent` prompt even for `root`.
   - Once the Hub's Vault PKI root CA (`pki/cert/ca`) is trusted once in `/Library/Keychains/System.keychain` from an Aqua GUI session, `security verify-cert -c` returns `0` on every subsequent headless/SSH/Slack `acg-up` run (and across Hub `hub-snapshot` / `hub-data` restores, which preserve the `secrets/data-vault-0` PVC).
   - However, `ca.crt` (`~/.local/share/k3d-manager/acg/argocd-browser-https-tls/ca.crt`) is only written during Step 4c of `acg-up` and is deleted on full teardown (`bin/cluster-down:363`). There is no `bin/cluster-up --trust-vault-ca` (`make trust-vault-ca`) flag or corresponding webhook support (`POST /api/v1/cluster` with `trust_vault_ca: true`, Slack `cluster-up --trust-vault-ca`, and `/k3dm trust-vault-ca`) to fetch `pki/cert/ca` from Hub Vault (`k3d-k3d-cluster`) if missing on disk and trust it in `/Library/Keychains/System.keychain`.
2. **Headless `sudo -n true` probe fails after 60-minute `timestamp_timeout` despite `/etc/sudoers.d/k3d-manager`:**
   - `bin/cluster-up` (`lines 857, 1517, 1765`), `bin/cluster-down` (`lines 217, 326, 351`), and `_run_command --prefer-sudo` probe `sudo -n true`.
   - `bin/install-sudoers.sh` (`_SUDOERS_CONTENT`) grants `NOPASSWD` for `/bin/launchctl bootstrap system /Library/LaunchDaemons/com.k3d-manager.*.plist`, `/bin/launchctl bootout system /Library/LaunchDaemons/com.k3d-manager.*.plist`, `/usr/bin/install`, and `/bin/rm`, but does **not** grant `NOPASSWD: /usr/bin/true`.
   - In the `m5-air.local` unified log for job `c38c3855` (`2026-11-01 20:03:52.637–20:03:52.675 PST`), `sudo -n true` failed 3 times with `a password is required ; COMMAND=/usr/bin/true`. In headless runs after the 60-minute sudo timestamp cache expires, `! sudo -n true` falsely concludes `no sudo in headless context` and skips LaunchDaemon installation in `bin/cluster-up` and LaunchDaemon bootout/cleanup in `bin/cluster-down`.

## Files

- `bin/cluster-up`
- `bin/cluster-down`
- `bin/install-sudoers.sh`
- `Makefile`
- `bin/k3dm-webhook`
- `scripts/lib/webhook/lifecycle.py`
- `scripts/lib/webhook/make_targets.py`
- `scripts/tests/bin/cluster_up.bats`
- `scripts/tests/bin/cluster_down.bats`
- `scripts/tests/bin/install_sudoers.bats`
- `scripts/tests/bin/webhook_lifecycle.py`
- `scripts/tests/bin/webhook_make_targets.py`
- `CHANGELOG.md`

## Fix scope

1. **`bin/install-sudoers.sh`:**
   - Add `%admin  ALL=(root) NOPASSWD: /usr/bin/true` to `_SUDOERS_CONTENT` so non-interactive `sudo -n true` readiness probes in `_run_command --prefer-sudo`, `bin/cluster-up`, and `bin/cluster-down` succeed without password prompts or Unified Log security alerts when `/etc/sudoers.d/k3d-manager` is installed.
2. **`bin/cluster-up`:**
   - Add helper `function _acg_has_launchdaemon_sudo()`:
     - Takes optional plist path `local _plist="${1:-/Library/LaunchDaemons/com.k3d-manager.argocd-browser-https.plist}"`.
     - Returns `0` if `sudo -n true >/dev/null 2>&1 || sudo -n -l /bin/launchctl bootout system "${_plist}" >/dev/null 2>&1`; otherwise returns `1`.
   - Replace the three `! sudo -n true 2>/dev/null && ! [[ -t 0 && -t 1 ]]` guards in `bin/cluster-up` (`_argocd_browser_plist`, `_keycloak_browser_plist`, `_frontend_browser_plist`) with `! _acg_has_launchdaemon_sudo "<respective_plist>" && ! [[ -t 0 && -t 1 ]]`.
   - Add helper `function _acg_export_and_trust_vault_ca()`:
     - Takes `local _ca_cert="${1:-${ARGOCD_BROWSER_TLS_CA_FILE:-${HOME}/.local/share/k3d-manager/acg/argocd-browser-https-tls/ca.crt}}"`.
     - If `[[ "$(uname)" != "Darwin" ]]`, log `_info "[acg-up] System Keychain trust is only supported on macOS — skipping"` and return `0`.
     - If `[[ ! -s "${_ca_cert}" ]]`:
       - Create `mkdir -p "$(dirname "${_ca_cert}")"`.
       - Fetch the CA certificate from Hub Vault via `kubectl exec -n "${VAULT_NS_DEFAULT:-secrets}" "${VAULT_POD_0:-vault-0}" --context "${KUBE_CONTEXT_HUB:-k3d-k3d-cluster}" -- vault read -field=certificate "${VAULT_PKI_PATH:-pki}/cert/ca" > "${_ca_cert}" 2>/dev/null || true`.
       - If `[[ ! -s "${_ca_cert}" ]]`, remove `"${_ca_cert}"` (`rm -f "${_ca_cert}"`) and call `_err "[acg-up] Vault CA cert not found at ${_ca_cert} and could not be read from Hub Vault (${KUBE_CONTEXT_HUB:-k3d-k3d-cluster})"`.
     - If `security verify-cert -c "${_ca_cert}" >/dev/null 2>&1` returns `0`, log `_info "[acg-up] Vault CA cert already trusted in System Keychain — skipping"` and return `0`.
     - If `[[ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ]]` or (`! [[ -t 0 && -t 1 ]]` and `[[ "${K3DM_ALLOW_GUI_SECURITY_AGENT:-0}" != "1" ]]`), call `_err "[acg-up] System Keychain Vault CA trust requires a local macOS GUI session (SecurityAgent prompt) — run 'make trust-vault-ca' from a local terminal on the Mac"` (exiting non-zero).
     - Log `_info "[acg-up] Trusting Vault CA cert in macOS System Keychain (may prompt for sudo password)..."` and run `_run_command --interactive-sudo -- security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "${_ca_cert}"`.
   - In `bin/cluster-up` argument parsing (`for arg in "$@"; do case "$arg" in`), support `--trust-vault-ca`: set `trust_vault_ca_only=1`, and immediately after argument parsing (before Step 0), if `[[ "${trust_vault_ca_only:-0}" -eq 1 ]]`, invoke `_acg_export_and_trust_vault_ca` and `exit $?`.
   - In `_acg_trust_vault_ca` (`bin/cluster-up`), include `make trust-vault-ca` in the headless warning message:
     `_warn "[acg-up] Skipping System Keychain Vault CA trust in headless session (macOS SecurityAgent requires interactive approval) — to trust manually, run 'make trust-vault-ca' or: sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ${_ca_cert}"`
3. **`bin/cluster-down`:**
   - Add helper `function _acg_has_launchdaemon_sudo()` (checking `sudo -n true >/dev/null 2>&1 || sudo -n -l /bin/launchctl bootout system "${1:-/Library/LaunchDaemons/com.k3d-manager.argocd-browser-https.plist}" >/dev/null 2>&1`).
   - Replace the three `! sudo -n true 2>/dev/null && ! [[ -t 0 && -t 1 ]]` guards (`_frontend_browser_plist`, `_keycloak_browser_plist`, `_argocd_browser_plist`) with `! _acg_has_launchdaemon_sudo "<respective_plist>" && ! [[ -t 0 && -t 1 ]]`.
4. **`Makefile`:**
   - Add `trust-vault-ca` to `.PHONY` and add target:
     ```makefile
     ## Export Hub Vault PKI root CA and trust it in macOS System Keychain (local GUI session required)
     trust-vault-ca:
     	./bin/cluster-up --trust-vault-ca
     ```
5. **`bin/k3dm-webhook`, `scripts/lib/webhook/lifecycle.py`, and `scripts/lib/webhook/make_targets.py`:**
   - In `scripts/lib/webhook/make_targets.py`:
     - Add `"trust-vault-ca": {"min_role": "admin", "timeout": 120, "summary": "export Hub Vault PKI root CA and trust it in macOS System Keychain"}` to `MAKE_TARGETS`.
   - In `scripts/lib/webhook/lifecycle.py`:
     - Extend `def _run_cluster(job_id, action, provider="aws", dry_run=False, trust_vault_ca=False):`.
     - When `action == "up"` and `trust_vault_ca` is `True`:
       - Set `cmd = ["./bin/cluster-up", "--trust-vault-ca"]`.
       - Set `_spawn_env["K3DM_ALLOW_GUI_SECURITY_AGENT"] = "1"` so `k3dm-webhook` (which runs in the `gui/$(id -u)` Aqua LaunchAgent domain) can trigger `SecurityAgent` when explicitly requested (while bounded by a 120s timeout: use `timeout = 120` when `trust_vault_ca` is `True`).
       - Skip `_record_acg_state`, `_run_post_provision_check`, and failure `_run_cleanup` when `trust_vault_ca` is `True`.
   - In `bin/k3dm-webhook`:
     - Define `_TRUST_VAULT_CA_TOKENS = {"--trust-vault-ca", "trust-vault-ca"}` and helper `_has_trust_vault_ca_flag(command)` returning `any(p.lower() in _TRUST_VAULT_CA_TOKENS for p in command.strip().split()[1:])`.
     - In `_handle_thread_command` for `cmd in ("cluster-up", "up")`: pass `"trust_vault_ca": _has_trust_vault_ca_flag(command)` in `kwargs` to `_run_cluster`.
     - In `do_POST` (`route["handler"] == "cluster"`): accept `trust_vault_ca = bool(body.get("trust_vault_ca"))` (and also accept `action == "trust-vault-ca"`, normalizing it to `action = "up"` with `trust_vault_ca = True`), and pass `kwargs={"trust_vault_ca": trust_vault_ca}` (when `trust_vault_ca` is `True`, otherwise `kwargs={}` so existing positional-arg tests remain compatible) to `_run_cluster`.
6. **`scripts/tests/bin/cluster_up.bats`, `scripts/tests/bin/cluster_down.bats`, `scripts/tests/bin/install_sudoers.bats`, `scripts/tests/bin/webhook_lifecycle.py`, `scripts/tests/bin/webhook_make_targets.py`:**
   - Keep all existing tests intact and passing.
   - Add isolated tests covering `M1`–`M6` and `N1`–`N2` below.
7. **`CHANGELOG.md`:**
   - Add a bullet under `## [1.43.14] - Unreleased` for `bin/cluster-up --trust-vault-ca` (`make trust-vault-ca` and webhook endpoint/command support), `NOPASSWD: /usr/bin/true` in `bin/install-sudoers.sh`, and `sudo -n -l /bin/launchctl` fallback in headless LaunchDaemon guards.

## Acceptance

```yaml
must:
  - id: M1
    req: when bin/cluster-up --trust-vault-ca is run on Darwin in a local TTY (SSH_CONNECTION and SSH_TTY unset) and ca.crt is missing on disk, _acg_export_and_trust_vault_ca fetches pki/cert/ca from Hub Vault via kubectl exec, verifies it with security verify-cert, and invokes _run_command --interactive-sudo -- security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain <ca_cert>
  - id: M2
    req: make -n trust-vault-ca invokes ./bin/cluster-up --trust-vault-ca, and MAKE_TARGETS["trust-vault-ca"] is registered with min_role "admin" and timeout 120 in scripts/lib/webhook/make_targets.py
  - id: M3
    req: bin/install-sudoers.sh --dry-run includes "%admin  ALL=(root) NOPASSWD: /usr/bin/true" and passes visudo validation
  - id: M4
    req: when sudo -n true returns non-zero (expired timestamp cache) but sudo -n -l /bin/launchctl bootout system <plist> returns 0, headless bin/cluster-down still runs launchctl bootout system <plist> instead of skipping with "no sudo in headless context"
  - id: M5
    req: in scripts/lib/webhook/lifecycle.py, _run_cluster(job_id, "up", "aws", trust_vault_ca=True) spawns ["./bin/cluster-up", "--trust-vault-ca"] with K3DM_ALLOW_GUI_SECURITY_AGENT=1 and does not run _record_acg_state or _run_post_provision_check
  - id: M6
    req: in bin/k3dm-webhook, _has_trust_vault_ca_flag("cluster-up aws --trust-vault-ca") returns True and POST /api/v1/cluster accepts trust_vault_ca=True (or action="trust-vault-ca") and forwards trust_vault_ca=True to _run_cluster
must_not:
  - id: N1
    req: when bin/cluster-up --trust-vault-ca is run in a headless session without K3DM_ALLOW_GUI_SECURITY_AGENT=1 or with SSH_CONNECTION/SSH_TTY set and security verify-cert returns non-zero, _acg_export_and_trust_vault_ca exits non-zero with a message naming "make trust-vault-ca" and never invokes security add-trusted-cert
  - id: N2
    req: when sudo -n true returns non-zero AND sudo -n -l /bin/launchctl bootout system <plist> returns non-zero in a headless session, bin/cluster-down never invokes launchctl bootout system <plist> and emits the "no sudo in headless context" warning
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, M6, N1, N2]
    kind: offline
    intent: >-
      Isolated BATS and pytest suites prove N1 and M4/M5/M6 fail on pre-fix code and M1-M6 + N1-N2 pass on fixed code.
    what: env -i HOME="$HOME" PATH="$PATH" bash -c 'bats scripts/tests/bin/cluster_up.bats scripts/tests/bin/cluster_down.bats scripts/tests/bin/install_sudoers.bats && pytest scripts/tests/bin/webhook_lifecycle.py scripts/tests/bin/webhook_make_targets.py'
```

## Rules

- Touch only the 13 files listed under `## Files`. Do not create or modify any other files, and do not touch `memory-bank/`.
- Do not run `git add`, `git commit`, or `git push`. Leave changes in the working tree.
- Never weaken, skip, or delete any existing test.
- Run and paste the output of:
  - `bats scripts/tests/bin/cluster_up.bats scripts/tests/bin/cluster_down.bats scripts/tests/bin/install_sudoers.bats`
  - `pytest scripts/tests/bin/webhook_lifecycle.py scripts/tests/bin/webhook_make_targets.py`
  - `shellcheck -x -S warning bin/cluster-up bin/cluster-down bin/install-sudoers.sh`
  - `git --no-pager diff --check`
