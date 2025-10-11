# System Dependency Helper Audit

## Goal
Ensure every external CLI used by `k3d-manager` has a corresponding `_ensure_*` helper so the tooling can install or warn about missing prerequisites automatically across supported operating systems.

## Plan
1. **Inventory dependencies**
   - Review `scripts/lib/system.sh` (and other libraries/plugins where needed) to list all external commands (`helm`, `kubectl`, `k3d`, `lpass`, `envsubst`, `jq`, etc.).
   - Note which already have `_ensure_*` helpers and identify gaps.
2. **Design install strategy**
   - For missing helpers, define per-OS installation commands (Homebrew, apt, dnf/yum, etc.) consistent with existing style.
   - Decide on graceful failure messages when no supported package manager is available.
   - Capture edge cases (e.g., WSL without sudo, air-gapped setups) so the helper can advise manual installation paths.
3. **Implement helper coverage**
   - Add new `_ensure_*` functions (or extend existing ones) in `scripts/lib/system.sh`.
   - Update call sites to invoke the helpers before they rely on each tool.
   - Confirm changes respect tracing safeguards (no secret leaks).
4. **Add/update tests**
   - Expand BATS/unit tests to cover the new helper logic, stubbing package-manager commands so tests remain offline.
5. **Document usage**
   - Summarize the new installation behaviour in relevant docs (README, operations notes) if prerequisites or flags change.
   - Record follow-up tasks, if any, after implementation and testing.

## Status
- Item 1: completed
- Item 2: pending
- Item 3: pending
- Item 4: pending
- Item 5: pending

### Dependency inventory (WIP)

| Tool | Primary caller(s) | Existing helper | Notes |
| ---- | ----------------- | --------------- | ----- |
| `kubectl` | `_kubectl`, cluster helpers | ✅ `_install_kubernetes_cli` invoked automatically | Handles macOS, Debian, RedHat, WSL |
| `helm` | `_helm`, Jenkins/Vault deployers | ✅ `_ensure_helm` | Automates install before invoking Helm |
| `istioctl` | `_istioctl`, Istio workflows | ✅ `_ensure_istioctl` | Installs via existing helper before use |
| `curl` | `_curl`, install helpers | ⚠️ none | Consider bootstrap via package manager or clearer guidance |
| `lpass` | `_sync_lastpass_ad` | ⚠️ none | At least detect and suggest install command by platform |
| `secret-tool` | `_secret_tool` | ✅ `_ensure_secret_tool` | Uses distro package managers |
| `jq` | `_sync_lastpass_ad`, templating | ✅ `_ensure_jq` | Already covers common distros |
| `envsubst` | rendering templates | ✅ `_ensure_envsubst` | |
| `bats` | test harness (`_ensure_bats`) | ✅ | Ensures minimum version |
| `cargo` | developer tooling (`_ensure_cargo`) | ✅ | |
| `docker`/`colima` | install helpers | ⚠️ manual invocation only | Evaluate whether to auto-install or keep on-demand |
| `k3d` | provider abstraction | ⚠️ relies on user install | Need to decide on ensure strategy |

### Install strategy (draft)

| Tool | macOS | Debian/Ubuntu | RHEL/CentOS/Fedora | WSL notes | Failure guidance |
| ---- | ----- | ------------- | ------------------ | --------- | ---------------- |
| `helm` | `brew install helm` (reuse `_install_mac_helm`) | Reuse `_install_debian_helm` (apt repo) | Reuse `_install_redhat_helm` (`dnf`/`yum`) | Delegate to distro branch | If package manager unavailable, instruct manual download from https://helm.sh |
| `istioctl` | Call `_install_istioctl "$HOME/.local/bin"` for non-root install | `_install_istioctl` already handles sudo fallback | Same as Debian (existing script) | On WSL reuse linux path; warn if sudo missing | Warn to download from Istio releases and place in PATH |
| `curl` | `brew install curl` when missing (rare); warn about macOS system curl for TLS issues | `apt-get install -y curl` | `dnf install -y curl` (fall back to `yum`) | Same as Linux branch; if `apt-get` absent, warn | If install fails, advise manual download and bail early (since many workflows require curl) |
| `lpass` | `brew install lastpass-cli` | `apt-get install -y lastpass-cli` (available in Debian repos) | Prefer `dnf install -y lastpass-cli` (EPEL) with fallback message if not found | On WSL follow distro packages; if missing, instruct manual compilation | If CLI not available, abort with actionable message pointing to https://github.com/lastpass/lastpass-cli |
| `docker` | Keep existing `_install_mac_docker` (Colima) but invoke via `_ensure_docker` that can skip in CI | `_install_debian_docker` (apt repo) | `_install_redhat_docker` (dnf) | For WSL, advise using Docker Desktop on host; if attempting install, guard against systemd absent | When install unsupported, warn and leave to user with link |
| `colima` | `brew install colima` (already) | n/a | n/a | n/a | If macOS without Homebrew, warn about manual setup |
| `k3d` | Provide `_ensure_k3d`: download via official install script (`INSTALL_DIR=/usr/local/bin` under sudo). On mac with Homebrew, prefer `brew install k3d` if available. | For Debian/RedHat, run upstream install script (uses curl); require curl -> ensures before. | Same | On WSL, allow same script but caution about docker daemon | Warn if install script unavailable (curl missing, no sudo). |
| `vault`, `kubectl` et al. | Already covered (`_install_kubernetes_cli`, Vault installed via helm) | — | — | — | — |

Additional considerations:
- Ensure new helpers honour `ENABLE_TRACE` secrecy requirements (no secret leakage from package installs).
- When auto-install would need root/sudo and not available, helper should emit a single warning and return failure rather than exiting whole script, so caller can prompt the user.
