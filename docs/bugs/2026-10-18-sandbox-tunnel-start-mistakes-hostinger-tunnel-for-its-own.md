# Bug: a sandbox `make up` mistakes Hostinger's SSH tunnel for its own, so the sandbox never gets a Vault reverse tunnel

**Filed:** 2026-10-18 (Claude, from the operator's `make up CLUSTER_PROVIDER=k3s-aws` at 18:30 PDT 2026-10-17)
**Status:** FIXED — 2026-10-18: `17c7cda5` (Codex, landed in scope; 199 BATS green; 7 new tests red on pre-fix) + `152f7978` (Claude: `bin/cluster-status` and `bin/k3dm-webhook` tunnel probes moved to the sandbox port, from the Step 0 grep). Independent verifier (Sonnet, Acceptance-only, offline evidence) PASSED: tunnel 16/16 + frontend 7/7 on 7791b17f; every red-on-pre-fix must_not red on ccf5dbfc (re-run by Claude). Awaiting live E2/E3.
**Fix commit:** 17c7cda5, 152f7978
**Priority:** P1 — a sandbox `make up` fails whenever the Hostinger tunnel is up, and the only workaround in `docs/issues/2026-07-07-two-cluster-vault-bridge-css-not-ready-k3s-aws.md` (one remote cluster at a time) means taking down the public Hostinger site
**Severity:** high
**Approval:** approved — operator, 2026-10-18: "1. go ahead 2. yes" (write the dispatch spec and send it to Codex, with the P3 `2026-10-18-keep-hub-down-leaves-sandbox-frontend-agents.md` in the same run as Part B)
**Release:** v1.43.4 (bug; exempt from the plan cap)
**Component:** `scripts/plugins/tunnel.sh` (`_tunnel_is_running`, `tunnel_start`, launchd labels), `scripts/lib/providers/k3s-aws.sh`, `scripts/lib/providers/k3s-hostinger.sh` (`TUNNEL_SSH_HOST` override at line 940), `bin/cluster-down`, `bin/cluster-refresh`
**Related:** `docs/issues/2026-07-07-two-cluster-vault-bridge-css-not-ready-k3s-aws.md` (same symptom, RCA never fixed); `docs/bugs/2026-10-05-sandbox-make-up-hijacks-hostinger-launchd-labels.md` (moved the other shared labels to `sandbox.*`, but not the SSH tunnel)

## Symptom

`make up CLUSTER_PROVIDER=k3s-aws` fails at Step 8/12:

    INFO: [shopping_cart] Waiting for ClusterSecretStore vault-backend to be Ready on ubuntu-k3s...
    WARN: [shopping_cart] ClusterSecretStore vault-backend not Ready after 90s (attempt 1/3) — forcing reconcile...
    ...
    ERROR: [shopping_cart] ClusterSecretStore vault-backend never became Ready after 3 attempts (270s total)

Before it, at Step 3/12, the tunnel step does nothing:

    INFO: [acg-up] Step 3/12 — Starting SSH tunnel...
    [tunnel] already running

## Root cause

The sandbox and Hostinger share one pair of tunnel launchd labels: `com.k3d-manager.ssh-tunnel`
(forward `:6443`) and `com.k3d-manager.ssh-tunnel-vault` (reverse `-R 8200:127.0.0.1:18200`).
`k3s-hostinger.sh:940` sets `TUNNEL_SSH_HOST=ubuntu@<hostinger-host>` and calls `tunnel_start`,
which writes both plists for Hostinger. On 2026-10-17 at 17:54 they pointed at
`ubuntu@srv1754834.hstgr.cloud`.

The sandbox calls `tunnel_start` with `TUNNEL_SSH_HOST=ubuntu` (the `~/.ssh/config` alias for the
sandbox server). `tunnel_start` returns early when three checks pass:

- `_tunnel_is_running` runs `pgrep -f "autossh.*ubuntu"`, a substring match. Hostinger's
  `autossh ... -N ubuntu@srv1754834.hstgr.cloud` matches it.
- `_tunnel_plist_has_reverse` is false, because the main plist has no `-R`.
- `_tunnel_vault_launchd_loaded` is true, because Hostinger's reverse agent is loaded.

So the sandbox gets no reverse tunnel. `vault-bridge` on the sandbox server (socat `:8201` →
`localhost:8200`) forwards to a port that nothing listens on, and ESO's `vault-backend` store
cannot reach Vault.

Fixing only the match would not help. With an exact host match, `tunnel_start` would rewrite the
shared plists to `ubuntu`. That takes Hostinger's Vault reverse tunnel away, so Hostinger's ESO
loses Vault, and `make down` (`tunnel_stop`) would later unload Hostinger's agents. The labels
have to be separate.

Confirmed from the code and the launchd state after the run; not reproduced. An earlier sandbox
`make up` on 2026-10-17 succeeded. That was probably because the sandbox wrote the shared plists
after Hostinger's last refresh, which would have taken Hostinger's tunnel at the time. This is not
verified; no log from that run was checked.

## Fix (direction; the dispatch spec gives exact code)

- When the sandbox runs `tunnel_start`/`tunnel_stop` (k3s-aws up, down and refresh), it uses its own
  labels and paths: `com.k3d-manager.sandbox.ssh-tunnel` and
  `com.k3d-manager.sandbox.ssh-tunnel-vault`, set through the existing `TUNNEL_LAUNCHD_LABEL`,
  `TUNNEL_PLIST_PATH`, `TUNNEL_VAULT_LAUNCHD_LABEL`, `TUNNEL_VAULT_PLIST_PATH` and
  `TUNNEL_VAULT_WRAPPER_PATH`. Hostinger keeps the unscoped labels.
- `_tunnel_is_running` matches the ssh destination exactly, as a whole argument, not as a substring.
- A sandbox teardown unloads only the `sandbox.*` tunnel agents.
- The sandbox forward tunnel binds `0.0.0.0:16443`, not Hostinger's `0.0.0.0:6443`. Settled while
  writing the spec: the hub's ArgoCD reaches the sandbox through this forward
  (`ARGOCD_APP_CLUSTER_SERVER` default `https://host.k3d.internal:6443`), and so does the
  `add_ubuntu_k3s_cluster` kubeconfig fallback (`127.0.0.1:6443`). Whichever cluster owned `:6443`
  answered both. Hostinger registers with ArgoCD by its public IP, so it keeps `:6443`.
- A sandbox `tunnel_stop` today also kills Hostinger's Vault tunnel: its `pkill` pattern
  `ssh -N .*-R 8200:127.0.0.1:18200` matches any host. Both `pgrep`/`pkill` patterns must end in
  the exact destination.

## Acceptance

```yaml
must:
  - id: M1
    text: With Hostinger's tunnel agents loaded and pointing at ubuntu@<hostinger-host>, a k3s-aws tunnel_start installs and loads com.k3d-manager.sandbox.ssh-tunnel and com.k3d-manager.sandbox.ssh-tunnel-vault, whose ssh destination is the sandbox alias (ubuntu) and whose reverse forward is -R 8200:127.0.0.1:18200.
  - id: M2
    text: _tunnel_is_running is true only for an autossh whose destination argument equals TUNNEL_SSH_HOST; ubuntu does not match ubuntu@srv1754834.hstgr.cloud.
  - id: M3
    text: A k3s-aws teardown (bin/cluster-down, keep-hub and delete-hub) unloads and removes the sandbox.* tunnel agents.
  - id: M4
    text: A k3s-hostinger refresh still installs and uses the unscoped com.k3d-manager.ssh-tunnel and ssh-tunnel-vault labels.
  - id: M5
    text: The sandbox forward binds local port 16443 (TUNNEL_SANDBOX_LOCAL_PORT), and the sandbox's ArgoCD registration default and the add_ubuntu_k3s_cluster kubeconfig both use that port; Hostinger's forward stays on 6443.
must_not:
  - id: N1
    text: A k3s-aws tunnel_start must not print "already running" or return early because a Hostinger autossh is running (red on pre-fix, where pgrep "autossh.*ubuntu" matches it).
  - id: N2
    text: A k3s-aws tunnel_start, tunnel_stop or teardown must not write, unload or remove com.k3d-manager.ssh-tunnel, com.k3d-manager.ssh-tunnel-vault or their plists and wrapper (red on pre-fix once N1 no longer returns early).
  - id: N3
    text: A k3s-hostinger refresh must not touch the sandbox.* tunnel agents.
  - id: N4
    text: A sandbox tunnel_stop must not pkill an ssh or autossh whose destination is another host, such as Hostinger's ssh -N ... -R 8200:127.0.0.1:18200 ubuntu@srv1754834.hstgr.cloud (red on pre-fix).
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, N1, N2, N3, N4]
    kind: offline
    text: BATS in scripts/tests/plugins/tunnel.bats (and cluster_down where teardown is covered) with launchctl, pgrep, ssh and autossh stubbed, recording every launchctl, plist write and rm; a stubbed pgrep process list that holds Hostinger's autossh command line; N1 red on pre-fix.
  - id: E2
    proves: [M1, N1, N2]
    kind: live
    text: Claude, after the operator's next make up CLUSTER_PROVIDER=k3s-aws with Hostinger up — Step 8 passes (vault-backend Ready on ubuntu-k3s), launchctl shows both sandbox.* tunnel agents, and com.k3d-manager.ssh-tunnel-vault still runs ssh to the Hostinger host.
  - id: E3
    proves: [M3, N2]
    kind: live
    text: Claude, after the following make down CLUSTER_PROVIDER=k3s-aws KEEP_LOCAL=1 — no sandbox.* tunnel agent is loaded, and Hostinger's two tunnel agents are still loaded with the same PIDs as before.
interface:
  - scripts/plugins/tunnel.sh tunnel_start, tunnel_stop, _tunnel_is_running and the TUNNEL_* label and path variables
  - bin/cluster-up Step 3 (k3s-aws), bin/cluster-down --confirm [--keep-hub|--delete-hub], bin/cluster-refresh (k3s-aws, k3s-hostinger)
  - launchd labels com.k3d-manager.ssh-tunnel, com.k3d-manager.ssh-tunnel-vault, com.k3d-manager.sandbox.ssh-tunnel, com.k3d-manager.sandbox.ssh-tunnel-vault
```

---

# Dispatch spec (Part A: this bug; Part B: `docs/bugs/2026-10-18-keep-hub-down-leaves-sandbox-frontend-agents.md`)

## Files

Only these files may change:

- `scripts/plugins/tunnel.sh`
- `scripts/etc/tunnel/vars.sh`
- `scripts/etc/argocd/vars.sh`
- `scripts/plugins/argocd.sh`
- `scripts/plugins/shopping_cart.sh`
- `scripts/lib/providers/k3s-aws.sh`
- `scripts/lib/providers/k3s-hostinger.sh`
- `bin/cluster-up`
- `bin/cluster-down`
- `bin/cluster-refresh`
- `scripts/tests/plugins/tunnel.bats`
- `scripts/tests/bin/cluster_down.bats`
- `scripts/tests/bin/cluster_refresh.bats`
- `scripts/tests/plugins/shopping_cart.bats`
- `docs/howto/tunnel.md`
- `docs/howto/launchd-daemons.md`

## Before You Start

1. Read this whole doc, and `docs/bugs/2026-10-18-keep-hub-down-leaves-sandbox-frontend-agents.md`
   (Part B's Symptom, Root cause and Acceptance).
2. Read `scripts/plugins/tunnel.sh` in full, `scripts/tests/plugins/tunnel.bats` in full, and the
   call sites: `bin/cluster-up` Step 3 (`tunnel_start`, ~line 452) and Step 10 (~lines 903–927),
   `bin/cluster-down` lines 97–117, 187–203 and 242–252, `bin/cluster-refresh` lines 236–260 and
   ~303, `scripts/lib/providers/k3s-aws.sh` (`tunnel_start` ~159, `tunnel_stop` ~453),
   `scripts/lib/providers/k3s-hostinger.sh` 936–947, `scripts/plugins/shopping_cart.sh` 54–67,
   `scripts/etc/argocd/vars.sh:68`, `scripts/plugins/argocd.sh:1584`.
3. **Step 0 — report before editing.** Run
   `grep -rnE 'host\.k3d\.internal:6443|127\.0\.0\.1:6443|localhost:6443|TUNNEL_LOCAL_PORT|TUNNEL_PLIST_PATH|TUNNEL_LAUNCHD_LABEL' bin scripts --include='*.sh' --include='*.py'`
   plus the same pattern over `bin/` without `--include`. Paste the output. Every non-test hit must
   be one of the sites listed in this spec. If any other non-test hit exists, do not edit it: list
   it in your last message as an open question and continue.

## Part A — tunnel scope (this bug)

### A1. `scripts/plugins/tunnel.sh` — source-time defaults

Replace:

```bash
: "${TUNNEL_SSH_HOST:=ubuntu}"
: "${TUNNEL_LOCAL_PORT:=6443}"
: "${TUNNEL_REMOTE_PORT:=6443}"
: "${TUNNEL_BIND_ADDR:=0.0.0.0}"
: "${TUNNEL_VAULT_REMOTE_PORT:=${TUNNEL_VAULT_PORT:-8200}}"
: "${TUNNEL_VAULT_LOCAL_PORT:=18200}"
: "${TUNNEL_LAUNCHD_LABEL:=com.k3d-manager.ssh-tunnel}"
: "${TUNNEL_PLIST_PATH:=${HOME}/Library/LaunchAgents/${TUNNEL_LAUNCHD_LABEL}.plist}"
: "${TUNNEL_VAULT_LAUNCHD_LABEL:=com.k3d-manager.ssh-tunnel-vault}"
: "${TUNNEL_VAULT_PLIST_PATH:=${HOME}/Library/LaunchAgents/${TUNNEL_VAULT_LAUNCHD_LABEL}.plist}"
: "${TUNNEL_VAULT_WRAPPER_PATH:=${HOME}/Library/LaunchAgents/${TUNNEL_VAULT_LAUNCHD_LABEL}.sh}"

_tunnel_is_running() {
  pgrep -f "autossh.*${TUNNEL_SSH_HOST}" >/dev/null 2>&1
}
```

with:

```bash
: "${TUNNEL_SSH_HOST:=ubuntu}"
: "${TUNNEL_REMOTE_PORT:=6443}"
: "${TUNNEL_BIND_ADDR:=0.0.0.0}"
: "${TUNNEL_VAULT_REMOTE_PORT:=${TUNNEL_VAULT_PORT:-8200}}"
: "${TUNNEL_VAULT_LOCAL_PORT:=18200}"

_tunnel_resolve_scope() {
  local prefix="com.k3d-manager" log_base="/tmp/k3d-manager-tunnel" port="6443"
  if [[ "${TUNNEL_SCOPE:-}" == "sandbox" ]]; then
    prefix="com.k3d-manager.sandbox"
    log_base="/tmp/k3d-manager-sandbox-tunnel"
    port="${TUNNEL_SANDBOX_LOCAL_PORT:-16443}"
  fi
  _TUNNEL_LAUNCHD_LABEL="${TUNNEL_LAUNCHD_LABEL:-${prefix}.ssh-tunnel}"
  _TUNNEL_PLIST_PATH="${TUNNEL_PLIST_PATH:-${HOME}/Library/LaunchAgents/${_TUNNEL_LAUNCHD_LABEL}.plist}"
  _TUNNEL_VAULT_LAUNCHD_LABEL="${TUNNEL_VAULT_LAUNCHD_LABEL:-${prefix}.ssh-tunnel-vault}"
  _TUNNEL_VAULT_PLIST_PATH="${TUNNEL_VAULT_PLIST_PATH:-${HOME}/Library/LaunchAgents/${_TUNNEL_VAULT_LAUNCHD_LABEL}.plist}"
  _TUNNEL_VAULT_WRAPPER_PATH="${TUNNEL_VAULT_WRAPPER_PATH:-${HOME}/Library/LaunchAgents/${_TUNNEL_VAULT_LAUNCHD_LABEL}.sh}"
  _TUNNEL_LOCAL_PORT="${TUNNEL_LOCAL_PORT:-${port}}"
  _TUNNEL_LOG_BASE="${log_base}"
}

_tunnel_regex_escape() {
  printf '%s' "$1" | sed 's/[][\.*^$+?(){}|]/\\&/g'
}

_tunnel_forward_pattern() {
  printf 'autossh .* -N %s$' "$(_tunnel_regex_escape "${TUNNEL_SSH_HOST}")"
}

_tunnel_vault_pattern() {
  printf 'ssh -N .*-R %s:127\\.0\\.0\\.1:%s %s$' "${TUNNEL_VAULT_REMOTE_PORT}" "${TUNNEL_VAULT_LOCAL_PORT}" \
    "$(_tunnel_regex_escape "${TUNNEL_SSH_HOST}")"
}

_tunnel_is_running() {
  pgrep -f "$(_tunnel_forward_pattern)" >/dev/null 2>&1
}
```

`TUNNEL_SCOPE`, `TUNNEL_SANDBOX_LOCAL_PORT` and the `TUNNEL_*` label/path/port variables are
read on every call, never cached, so a Hostinger call after a sandbox call in one shell resolves
the unscoped values again. An explicitly set `TUNNEL_LAUNCHD_LABEL` (etc.) still wins, which keeps
the existing `tunnel.bats` setup working.

Check the escape and pattern output in a shell before relying on them:
`_tunnel_regex_escape 'ubuntu@srv1754834.hstgr.cloud'` must print `ubuntu@srv1754834\.hstgr\.cloud`,
and `TUNNEL_SSH_HOST=ubuntu _tunnel_vault_pattern` must print
`ssh -N .*-R 8200:127\.0\.0\.1:18200 ubuntu$`. Paste both outputs.

### A2. `scripts/plugins/tunnel.sh` — use the resolved values everywhere

- `_tunnel_vault_is_running` becomes `pgrep -f "$(_tunnel_vault_pattern)" >/dev/null 2>&1`.
- In `tunnel_stop`, `pkill -f "autossh.*${TUNNEL_SSH_HOST}"` becomes
  `pkill -f "$(_tunnel_forward_pattern)"`, and the vault `pkill` becomes
  `pkill -f "$(_tunnel_vault_pattern)"`.
- Call `_tunnel_resolve_scope` as the first statement of `_tunnel_launchd_loaded`,
  `_tunnel_vault_launchd_loaded`, `_tunnel_plist_has_reverse`, `_tunnel_write_plist`,
  `_tunnel_write_vault_agent`, `tunnel_start`, `tunnel_stop` and `tunnel_status` (before the
  `--help` check in the three public functions).
- Everywhere after the header, replace `${TUNNEL_LAUNCHD_LABEL}`, `${TUNNEL_PLIST_PATH}`,
  `${TUNNEL_VAULT_LAUNCHD_LABEL}`, `${TUNNEL_VAULT_PLIST_PATH}`, `${TUNNEL_VAULT_WRAPPER_PATH}` and
  `${TUNNEL_LOCAL_PORT}` with `${_TUNNEL_LAUNCHD_LABEL}`, `${_TUNNEL_PLIST_PATH}`,
  `${_TUNNEL_VAULT_LAUNCHD_LABEL}`, `${_TUNNEL_VAULT_PLIST_PATH}`, `${_TUNNEL_VAULT_WRAPPER_PATH}`
  and `${_TUNNEL_LOCAL_PORT}`. After the edit,
  `grep -nE '\$\{TUNNEL_(LAUNCHD_LABEL|PLIST_PATH|VAULT_LAUNCHD_LABEL|VAULT_PLIST_PATH|VAULT_WRAPPER_PATH|LOCAL_PORT)\}' scripts/plugins/tunnel.sh`
  must print nothing (the `:-` forms inside `_tunnel_resolve_scope` do not match it).
- Log paths: `/tmp/k3d-manager-tunnel.out` and `.err` become `${_TUNNEL_LOG_BASE}.out` and
  `${_TUNNEL_LOG_BASE}.err`; `/tmp/k3d-manager-tunnel-vault.out` and `.err` become
  `${_TUNNEL_LOG_BASE}-vault.out` and `${_TUNNEL_LOG_BASE}-vault.err`. The unscoped scope keeps
  today's exact file names.
- The `tunnel_start` help text: the `TUNNEL_LOCAL_PORT` line reads
  `(default: 6443; 16443 with TUNNEL_SCOPE=sandbox)`, and add a line
  `  TUNNEL_SCOPE       sandbox → com.k3d-manager.sandbox.* agents (default: unscoped)`.
- Add, after `_tunnel_plist_has_reverse`:

```bash
_tunnel_remove_agent_files() {
  _tunnel_resolve_scope
  rm -f -- "${_TUNNEL_PLIST_PATH}" "${_TUNNEL_VAULT_PLIST_PATH}" "${_TUNNEL_VAULT_WRAPPER_PATH}"
}
```

### A3. `scripts/etc/tunnel/vars.sh`

Delete these three lines (their defaults now come from `_tunnel_resolve_scope`):

```bash
TUNNEL_LOCAL_PORT="${TUNNEL_LOCAL_PORT:-6443}"
TUNNEL_LAUNCHD_LABEL="${TUNNEL_LAUNCHD_LABEL:-com.k3d-manager.ssh-tunnel}"
TUNNEL_PLIST_PATH="${TUNNEL_PLIST_PATH:-${HOME}/Library/LaunchAgents/${TUNNEL_LAUNCHD_LABEL}.plist}"
```

### A4. Sandbox call sites set `TUNNEL_SCOPE=sandbox`

- `bin/cluster-up` Step 3: `_dry_guard "start autossh tunnel" tunnel_start` →
  `TUNNEL_SCOPE=sandbox _dry_guard "start autossh tunnel" tunnel_start`.
- `scripts/lib/providers/k3s-aws.sh` ~159: same change to its `_dry_guard "start autossh tunnel" tunnel_start`.
- `scripts/lib/providers/k3s-aws.sh` ~453: `tunnel_stop || true` → `TUNNEL_SCOPE=sandbox tunnel_stop || true`.
- `bin/cluster-refresh`: directly after `export TUNNEL_SSH_HOST`, add `export TUNNEL_SCOPE=sandbox`.
  (`make refresh` sends `k3s-hostinger` to `refresh_cluster`, never to `bin/cluster-refresh`, so
  every case there is a sandbox.) Replace `_tunnel_port="${TUNNEL_LOCAL_PORT:-6443}"` with
  `_tunnel_port="${_TUNNEL_LOCAL_PORT}"`.
- `bin/cluster-refresh` ~303:
  `_argocd_server="${ARGOCD_APP_CLUSTER_SERVER:-https://host.k3d.internal:6443}"` →
  `_argocd_server="${ARGOCD_APP_CLUSTER_SERVER:-https://host.k3d.internal:${TUNNEL_SANDBOX_LOCAL_PORT:-16443}}"`.

### A5. `bin/cluster-down` (k3s-aws case, lines 97–117)

Move the tunnel stop out of the `if [[ "${_keep_hub}" -eq 0 ]]` block so it runs on keep-hub and
delete-hub teardowns, scoped to the sandbox, and remove the agent files. The `lsof … | xargs kill -9`
block stays inside the `_keep_hub -eq 0` branch unchanged. Replace:

```bash
      _info "[acg-down] Stopping tunnel..."
      if _dry_run_active; then
        _info "DRY_RUN: would stop autossh tunnel"
      else
        tunnel_stop 2>/dev/null || true
      fi
    fi
```

with:

```bash
    fi
    _info "[acg-down] Stopping sandbox tunnel agents..."
    if _dry_run_active; then
      _info "DRY_RUN: would stop the com.k3d-manager.sandbox.ssh-tunnel agents"
    else
      TUNNEL_SCOPE=sandbox tunnel_stop 2>/dev/null || true
      TUNNEL_SCOPE=sandbox _tunnel_remove_agent_files
    fi
```

### A6. Hostinger keeps the unscoped agents

`scripts/lib/providers/k3s-hostinger.sh` ~938: directly after
`local _prev_tunnel_host="${TUNNEL_SSH_HOST:-}"`, add `local TUNNEL_SCOPE=""`.

### A7. ArgoCD registration and kubeconfig fallback use the sandbox port

- `scripts/etc/argocd/vars.sh:68`:
  `export ARGOCD_APP_CLUSTER_SERVER="${ARGOCD_APP_CLUSTER_SERVER:-https://host.k3d.internal:6443}"` →
  `export ARGOCD_APP_CLUSTER_SERVER="${ARGOCD_APP_CLUSTER_SERVER:-https://host.k3d.internal:${TUNNEL_SANDBOX_LOCAL_PORT:-16443}}"`.
- `scripts/plugins/argocd.sh:1584` help text: `(default: https://host.k3d.internal:6443)` →
  `(default: https://host.k3d.internal:16443, the sandbox tunnel)`.
- `bin/cluster-up` ~927:
  `_info "[acg-up] ArgoCD cluster registered: ubuntu-k3s → https://host.k3d.internal:6443"` →
  `_info "[acg-up] ArgoCD cluster registered: ubuntu-k3s → ${ARGOCD_APP_CLUSTER_SERVER:-https://host.k3d.internal:${TUNNEL_SANDBOX_LOCAL_PORT:-16443}}"`.
- `scripts/plugins/shopping_cart.sh` `add_ubuntu_k3s_cluster`: before the `ssh "${ssh_target}" "cat …"`
  export, add

```bash
  local _tunnel_port="${TUNNEL_SANDBOX_LOCAL_PORT:-16443}"
  if [[ ! "${_tunnel_port}" =~ ^[0-9]+$ ]]; then
    _err "[shopping_cart] TUNNEL_SANDBOX_LOCAL_PORT must be numeric: ${_tunnel_port}"
    return 1
  fi
```

  change the `sed` to
  `sed -e 's|https://localhost:|https://127.0.0.1:|g' -e "s|https://127.0.0.1:6443|https://127.0.0.1:${_tunnel_port}|g"`,
  and in the two messages replace `127.0.0.1:6443` with `127.0.0.1:${_tunnel_port}`.

### A8. Docs

- `docs/howto/tunnel.md`: say that the sandbox (`TUNNEL_SCOPE=sandbox`, set by `make up`,
  `make down` and `make refresh` for ACG providers) uses `com.k3d-manager.sandbox.ssh-tunnel` and
  `com.k3d-manager.sandbox.ssh-tunnel-vault` with local port 16443 and logs
  `/tmp/k3d-manager-sandbox-tunnel*`, while Hostinger keeps the unscoped agents on 6443; and that
  hub ArgoCD reaches the sandbox at `https://host.k3d.internal:16443`.
- `docs/howto/launchd-daemons.md`: add rows for the two `sandbox.*` agents next to the
  `com.k3d-manager.ssh-tunnel` row, and say in the `com.k3d-manager.ssh-tunnel` section that it is
  Hostinger's.

## Part B — keep-hub down leaves frontend agents (`2026-10-18-keep-hub-down-leaves-sandbox-frontend-agents.md`)

### B1. Frontend port-forward LaunchAgent (`bin/cluster-down` ~242–252)

Directly after the closing `fi` of the `if [[ -f "${_frontend_pf_pid_file}" ]]` block, add:

```bash
_frontend_pf_agent_plist="${FRONTEND_PF_PLIST:-${HOME}/Library/LaunchAgents/com.k3d-manager.frontend-port-forward.plist}"
if [[ -f "${_frontend_pf_agent_plist}" ]] && grep -Fq -- '<string>ubuntu-k3s</string>' "${_frontend_pf_agent_plist}"; then
  if _dry_run_active; then
    _info "DRY_RUN: would unload frontend port-forward LaunchAgent"
  else
    launchctl unload "${_frontend_pf_agent_plist}" 2>/dev/null || true
    _info "[acg-down] Frontend port-forward LaunchAgent unloaded"
  fi
  _dry_guard "remove frontend port-forward plist" rm -f "${_frontend_pf_agent_plist}"
elif [[ -f "${_frontend_pf_agent_plist}" ]]; then
  _info "[acg-down] com.k3d-manager.frontend-port-forward targets another cluster — left in place"
fi
```

### B2. Frontend browser daemon left installed (`bin/cluster-down` ~203)

Directly after
`_run_command --prefer-sudo --soft -- rm -f "${_frontend_browser_plist}" "${_frontend_browser_wrapper}" >/dev/null 2>&1 || true`,
add:

```bash
  if ! _dry_run_active && [[ -e "${_frontend_browser_plist}" ]]; then
    _warn "[acg-down] com.k3d-manager.sandbox.frontend-browser-http is still installed (see ${_frontend_browser_launchctl_log}); remove it with: sudo launchctl bootout system ${_frontend_browser_plist}; sudo rm -f ${_frontend_browser_plist}"
  fi
```

This warns whenever the plist survives — a bootout refused with `Operation not permitted`, or the
headless skip — and stays quiet when the daemon was never installed. Part B's M2 and N3 are read
this way.

## Tests (E1 of both bugs)

Add to `scripts/tests/plugins/tunnel.bats` (keep every existing test passing):

- **M2/N1:** with `pgrep` stubbed to match its `-f` pattern with `grep -E` against a fake process
  list holding only `/opt/homebrew/bin/autossh -M 0 -o ExitOnForwardFailure=yes -L 0.0.0.0:6443:localhost:6443 -N ubuntu@srv1754834.hstgr.cloud`,
  `TUNNEL_SSH_HOST=ubuntu _tunnel_is_running` fails, and with
  `... -N ubuntu` in the list it succeeds. A `TUNNEL_SCOPE=sandbox tunnel_start` with that
  Hostinger list and both unscoped labels reported loaded by a stub `launchctl list` must not print
  `already running`.
- **M1/N2:** unset the `TUNNEL_*` label/path exports from setup for this test (use a temp `HOME`),
  run `TUNNEL_SCOPE=sandbox tunnel_start` with `launchctl` recorded, and assert the written plists
  are `$HOME/Library/LaunchAgents/com.k3d-manager.sandbox.ssh-tunnel.plist` and
  `…sandbox.ssh-tunnel-vault.plist`, the forward is `0.0.0.0:16443:localhost:6443`, the wrapper
  has `-R 8200:127.0.0.1:18200 "ubuntu"`, and no `launchctl` call and no file names the unscoped
  `com.k3d-manager.ssh-tunnel.plist` or `ssh-tunnel-vault.plist`.
- **M4/N3:** the same with `TUNNEL_SCOPE` unset writes only the unscoped plists, port 6443, logs
  `/tmp/k3d-manager-tunnel.out`, and touches no `sandbox.*` path.
- **N4:** with `pkill` recorded, `TUNNEL_SSH_HOST=ubuntu TUNNEL_SCOPE=sandbox tunnel_stop` passes a
  pattern that `grep -E` does not match against
  `/usr/bin/ssh -N -o BatchMode=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -R 8200:127.0.0.1:18200 ubuntu@srv1754834.hstgr.cloud`
  and does match the same line ending in ` ubuntu`.
- **Resolve-per-call:** `TUNNEL_SCOPE=sandbox _tunnel_resolve_scope` then `TUNNEL_SCOPE= _tunnel_resolve_scope`
  leaves `_TUNNEL_LAUNCHD_LABEL=com.k3d-manager.ssh-tunnel` and `_TUNNEL_LOCAL_PORT=6443`.

Add to `scripts/tests/bin/cluster_down.bats` (or a new `@test` block in the same file using the
`cluster_down_acceptance.bats` stub style):

- **M3/N2 (Part A):** a k3s-aws `bin/cluster-down --confirm --keep-hub` run with the sandbox and the
  unscoped tunnel plists both present in a temp `HOME` removes only the `sandbox.*` tunnel files and
  never `launchctl unload`s an unscoped tunnel plist. Red on pre-fix (pre-fix runs no `tunnel_stop`
  on keep-hub).
- **Part B M1/N1/N2:** a `com.k3d-manager.frontend-port-forward.plist` containing
  `<string>ubuntu-k3s</string>` is unloaded and removed on keep-hub (N1 red on pre-fix); one
  containing `<string>ubuntu-hostinger</string>` is left untouched.
- **Part B M2/N3:** with a `FRONTEND_BROWSER_LISTENER_PLIST` temp file and `launchctl`/`rm` via
  `_run_command` stubbed to fail with `Operation not permitted`, the output contains
  `com.k3d-manager.sandbox.frontend-browser-http is still installed` and `sudo launchctl bootout system`
  (red on pre-fix, which prints neither).

Add to `scripts/tests/plugins/shopping_cart.bats`: `add_ubuntu_k3s_cluster` with `ssh` stubbed to
print a kubeconfig whose server is `https://127.0.0.1:6443` writes
`https://127.0.0.1:16443` to the local kubeconfig, and rejects `TUNNEL_SANDBOX_LOCAL_PORT=1x`.
Add to `scripts/tests/bin/cluster_refresh.bats` a static check that `bin/cluster-refresh` exports
`TUNNEL_SCOPE=sandbox` and that its ArgoCD server default names `16443`.

**Red on pre-fix:** for every test marked red above, run it against the pre-fix file
(`git show HEAD:<path> > "$TMPDIR/<name>"` and point the test at the copy, never `git checkout`)
and paste the failing output.

## Rules

Run and paste the output of each:

- `shellcheck -S warning scripts/plugins/tunnel.sh scripts/etc/tunnel/vars.sh scripts/etc/argocd/vars.sh scripts/plugins/shopping_cart.sh scripts/lib/providers/k3s-aws.sh scripts/lib/providers/k3s-hostinger.sh bin/cluster-up bin/cluster-down bin/cluster-refresh` — no new warnings versus pre-fix.
- `bats scripts/tests/plugins/tunnel.bats scripts/tests/bin/cluster_down.bats scripts/tests/bin/cluster_down_acceptance.bats scripts/tests/bin/cluster_refresh.bats scripts/tests/plugins/shopping_cart.bats scripts/tests/plugins/argocd.bats scripts/tests/lib/provider_contract.bats scripts/tests/lib/k3s_aws_deregister.bats`
- The red-on-pre-fix runs above.
- The Step 0 grep and the A1 and A2 grep/escape outputs.

`make test` takes ~15 minutes; Claude runs the full suite after landing. Do not run it.

## Definition of Done

- [ ] Every change in A1–A8 and B1–B2 made; nothing outside **Files** changed.
- [ ] Rules output pasted; all listed BATS green; each red-on-pre-fix test shown red.
- [ ] Last message lists every changed file and any Step 0 open question.
- [ ] Claude commits after verification with this message, verbatim:
  `fix(tunnel): give the sandbox its own tunnel agents and port; clean up sandbox frontend agents on keep-hub down`
- [ ] Claude pushes to `origin/k3d-manager-v1.43.4` and updates `memory-bank/activeContext.md` and `progress.md` with the SHA.

## What NOT to Do

- Do NOT run `git add`, `git commit` or `git push`; do NOT create a PR or touch `main`; do NOT use `--no-verify`.
- Do NOT run `launchctl`, `pkill`, `ssh`, `autossh`, `kubectl` or any `make` lifecycle target for real — tests stub them.
- Do NOT rename or move Hostinger's unscoped labels, and do NOT change `TUNNEL_REMOTE_PORT`, `TUNNEL_VAULT_REMOTE_PORT` or `TUNNEL_VAULT_LOCAL_PORT`.
- Do NOT change the `lsof … | xargs kill -9` block in `bin/cluster-down` or the Keycloak/legacy cleanup blocks.
- Do NOT modify `scripts/lib/foundation/`, `memory-bank/`, or this spec.
- Do NOT add an ArgoCD re-registration step; the next `make up` or `make refresh` re-registers with the new port.
