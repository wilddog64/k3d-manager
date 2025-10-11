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
| `helm` | `_helm`, Jenkins/Vault deployers | ⚠️ install routines exist (`_install_helm`) but no `_ensure_helm` wrapper | Needs automatic install before use |
| `istioctl` | `_istioctl`, Istio workflows | ⚠️ none (fails with message) | Should mirror `_kubectl` pattern |
| `curl` | `_curl`, install helpers | ⚠️ none | Consider bootstrap via package manager or clearer guidance |
| `lpass` | `_sync_lastpass_ad` | ⚠️ none | At least detect and suggest install command by platform |
| `secret-tool` | `_secret_tool` | ✅ `_ensure_secret_tool` | Uses distro package managers |
| `jq` | `_sync_lastpass_ad`, templating | ✅ `_ensure_jq` | Already covers common distros |
| `envsubst` | rendering templates | ✅ `_ensure_envsubst` | |
| `bats` | test harness (`_ensure_bats`) | ✅ | Ensures minimum version |
| `cargo` | developer tooling (`_ensure_cargo`) | ✅ | |
| `docker`/`colima` | install helpers | ⚠️ manual invocation only | Evaluate whether to auto-install or keep on-demand |
| `k3d` | provider abstraction | ⚠️ relies on user install | Need to decide on ensure strategy |
