# Bug: a sandbox `make up` takes over the launchd agents behind Hostinger's public routes

**Filed:** 2026-10-05, Claude
**Branch:** `k3d-manager-v1.41.0`
**Status:** FIXED — Codex, verified by Claude 2026-10-05: 139/139 across the listed suites plus pytest 13/13; all 3 mutations red. Claude corrected four things before the commit: docs had moved the webhook push target to `9092` (it stays `9091`, now always Hostinger); the `cluster-down` legacy bootouts ran under dry-run; the agent bootout used sudo and bad syntax; and the root-plist `rm` lacked sudo. The dry-run guard has no test. Live check pending the next sandbox `make up`.
**Severity:** high. The public `frontend.3ai-talk.org` returns 502 once the ACG sandbox expires,
although the Hostinger cluster and its frontend pod are healthy.

## Symptom (2026-10-05, about 04:00 UTC)

`make status CLUSTER_PROVIDER=k3s-hostinger`:

```
✗ Frontend: HTTP Error 502: Bad Gateway
✗ Pushgateway: <urlopen error [Errno 61] Connection refused>
Overall: FAIL (2 errors, 0 warnings)
```

ArgoCD, Keycloak, Prometheus (401, as intended) and Grafana were fine.

## Evidence (Claude, read-only)

- **Hostinger is healthy.** `frontend-87f4b57f4-x58gz` is `1/1 Running`, and `endpoints/frontend` is
  `10.42.0.232:8080`. No ingress and no in-cluster `cloudflared` sit in front of it.
- **The public route ends on this Mac.** In `~/.cloudflared/config.yml`, `frontend.3ai-talk.org`
  routes to `http://127.0.0.2:80`. That address is served by the root LaunchDaemon
  `com.k3d-manager.frontend-browser-http`.
- **The daemon now forwards from the sandbox.** Its plist runs
  `~/.local/share/k3d-manager/k3s-aws/bin/frontend-browser-http.sh` (written Oct 3 19:28 by the
  sandbox `make up`), which runs `kubectl --context ubuntu-k3s port-forward --address=127.0.0.2 svc/frontend 80:80`.
  The Hostinger copy of the wrapper (`k3s-hostinger/bin/frontend-browser-http.sh`, Sep 29) still
  exists, but no daemon points at it.
- **The sandbox is gone.** The forward logs show `dial tcp 54.187.188.234:6443: i/o timeout`
  every 30 s.
- **Pushgateway, same pattern.** The user agent `com.k3d-manager.pushgateway-port-forward`
  forwards `svc/prometheus-pushgateway` from `--context ubuntu-k3s` on `9091:9091`. It logs to
  `k3s-aws/logs/pushgateway-pf.log`, which shows the same timeouts. The status check probes
  `localhost:9091` for k3s-hostinger.
- `com.k3d-manager.frontend-port-forward` (`3000:80`) also points at `ubuntu-k3s`.

## Cause

`bin/cluster-up` (sandbox) and `scripts/lib/providers/k3s-hostinger.sh`
(`_hostinger_refresh_access_layer`, around :583–:700) install launchd jobs with **the same labels
and the same local ports**: `com.k3d-manager.frontend-browser-http` on `127.0.0.2:80`, and
`com.k3d-manager.pushgateway-port-forward` on `9091`. The provider that ran last owns them.
A sandbox lives 4–8 hours, so a sandbox `make up` breaks Hostinger's public frontend a few hours
later, and nothing restores it.

## Operator workaround (now)

`make refresh-edge` alone does **not** fix the frontend. `_hostinger_refresh_access_layer` rewrites
the wrapper in `k3s-hostinger/bin/` and restarts the system daemon, but it never rewrites
`/Library/LaunchDaemons/com.k3d-manager.frontend-browser-http.plist`. That plist still runs the
`k3s-aws/` wrapper, so the restart brings back the dead sandbox forward. It does fix Pushgateway,
whose user plist it regenerates.

In Terminal.app:

1. Point the root daemon at the Hostinger wrapper:
   `sudo plutil -replace ProgramArguments.1 -string "$HOME/.local/share/k3d-manager/k3s-hostinger/bin/frontend-browser-http.sh" /Library/LaunchDaemons/com.k3d-manager.frontend-browser-http.plist`
2. Refresh the edge, which restarts that daemon and rewrites the Pushgateway forward:
   `make refresh-edge CLUSTER_PROVIDER=k3s-hostinger`
3. `make status CLUSTER_PROVIDER=k3s-hostinger`

`keycloak-browser-http` points at the `k3s-aws` wrapper too. It does not serve a public route
(`keycloak.3ai-talk.org` goes to `127.0.0.1:8880`), so it is left alone here, but the fix must cover it.

## Second defect: the edge refresh never owns the system plists

The same gap means `make refresh-edge` can never recover from this state on its own. The fix
must make `_hostinger_refresh_access_layer` write (or verify) the `ProgramArguments` of each
system daemon it restarts.

## Fix direction (to spec)

- **Option A: per-provider labels and ports.** Give the sandbox's frontend and Pushgateway
  forwards provider-scoped labels and their own ports, so the two providers never collide. The
  tunnel route `frontend.3ai-talk.org` then belongs to Hostinger alone.
- **Option B: the sandbox does not install public-route daemons.** `127.0.0.2:80` exists for the
  public tunnel. The sandbox needs only its own local forwards.
- **In either case:** `cluster-down` / sandbox expiry must not leave a Hostinger-route label
  pointing at a dead context. `make status` could also flag any `com.k3d-manager.*` plist whose
  `--context` differs from the provider being checked.

## Workaround result (2026-10-05)

The operator ran the three steps, and `make status CLUSTER_PROVIDER=k3s-hostinger` was HEALTHY.

- The Pushgateway agent now runs `com.k3d-manager.pushgateway-port-forward.sh` with `--context "ubuntu-hostinger"`.
- `plutil -replace ProgramArguments.1` **inserted** an element instead of replacing it. The daemon's
  array is now `[/bin/bash, k3s-hostinger/.../frontend-browser-http.sh, k3s-aws/.../frontend-browser-http.sh]`.
  It works, because bash runs the first script and passes the second as `$1`, which the wrapper ignores.
  Fix item 4 below rewrites the whole plist, which removes the stray element.

## Third writer: `bin/cluster-refresh`

`bin/cluster-refresh:540–564` (a sandbox `make refresh`) rewrites the shared frontend wrapper with
`--context ubuntu-k3s`, installs `com.k3d-manager.frontend-browser-http` if it is missing, and
restarts it. It takes the route over the same way `cluster-up` does.

## Fix spec (Claude, 2026-10-05)

Option A. Each sandbox provider (`k3s-aws`, `k3s-gcp`, `k3s-az`; only one runs at a time) gets its
own launchd labels and local addresses under a `sandbox` scope. Hostinger keeps the unscoped labels,
`127.0.0.2:80` and `9091`, so the Cloudflare route `frontend.3ai-talk.org → 127.0.0.2:80` belongs to
Hostinger alone. The Hostinger edge refresh writes its own daemon plist, so it recovers on its own
from any state.

| | Hostinger (unchanged) | Sandbox (new) |
|---|---|---|
| Frontend daemon label | `com.k3d-manager.frontend-browser-http` | `com.k3d-manager.sandbox.frontend-browser-http` |
| Frontend bind | `127.0.0.2:80` | `127.0.0.3:80` |
| Loopback alias daemon | `com.k3d-manager.loopback-alias` (127.0.0.2) | `com.k3d-manager.sandbox.loopback-alias` (127.0.0.3) |
| Pushgateway agent label | `com.k3d-manager.pushgateway-port-forward` | `com.k3d-manager.sandbox.pushgateway-port-forward` |
| Pushgateway local port | `9091` | `9092` |

`/etc/hosts` `frontend.shopping-cart.local` points at the sandbox (`127.0.0.3`). It is a local name.
The Hostinger status and smoke checks use the public `https://frontend.3ai-talk.org`.

### File 1 — `bin/cluster-up`

1. `_HOSTS_LIST` (:670): `"frontend.shopping-cart.local|127.0.0.2"` → `"frontend.shopping-cart.local|127.0.0.3"`.
2. Step 10g (:1577–1712):
   - `_frontend_browser_label="com.k3d-manager.sandbox.frontend-browser-http"`. The plist default
     follows from the label: `/Library/LaunchDaemons/com.k3d-manager.sandbox.frontend-browser-http.plist`.
   - Every `127.0.0.2` in this block becomes `127.0.0.3`: the `ifconfig` probe regex `127\.0\.0\.3`,
     the alias command, the warning text, the loopback plist's `<string>`, the wrapper's
     `--address=` and its log line, and the two `_info` messages.
   - `_loopback_label="com.k3d-manager.sandbox.loopback-alias"`, and the loopback tmp plist becomes
     `${_ACG_STATE_DIR}/run/sandbox-loopback-alias.plist`. **Do not** boot out or delete
     `com.k3d-manager.loopback-alias`. Hostinger needs 127.0.0.2 to survive a reboot.
3. Step 13 `_info` (:1929): `127.0.0.2` → `127.0.0.3`.
4. Step 14c (:1964–2005): `_pgw_pf_label="com.k3d-manager.sandbox.pushgateway-port-forward"`, the
   port argument `9092:9091`, and both `_info` lines say `localhost:9092`.
5. Nothing in `cluster-up` may bootout, load, install or remove the unscoped
   `com.k3d-manager.frontend-browser-http`, `com.k3d-manager.pushgateway-port-forward` or
   `com.k3d-manager.loopback-alias`.

### File 2 — `bin/cluster-refresh`

In the frontend block (:540–564), the wrapper binds `127.0.0.3` (the `--address=` and the log
line), and both `_system_daemon_install_if_missing` and `_launchd_ensure` use
`com.k3d-manager.sandbox.frontend-browser-http` and
`/Library/LaunchDaemons/com.k3d-manager.sandbox.frontend-browser-http.plist`. Change nothing else
in the file.

### File 3 — `bin/cluster-down`

- Frontend (:282–296): default plist
  `/Library/LaunchDaemons/com.k3d-manager.sandbox.frontend-browser-http.plist`.
- Pushgateway (:299–307): `_pgw_pf_label="com.k3d-manager.sandbox.pushgateway-port-forward"`.
- **Legacy cleanup, guarded.** After those two blocks, boot out and remove the unscoped
  `/Library/LaunchDaemons/com.k3d-manager.frontend-browser-http.plist` **only if** that file
  contains the string `"${_ACG_STATE_DIR}/bin/frontend-browser-http.sh"`, meaning the sandbox owns
  it. Do the same for `~/Library/LaunchAgents/com.k3d-manager.pushgateway-port-forward.plist`, only
  if it contains `ubuntu-k3s`. Use the same `_run_command --prefer-sudo --quiet --soft`,
  `_dry_guard` and headless-sudo patterns as the surrounding code. If the file references anything
  else, leave it and print `_info "[acg-down] unscoped <label> belongs to another provider — left in place"`.

### File 4 — `scripts/lib/providers/k3s-hostinger.sh`

In `_hostinger_refresh_access_layer`, before the `_hostinger_restart_launchd` call for
`com.k3d-manager.frontend-browser-http` (:694–697), make sure the system plist runs the Hostinger
wrapper:

- Add `function _hostinger_write_frontend_browser_plist() { local plist_tmp="$1" wrapper="$2" log_file="$3"; ... }`.
  It writes the plist with the same shape `bin/cluster-up` used: Label
  `com.k3d-manager.frontend-browser-http`, `ProgramArguments` exactly `[/bin/bash, <wrapper>]`,
  RunAtLoad, KeepAlive, and stdout and stderr both set to `<log_file>`.
- Write it to `${_ACG_STATE_DIR}/run/frontend-browser-http.plist`. If
  `/Library/LaunchDaemons/com.k3d-manager.frontend-browser-http.plist` is missing or differs
  (`diff -q`), install it with
  `_run_command --interactive-sudo --quiet --soft -- install -m 644 <tmp> <plist>`. On failure,
  `_warn "[k3s-hostinger] could not install frontend-browser-http plist — public frontend may still point at another provider"`.
  Remove the tmp file either way.
- Do not change the other system daemons (`argocd-browser-https`, `keycloak-browser-http`).

### File 5 — `scripts/lib/webhook/smoke.py`

In the `smoke_endpoints.append(("Pushgateway", ...))` line (:592), use
`http://localhost:9091/-/healthy` for `k3s-hostinger` and `http://localhost:9092/-/healthy`
otherwise. Leave `_provider_supports_pushgateway` unchanged.

### File 6 — tests

New `scripts/tests/bin/sandbox_launchd_scope.bats`. Use `run grep` with `status` checks, never a bare
`! grep`.

1. `bin/cluster-up`, `bin/cluster-refresh` and `bin/cluster-down` each contain
   `com.k3d-manager.sandbox.frontend-browser-http`.
2. `bin/cluster-up` has no line that matches `_frontend_browser_label="com.k3d-manager.frontend-browser-http"`
   or `_pgw_pf_label="com.k3d-manager.pushgateway-port-forward"`, and no `127.0.0.2` outside the
   unchanged loopback comment, if any. The simplest gate is `grep -c '127\.0\.0\.2' bin/cluster-up`
   equals `0`.
3. `bin/cluster-up` contains `9092:9091` and `com.k3d-manager.sandbox.loopback-alias`.
4. `bin/cluster-refresh` has no `127.0.0.2`, and does not contain
   `"/Library/LaunchDaemons/com.k3d-manager.frontend-browser-http.plist"`.
5. Functional, for the `cluster-down` legacy guard. Extract the guarded block with `sed -n`, between
   marker comments you add (`# legacy-unscoped-cleanup:begin` and `:end`). Run it with `launchctl`,
   `sudo` and `rm` stubs on `PATH`, plus stub `_run_command`, `_dry_guard`, `_dry_run_active`
   (returns 1) and `_info` functions. Run it against temp plists, with the plist paths overridable
   through env vars defaulting to the real ones. Case a: the plist references the sandbox wrapper,
   so `rm` is called on it. Case b: it references `k3s-hostinger`, so `rm` is not called and the
   output contains `belongs to another provider`.
6. Functional, for File 4. Source `scripts/lib/providers/k3s-hostinger.sh` the way
   `scripts/tests/lib/provider_contract.bats` does, call `_hostinger_write_frontend_browser_plist`
   on temp paths, and assert that `plutil -extract ProgramArguments json -o -` of the output is
   exactly `["\/bin\/bash","<wrapper>"]`, with two elements.

Update existing tests that assert the old values: `scripts/tests/bin/cluster_refresh.bats:73`
(`127.0.0.2` → `127.0.0.3`), and any `cluster_up.bats` or `cluster_down.bats` assertions that the
new names break. Do not edit the `provider_contract.bats` Hostinger assertions (:982, :1000); they
must stay green unchanged.

In `scripts/tests/bin/test_webhook_pushgateway_provider.py`, add a test: run the smoke function
with `urlopen` patched and the provider set to `k3s-aws`. The Pushgateway URL it requests ends with
`:9092/-/healthy`; for `k3s-hostinger` it ends with `:9091/-/healthy`. Follow the patching style of
`test_smoke_prometheus_auth.py`.

### Docs

Update the page a reader opens for local sandbox URLs: `grep -rln '127.0.0.2\|localhost:9091' docs/guides docs/howto README.md`.
Change only the lines describing the **sandbox**. Hostinger stays `127.0.0.2` and `9091`.

## Rules

- Modify only the files named above, plus the doc lines from the grep. Do not touch
  `scripts/lib/foundation/`, `scripts/lib/acg/`, or any launchd or `/etc/hosts` state on this Mac.
  Do not run `make up`, `make refresh`, `make refresh-edge`, `make down` or `launchctl` for real.
- Do not commit or push. Leave the changes unstaged.
- Run and paste:
  - `shellcheck bin/cluster-up bin/cluster-refresh bin/cluster-down scripts/lib/providers/k3s-hostinger.sh`:
    no new warnings, comparing counts against `git show HEAD:<file> | shellcheck -`;
  - `bats scripts/tests/bin/sandbox_launchd_scope.bats scripts/tests/bin/cluster_up.bats scripts/tests/bin/cluster_down.bats scripts/tests/bin/cluster_refresh.bats scripts/tests/lib/provider_contract.bats scripts/tests/lib/hostinger_pushgateway_port_forward.bats`;
  - `bats scripts/tests/lib/bats_negation_lint.bats`;
  - `python3 -m pytest -q scripts/tests/bin/test_webhook_pushgateway_provider.py scripts/tests/bin/test_smoke_prometheus_auth.py`.
- Mutations: snapshot each file to `$TMPDIR`, restore, and prove the restore with `cmp`.
  1. Revert `_frontend_browser_label` in `cluster-up` to the unscoped name → test 1 or 2 is red.
  2. Remove the ownership check in the `cluster-down` legacy block, so it always removes → test 5b is red.
  3. Make `_hostinger_write_frontend_browser_plist` emit a third `ProgramArguments` element → test 6 is red.
- Do not run `make test`.

## Done when

No sandbox code path writes, loads or removes a Hostinger-owned label or binds `127.0.0.2` or
`9091`. `make refresh-edge CLUSTER_PROVIDER=k3s-hostinger` alone restores the frontend daemon's
`ProgramArguments`. The new and listed suites pass, and all three mutations go red, then are
restored.

**Follow-ups (not in this spec):** `keycloak-browser-http` and `argocd-browser-https` share labels
the same way, but serve no Cloudflare route that depends on them. A `make status` check that flags
a `com.k3d-manager.*` job whose `--context` differs from the provider being checked.

**Live check (operator, after merge):** the next sandbox `make up`, then
`make status CLUSTER_PROVIDER=k3s-hostinger`, must stay HEALTHY.
