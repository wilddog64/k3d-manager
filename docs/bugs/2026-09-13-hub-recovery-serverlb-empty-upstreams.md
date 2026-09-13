# Bug: hub recovery never checks the k3d serverlb upstream list

**Branch:** `k3d-manager-v1.33.0`
**Filed:** 2026-09-13
**Status:** FIXED `8e6d84b2` (Codex; Claude verified)
**Files:** `scripts/plugins/hub_recovery.sh`, `scripts/tests/plugins/hub_recovery.bats`, `CHANGELOG.md`
**Parent incident:** `2026-09-13-hub-orbstack-restart-serverlb-empty-config.md` (Defect 1)

## Problem

The k3d serverlb container (`k3d-<cluster>-serverlb`, image `ghcr.io/k3d-io/k3d-proxy:5.8.3`) renders nginx from `/etc/confd/values.yaml`. k3d writes that file only at cluster or node create. After the 2026-09-10/11 hub rebuild it held the image default:

```yaml
ports:
  6443.tcp: []
  80.tcp: []
  443.tcp: []
```

nginx kept serving from an old generated config until the 2026-09-13 OrbStack restart regenerated `stream { }`. Host `kubectl` then got `EOF`, and `127.0.0.1:8000` stopped reaching the frontend. `hub_recovery_reconcile` has no step for this, and its first step (`_hub_recovery_sync_vault_root_token`) already needs the host API. So reconcile fails with a kubectl error instead of naming the cause.

## Fix

Add a first reconcile step, "k3d serverlb upstreams". It builds the expected upstream list from the k3d container role labels (`k3d.role=server|agent`, `k3d.cluster=<cluster>`) and compares it with the live file as an order-insensitive set of `port|container` pairs. On drift it rewrites the file, restarts only the LB container, and waits for the host API to answer `/readyz`. Upstreams use container names, never IPs, because node IPs reshuffle on every OrbStack restart.

Port layout matches k3d's defaults for this hub: `6443.tcp` → servers only; `80.tcp` and `443.tcp` → servers then agents.

### S1 — `scripts/plugins/hub_recovery.sh`: new variable

After the line `HUB_RECOVERY_DOCKER_BIN="${HUB_RECOVERY_DOCKER_BIN:-docker}"` add:

```bash
HUB_RECOVERY_K3D_CLUSTER="${HUB_RECOVERY_K3D_CLUSTER:-k3d-cluster}"
```

### S2 — `scripts/plugins/hub_recovery.sh`: three new functions

Insert these immediately **before** `function hub_recovery_reconcile() {`:

```bash
function _hub_recovery_render_serverlb_values() {
  sort -k1,1r -k2,2 | awk '
    $1 == "server" { servers[++ns] = $2; upstreams[++nu] = $2 }
    $1 == "agent" { upstreams[++nu] = $2 }
    END {
      if (ns == 0) exit 1
      print "ports:"
      print "  6443.tcp:"
      for (i = 1; i <= ns; i++) print "  - " servers[i]
      print "  80.tcp:"
      for (i = 1; i <= nu; i++) print "  - " upstreams[i]
      print "  443.tcp:"
      for (i = 1; i <= nu; i++) print "  - " upstreams[i]
      print "settings:"
      print "  workerConnections: 1024"
    }'
}

function _hub_recovery_serverlb_upstream_pairs() {
  awk '
    /^[^ ]/ { in_ports = ($1 == "ports:"); key = ""; next }
    in_ports && /^  [0-9]+\.tcp:/ { key = $1; sub(/:$/, "", key); next }
    in_ports && key != "" && /^  - / { print key "|" $2 }
  ' | sort
}

function _hub_recovery_ensure_serverlb_upstreams() {
  local hub_context="$1" cluster="${2:-$HUB_RECOVERY_K3D_CLUSTER}"
  local lb="k3d-${cluster}-serverlb" nodes desired current rendered attempt
  if ! nodes=$("$HUB_RECOVERY_DOCKER_BIN" ps -a --filter "label=k3d.cluster=${cluster}" --format '{{.Label "k3d.role"}} {{.Names}}'); then
    _err "[hub-recovery] cannot list k3d containers for ${cluster}"
    return 1
  fi
  if ! desired=$(printf '%s\n' "$nodes" | _hub_recovery_render_serverlb_values); then
    _err "[hub-recovery] no k3d server container found for ${cluster}"
    return 1
  fi
  if ! current=$("$HUB_RECOVERY_DOCKER_BIN" exec "$lb" cat /etc/confd/values.yaml 2>/dev/null); then
    _err "[hub-recovery] cannot read ${lb}:/etc/confd/values.yaml"
    return 1
  fi
  if [[ "$(printf '%s\n' "$current" | _hub_recovery_serverlb_upstream_pairs)" == "$(printf '%s\n' "$desired" | _hub_recovery_serverlb_upstream_pairs)" ]]; then
    _info "[hub-recovery] ${lb} upstreams match k3d nodes"
    return 0
  fi
  _warn "[hub-recovery] ${lb} upstreams drifted from k3d nodes; rewriting values.yaml and restarting ${lb}"
  rendered=$(mktemp -t hub-recovery-serverlb.XXXXXX)
  printf '%s\n' "$desired" > "$rendered"
  if ! "$HUB_RECOVERY_DOCKER_BIN" cp "$rendered" "${lb}:/etc/confd/values.yaml"; then
    rm -f "$rendered"
    _err "[hub-recovery] failed to copy values.yaml into ${lb}"
    return 1
  fi
  rm -f "$rendered"
  if ! "$HUB_RECOVERY_DOCKER_BIN" restart "$lb" >/dev/null; then
    _err "[hub-recovery] failed to restart ${lb}"
    return 1
  fi
  for attempt in {1..30}; do
    if _kubectl --no-exit --quiet --context "$hub_context" get --raw /readyz >/dev/null 2>&1; then
      _info "[hub-recovery] ${lb} restarted; host API ready"
      return 0
    fi
    sleep "${HUB_RECOVERY_SERVERLB_WAIT_SECONDS:-2}"
  done
  _err "[hub-recovery] host API not ready after restarting ${lb}"
  return 1
}
```

### S3 — `scripts/plugins/hub_recovery.sh`: wire into `hub_recovery_reconcile`

Old:

```bash
  local -a steps=("Vault root token ↔ Keychain" "ESO policy" "Hub registration" "CVE reader credential" "OpenLDAP replicas" "Identity hook replay" "Smoke user" "ArgoCD admin Vault mirror" "Cloudflare origins")
```

New:

```bash
  local -a steps=("k3d serverlb upstreams" "Vault root token ↔ Keychain" "ESO policy" "Hub registration" "CVE reader credential" "OpenLDAP replicas" "Identity hook replay" "Smoke user" "ArgoCD admin Vault mirror" "Cloudflare origins")
```

Old:

```bash
  _hub_recovery_sync_vault_root_token "$hub_context" || return 1
```

New:

```bash
  _hub_recovery_ensure_serverlb_upstreams "$hub_context" || return 1
  _hub_recovery_sync_vault_root_token "$hub_context" || return 1
```

Change nothing else in the file.

## Tests — `scripts/tests/plugins/hub_recovery.bats`

1. **Update** the existing test `hub_recovery_reconcile: dry run prints steps and invokes no operations`:
   - change `for step in {1..9}; do` to `for step in {1..10}; do`;
   - add `[[ "$output" == *"k3d serverlb upstreams"* ]]` after the loop;
   - add a docker stub that logs to `$calls`, so `[ ! -s "$calls" ]` also proves dry-run does not touch docker. Define `docker_stub() { echo docker >> "$calls"; }` and set `HUB_RECOVERY_DOCKER_BIN=docker_stub`, exported like the other stubs.

2. **Add** these tests. They are behavioral: stub `HUB_RECOVERY_DOCKER_BIN` with a shell function, and never grep the plugin source.
   - `_hub_recovery_render_serverlb_values: servers on 6443, servers then agents on 80/443`
     - Input, unsorted, including a `loadbalancer` line: `agent k3d-c-agent-1`, `loadbalancer k3d-c-serverlb`, `server k3d-c-server-0`, `agent k3d-c-agent-0`.
     - Assert the exact output equals the expected 12-line YAML (heredoc compare), with `6443.tcp` holding only `k3d-c-server-0` and `80.tcp`/`443.tcp` holding `server-0, agent-0, agent-1` in that order.
   - `_hub_recovery_render_serverlb_values: fails with no server container` — agents only → non-zero status.
   - `_hub_recovery_serverlb_upstream_pairs: empty inline lists yield no pairs` — the image-default YAML (three `NNN.tcp: []` keys) → empty output.
   - `_hub_recovery_ensure_serverlb_upstreams: matching upstreams do not restart the LB`
     - The stub answers `ps` with the node list, and `exec` with the rendered YAML reordered (agents before server under `80.tcp`).
     - Assert status 0 and that no `cp` or `restart` call was logged.
   - `_hub_recovery_ensure_serverlb_upstreams: empty upstreams rewrite values and restart only the LB`
     - `exec` returns the image-default YAML; `cp` saves a copy of its source file into `BATS_TEST_TMPDIR`; `restart` logs its argument; `_kubectl` stub returns 0.
     - Assert status 0, `cp` target is `k3d-c-serverlb:/etc/confd/values.yaml`, the copied file lists `k3d-c-server-0` under `6443.tcp`, and the only restart argument is `k3d-c-serverlb`.
   - `_hub_recovery_ensure_serverlb_upstreams: fails when the host API never becomes ready`
     - Same as above, but the `_kubectl` stub returns 1.
     - Set `HUB_RECOVERY_SERVERLB_WAIT_SECONDS=0`; assert non-zero status.
   - `_hub_recovery_ensure_serverlb_upstreams: unreadable LB values fail without restart`
     - `exec` returns 1; assert non-zero status and no `restart` logged.

   Call the function as `_hub_recovery_ensure_serverlb_upstreams k3d-k3d-cluster c` so the LB name is `k3d-c-serverlb`.

## CHANGELOG

Under `## [Unreleased]` → `### Fixed`, add as the first bullet:

```
- `hub_recovery_reconcile` now checks the k3d serverlb upstream list first and, when it has drifted from the k3d server/agent containers (e.g. the empty image default left by a rebuild), rewrites `/etc/confd/values.yaml` by container name, restarts only the LB, and waits for the host API — an OrbStack restart no longer leaves host `kubectl` failing with `EOF`
```

## Definition of Done

- [ ] S1–S3 applied exactly; no other lines in `scripts/plugins/hub_recovery.sh` changed.
- [ ] `shellcheck -x scripts/plugins/hub_recovery.sh`: no new warnings versus the pre-change file (paste both counts).
- [ ] `bats scripts/tests/plugins/hub_recovery.bats`: all pass (paste summary).
- [ ] CHANGELOG bullet added.
- [ ] Commit message, verbatim: `fix(hub-recovery): assert and repair k3d serverlb upstreams before reconcile touches the API`
- [ ] Pushed; `git rev-parse origin/k3d-manager-v1.33.0` equals the commit SHA.

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`.
- Do NOT run `hub_recovery_reconcile --confirm`, `docker`, `kubectl`, or `k3d` against a live system. Tests use stubs only.
- Do NOT modify files outside the three listed targets. Do NOT edit `scripts/lib/foundation/`, `scripts/lib/acg/`, `scripts/lib/system.sh`, or memory-bank.
- Do NOT write IPs into the LB config.
- Do NOT use `grep -F` on source lines in BATS.
