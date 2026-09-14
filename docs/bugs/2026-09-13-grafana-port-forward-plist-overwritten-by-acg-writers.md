# Bug: ACG `cluster-up` / `cluster-refresh` overwrite the hub Grafana port-forward plist

**Filed:** 2026-09-13
**Branch:** `k3d-manager-v1.33.0`
**Incident:** `docs/issues/2026-07-08-hostinger-grafana-502-from-wrong-refresh-port-forward-target.md` (Recurrence 2026-09-13)
**Status:** READY FOR CODEX

---

## Problem

`grafana.3ai-talk.org` is served by cloudflared → `127.0.0.1:3001` → LaunchAgent
`com.k3d-manager.grafana-port-forward`. The correct agent runs the hub wrapper
`~/Library/LaunchAgents/com.k3d-manager.grafana-port-forward.sh`. That wrapper
port-forwards `svc/kube-prometheus-stack-grafana` on `k3d-k3d-cluster` with an
`/api/health` self-heal loop, and is written by
`_hostinger_write_monitoring_port_forward_plist` (`scripts/lib/providers/k3s-hostinger.sh:440`).

Two ACG code paths write a different target into the **same plist path**:

- **`bin/cluster-up` Step 10g.11** (~1635) *unconditionally* writes a direct `kubectl port-forward svc/acg-kube-prometheus-stack-grafana --context ubuntu-k3s`, then unloads and reloads it.
- **`bin/cluster-refresh`** (~411) writes the same direct target on `${_app_context}` whenever the plist file is missing.

The direct port-forward has no health check, so it goes zombie (listener up, HTTP 000). It also
serves a Grafana whose credentials do not match the hub Secret the smoke check reads
(`make status` "Grafana login: HTTP 401"). Seen on 2026-07-08 and again on 2026-09-13.

## Fix

Once the hub wrapper exists, it owns the Grafana agent. The ACG paths must never replace it.
If the plist is missing while the wrapper exists, regenerate a plist that invokes the wrapper.

### Before You Start

- `git pull origin k3d-manager-v1.33.0`; read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
- Read in full: `bin/cluster-up` lines 1630-1680, `bin/cluster-refresh` lines 405-460, and `scripts/lib/providers/k3s-hostinger.sh` lines 440-477 (the wrapper plist shape).
- Read `scripts/tests/bin/cluster_up.bats` and `scripts/tests/bin/cluster_refresh.bats` for the stubbing idiom.

### C1 — `bin/cluster-up`

Old:

```bash
if _is_mac; then
  _info "[acg-up] Step 10g.11/14 — Installing Grafana port-forward launchd agent (localhost:3001 → ubuntu-k3s svc/acg-kube-prometheus-stack-grafana, auto-restart)..."
```

New:

```bash
if _is_mac && [[ -f "${HOME}/Library/LaunchAgents/com.k3d-manager.grafana-port-forward.sh" ]]; then
  _info "[acg-up] Step 10g.11/14 — hub Grafana port-forward wrapper present; leaving com.k3d-manager.grafana-port-forward untouched"
elif _is_mac; then
  _info "[acg-up] Step 10g.11/14 — Installing Grafana port-forward launchd agent (localhost:3001 → ubuntu-k3s svc/acg-kube-prometheus-stack-grafana, auto-restart)..."
```

Only the `if` line changes, plus the new `_info`/`elif` pair. The rest of the block, including its closing `fi`, is unchanged.

### C2 — `bin/cluster-refresh`

Old:

```bash
  if [[ ! -f "${_grafana_pf_plist}" ]]; then
    _info "[acg-refresh] Grafana port-forward plist missing — regenerating..."
```

New:

```bash
  _grafana_pf_wrapper="${_grafana_pf_plist%.plist}.sh"
  if [[ ! -f "${_grafana_pf_plist}" && -f "${_grafana_pf_wrapper}" ]]; then
    _info "[acg-refresh] Grafana port-forward plist missing — regenerating from hub wrapper..."
    mkdir -p "$(dirname "${_grafana_pf_log}")"
    cat > "${_grafana_pf_plist}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${_grafana_pf_label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${_grafana_pf_wrapper}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${_grafana_pf_log}</string>
  <key>StandardErrorPath</key>
  <string>${_grafana_pf_log}</string>
</dict>
</plist>
PLIST
  elif [[ ! -f "${_grafana_pf_plist}" ]]; then
    _info "[acg-refresh] Grafana port-forward plist missing — regenerating..."
```

The existing ACG heredoc and its closing `fi` stay as the body of the `elif`.

### Tests (pure logic, `HOME` pointed at `BATS_TEST_TMPDIR`)

- `scripts/tests/bin/cluster_refresh.bats`: with the wrapper `.sh` present and no plist, the generated plist contains `/bin/bash` and `com.k3d-manager.grafana-port-forward.sh`, and does **not** contain `acg-kube-prometheus-stack-grafana`.
- `scripts/tests/bin/cluster_refresh.bats`: with neither file present, today's behaviour holds and the plist contains `acg-kube-prometheus-stack-grafana`.
- `scripts/tests/bin/cluster_up.bats`: if that suite reaches Step 10g.11 under stubs, add a case where an existing wrapper and plist leave the plist byte-identical. If it cannot reach that step, assert statically instead: `grep -c 'grafana-port-forward.sh" ]]; then' bin/cluster-up` equals `1`. Do not assert whole source lines.

## Definition of Done

- [ ] C1 and C2 implemented exactly; only `bin/cluster-up`, `bin/cluster-refresh`, the two BATS files and `CHANGELOG.md` changed
- [ ] `shellcheck -x bin/cluster-up bin/cluster-refresh` — no new warnings
- [ ] `bats scripts/tests/bin/cluster_refresh.bats scripts/tests/bin/cluster_up.bats` green — paste the summary
- [ ] CHANGELOG `## [Unreleased]` → `### Fixed`: "ACG cluster-up/cluster-refresh no longer overwrite the hub Grafana port-forward agent (recurring grafana.3ai-talk.org 502/401)"
- [ ] Commit message verbatim: `fix(cluster-up): stop ACG paths overwriting the hub Grafana port-forward plist`
- [ ] Pushed to `origin/k3d-manager-v1.33.0`; report the SHA

## What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`
- Do NOT modify `scripts/lib/providers/k3s-hostinger.sh`, `scripts/lib/foundation/`, or any other file outside the targets
- Do NOT run `launchctl` or touch the real `~/Library/LaunchAgents` in tests
