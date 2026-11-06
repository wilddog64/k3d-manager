# Bug: the Hostinger refresh never writes the argocd and keycloak browser agents, so `make install-browser-relays` would leave the hub's browser URLs with no backend

**Status:** OPEN — not reproduced live; found by reading the code before the M5 pass
**Priority:** P1
**Severity:** high on the M5 only when its Part B pass runs. `make install-browser-relays` removes the root daemons, and nothing then listens on 18443 or 18080. Today nothing is broken, because the M5 still runs the legacy daemons.
**Approval:** operator, 2026-11-05: "dispatch Part B gap".
**Filed:** 2026-11-06
**Detected by:** Claude (review before the M5 Part B pass)
**Affected:** `scripts/lib/providers/k3s-hostinger.sh`
**Branch:** `k3d-manager-v1.43.14`
**Related:** `docs/bugs/2026-11-05-launchdaemon-d3-part-b-user-listeners.md` (Correction 4; Part B E5 on the M5 waits for this fix)

## Observed failure

Read from the code on 2026-11-06; no live reproduction.

`_hostinger_refresh_access_layer` handles the three browser listeners differently:

| Listener | Wrapper written | Plist written | Restart |
|---|---|---|---|
| `com.k3d-manager.browser.argocd-https` | yes | no | `_hostinger_restart_launchd` |
| `com.k3d-manager.browser.keycloak-http` | no | no | `_hostinger_restart_launchd` |
| `com.k3d-manager.browser.hostinger-frontend-http` | yes | yes | `_hostinger_restart_launchd` |

`_hostinger_restart_launchd` starts with `[[ -f "${plist}" ]] || return 0`, so a missing plist is silently skipped. The only writers of the argocd and keycloak plists are `bin/cluster-up` and `bin/cluster-refresh`, the ACG paths. The M5 runs neither for its hub listeners.

M5 state, captured read-only on 2026-11-05 (`m5-air.local`):

- No `browser.*` agents are loaded, and nothing listens on 18443, 18080, 18082 or 18083.
- `~/.local/share/k3d-manager/bin` has `argocd-browser-https.sh` and `frontend-browser-http.sh`, but no `keycloak-browser-http.sh`.
- There is no `~/.local/share/k3d-manager/k3s-hostinger/` directory. TLS material exists only in `k3s-aws/argocd-browser-https-tls/`.
- The Hostinger wrapper's default cert path is `$(_acg_provider_state_dir k3s-hostinger)/argocd-browser-https-tls/`, so socat would have no cert even with the plist in place.

## Fix

In `_hostinger_refresh_access_layer`, Darwin path only:

1. **TLS.** If the cert or key the wrapper will use is missing or empty, issue it with `_argocd_issue_browser_tls_material <dir>`, the same way `bin/cluster-refresh` section 5 does. Load the plugin first with `_hostinger_load_argocd_plugin`. A failed issue prints a warning naming the listener and does not stop the refresh.
2. **Argocd plist.** Write `browser.argocd-https` in `$HOME/Library/LaunchAgents`, running the existing wrapper.
3. **Keycloak wrapper and plist.** Write `keycloak-browser-http.sh` with `_argocd_write_port_forward_wrapper`, using the arguments from `bin/cluster-refresh` section 5: `istio-system`, `k3d-k3d-cluster`, `svc/istio-ingressgateway`, local 18080, remote 80, health `http://127.0.0.1:18080/health/ready`, kubeconfig `${HOME}/.kube/config`, address 127.0.0.1, name `keycloak-browser-http`. Then write the `browser.keycloak-http` plist.
4. **Plist writer.** Reuse one writer for all three. `_hostinger_write_frontend_browser_plist` has the right shape once its label is a parameter. Do not call `_user_agent_install_if_missing`: it lives in `bin/cluster-refresh` and keeps an existing plist.
5. **Missing plist is an error at these three callers only.** Do not change `_hostinger_restart_launchd` itself, because other callers rely on its silent return for optional agents. A missing browser plist logs an error naming the label; the rest of the refresh still runs, including `_hostinger_restart_cloudflared`, and the refresh then returns non-zero.

Keep the current restart order, with cloudflared between argocd and keycloak.

Not in scope: `bin/cluster-up`, `bin/cluster-refresh`, relays, sudoers, the k3s-aws wrappers.

## Correction 1 (Claude review of Luna's first attempt, 2026-11-06)

- `_err` in lib-foundation runs `exit 1`, and `_vault_login`, `_argocd_issue_browser_tls_material` and the wrapper writers call it. `if ! helper` does not catch an exit, so a Vault failure ends the process before cloudflared restarts. Run those helpers in a subshell at these call sites and treat a non-zero status as the failure. The first attempt's test stub used `return 1`, so it could not see this.
- `_vault_login` reads `vault-root` through `_kubectl` with no `--context`. Both the hub and `ubuntu-hostinger` have that secret (checked on the M5, 2026-11-05). Issuing with the current context set to Hostinger would use the wrong Vault. Check `kubectl config current-context` first and skip issuance with a warning when it is not `k3d-k3d-cluster`. The M5's current context today is `k3d-k3d-cluster`.
- `_hostinger_write_argocd_browser_https_wrapper` is now dead; remove it.
- Four new warnings are tagged `[k3d-hostinger]`; the file's tag is `[k3s-hostinger]`.

## Files

- `scripts/lib/providers/k3s-hostinger.sh`
- `scripts/tests/lib/provider_contract.bats`

## Acceptance

```yaml
must:
  - id: M1
    text: "After a Hostinger access-layer refresh on an empty LaunchAgents directory, each of com.k3d-manager.browser.argocd-https, .keycloak-http and .hostinger-frontend-http has a plist under $HOME/Library/LaunchAgents whose Label is that name and whose program is an existing wrapper file, and each is restarted in the user domain."
  - id: M2
    text: "The keycloak browser wrapper port-forwards svc/istio-ingressgateway in istio-system on context k3d-k3d-cluster, binds 127.0.0.1:18080, targets remote port 80, and its health probe is http://127.0.0.1:18080/health/ready."
  - id: M3
    text: "The argocd browser wrapper binds 127.0.0.1:18443 and its cert and key paths are the ones the refresh checked or issued."
  - id: M4
    text: "When the argocd cert or key is missing or empty, the refresh requests TLS issuance for that directory (paired positive control for N3)."
  - id: M5
    text: "If a browser plist is absent at restart, or TLS issuance or a wrapper write fails, including a helper that exits the process rather than returning (_err calls exit 1), the refresh prints an error or warning naming the listener and cloudflared is still restarted. An absent plist makes the refresh return non-zero."
  - id: M6
    text: "TLS issuance runs only when the current kube context is the hub, k3d-k3d-cluster (paired positive control for N5)."
must_not:
  - id: N1
    text: "The refresh never silently succeeds when a browser plist is absent at restart."
  - id: N2
    text: "No path in the refresh writes under /Library/LaunchDaemons, calls launchctl in the system domain, or invokes sudo for the three browser labels; no generated plist sets UserName or binds a non-loopback address."
  - id: N3
    text: "When cert and key are both present and non-empty, the refresh does not request TLS issuance, and existing material is not rewritten."
  - id: N4
    text: "An optional agent's missing plist passed to _hostinger_restart_launchd directly still returns 0."
  - id: N5
    text: "When the current kube context is not the hub, for example ubuntu-hostinger, which also has a vault-root secret, no TLS issuance is attempted; a warning names the listener and the context."
evidence:
  - {id: E1, proves: [M1, M2, M3, N1, N2], kind: offline, text: "BATS: HOME and LaunchAgents in BATS_TEST_TMPDIR (fixture asserts HOME is not the real home), stubs on PATH for launchctl, kubectl, socat, curl and sudo that log args; plists parsed with plutil or python plistlib; N1 and the M1 plist assertions shown red on the pre-fix commit."}
  - {id: E2, proves: [M4, N3], kind: offline, text: "BATS with the TLS issuer stubbed to log its call: called when material is absent, not called when present, and the material's bytes are unchanged."}
  - {id: E3, proves: [M5, N4], kind: offline, text: "BATS: plist writer forced to fail, or plist removed before restart, then an issuer and a wrapper helper that each call exit 1; cloudflared restart log entry present; rc asserted. Direct _hostinger_restart_launchd call on a missing path returns 0."}
  - {id: E5, proves: [M6, N5], kind: offline, text: "BATS with a kubectl stub answering config current-context: issuer log empty on ubuntu-hostinger, issuer called on k3d-k3d-cluster. N5 and the exit 1 case in E3 shown red on Luna's first attempt."}
  - {id: E4, proves: [M1, M2, M3], kind: live, text: "Operator on the M5, after landing: make install-browser-relays, make install-sudoers, CLUSTER_PROVIDER=k3s-hostinger make refresh-edge; Claude checks launchctl print for the three agents, listeners on the high ports, and the browser URLs. Runs with Part B E5."}
interface:
  - "scripts/lib/providers/k3s-hostinger.sh: _hostinger_refresh_access_layer, _hostinger_restart_launchd"
  - "Stubbable: _argocd_issue_browser_tls_material, _hostinger_restart_cloudflared, launchctl, kubectl, socat, curl, sudo on PATH"
  - "env: HOME, _ACG_STATE_DIR, SCRIPT_DIR, ARGOCD_BROWSER_TLS_CERT_FILE, ARGOCD_BROWSER_TLS_KEY_FILE, CLUSTER_PROVIDER"
```

## Notes for the fixer

- `scripts/tests/lib/provider_contract.bats:839` already drives this function with a scratch `SCRIPT_DIR`. Copy `lib/port_forward_wrapper.sh` and any needed template there, or the helper silently is not present.
- The plugin loader only checks for `register_app_cluster` and `_argocd_hub_kubectl_cmd`. A test that stubs those skips the `source` and must define the wrapper helper itself, so assert the wrapper file exists rather than trusting a zero exit.
- Stubs imitating `launchctl` take real captured output, with host and date in a comment.
