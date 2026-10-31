#!/usr/bin/env bats

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  WORK="$(mktemp -d "${BATS_TEST_TMPDIR}/hub-new.XXXXXX")"
  ROOT="$WORK/repo"
  mkdir -p "$WORK/stub" "$WORK/home/Library/LaunchAgents" "$ROOT/bin" "$ROOT/scripts/lib" "$ROOT/scripts/etc"
  cp "${HUB_NEW_SOURCE:-$REPO/bin/hub-new}" "$ROOT/bin/hub-new"
  HUB_NEW_BIN="$ROOT/bin/hub-new"
  ln -s "$REPO/scripts/lib/foundation" "$ROOT/scripts/lib/foundation"
  ln -s "$REPO/scripts/lib/system.sh" "$ROOT/scripts/lib/system.sh"
  ln -s "$REPO/scripts/lib/provider.sh" "$ROOT/scripts/lib/provider.sh"
  ln -s "${AGENT_CLASSIFICATION_DIR:-$REPO/scripts/etc/machine}" "$ROOT/scripts/etc/machine"
  ln -s "$REPO/scripts/etc/cloudflared" "$ROOT/scripts/etc/cloudflared"
  ln -s "$REPO/scripts/etc/hostinger" "$ROOT/scripts/etc/hostinger"
  TUNNEL_CREDS="$(awk '$1 == "credentials-file:" {print $2}' "$REPO/scripts/etc/cloudflared/config.yml")"
  TUNNEL_CREDS="${TUNNEL_CREDS##*/}"
  mkdir -p "$WORK/home/.cloudflared"
  echo fixture > "$WORK/home/.cloudflared/$TUNNEL_CREDS"
  echo fixture > "$WORK/home/.cloudflared/cert.pem"
  export HOME="$WORK/home" HUB_NEW_STATE_DIR="$WORK/state" CALLS="$WORK/calls" AGENTS_DIR="$WORK/home/Library/LaunchAgents"
  [[ "$HOME" == "$WORK/home" ]]
  mkdir -p "$HOME/src/gitrepo/personal/shopping-carts/shopping-cart-infra/argocd/config"
  : > "$HOME/src/gitrepo/personal/shopping-carts/shopping-cart-infra/argocd/config/argocd-secret.yaml"
  export PATH="$WORK/stub:/opt/homebrew/bin:/usr/bin:/bin"
  export HUB_NEW_HOST=m5-air HUB_OLD_HOST=m4-air.local HOSTINGER_HOST=vps.example.test
  unset HUB_NEW_FROM K3DM_AGENT_LOAD

  cat > "$WORK/record" <<'REC'
record() { printf '%s %s K3DM_AGENT_LOAD=%s\n' "$1" "$2" "${K3DM_AGENT_LOAD:-unset}" >> "$CALLS"; }
plist() { : > "$AGENTS_DIR/com.k3d-manager.$1.plist"; }
REC

  for cmd in uname sysctl df hostname pmset docker gh kubectl launchctl id security make k3d; do
    cat > "$WORK/stub/$cmd" <<STUB
#!/usr/bin/env bash
source "$WORK/record"
STUB
    cat >> "$WORK/stub/$cmd" <<'STUB'
record "$(basename "$0")" "$*"
case "$(basename "$0")" in
  uname) echo arm64 ;;
  sysctl) echo 34359738368 ;;
  df) echo 'Filesystem 1024-blocks Used Available Capacity Mounted on'; echo '/dev/test 200000000 1 150000000 1% /' ;;
  hostname) echo "${STUB_HOSTNAME:-m5-air}" ;;
  pmset) printf ' SleepDisabled\t\t%s\n' "${STUB_SLEEP_DISABLED:-1}" ;;
  gh) exit 0 ;;
  k3d) [[ -z "${STUB_EXISTING_CLUSTER:-}" ]] || echo k3d-cluster ;;
  security) exit 0 ;;
  id) echo 501 ;;
  docker)
    case "$1" in
      logs)
        if [[ "${STUB_KINE:-good}" == few ]]; then
          printf '%s\n' 'time="2026-10-30T08:00:00Z" level=info msg="COMPACT deleted 10 rows"'
        elif [[ "${STUB_KINE:-good}" == short ]]; then
          printf '%s\n' \
            'time="2026-10-31T00:03:48Z" level=info msg="COMPACT deleted 520 rows from 520 revisions in 41.171018ms - compacted to 23183/24183"' \
            'time="2026-10-31T00:08:48Z" level=info msg="COMPACT deleted 433 rows from 433 revisions in 39.153384ms - compacted to 23616/24616"' \
            'time="2026-10-31T00:13:48Z" level=info msg="COMPACT deleted 511 rows from 511 revisions in 46.330374ms - compacted to 24127/25127"' \
            'time="2026-10-31T00:18:48Z" level=info msg="COMPACT deleted 496 rows from 490 revisions in 11.032966ms - compacted to 24617/25617"' \
            'time="2026-10-31T00:23:48Z" level=info msg="COMPACT deleted 588 rows from 537 revisions in 12.636181ms - compacted to 25154/26154"' \
            'time="2026-10-31T00:28:48Z" level=info msg="COMPACT deleted 715 rows from 665 revisions in 13.376893ms - compacted to 25819/26819"'
        else
          # Captured read-only from m5-air.local, docker logs k3d-k3d-cluster-server-0, 2026-10-31.
          printf '%s\n' \
            'time="2026-10-31T00:03:48Z" level=info msg="COMPACT deleted 520 rows from 520 revisions in 41.171018ms - compacted to 23183/24183"' \
            'time="2026-10-31T00:08:48Z" level=info msg="COMPACT deleted 433 rows from 433 revisions in 39.153384ms - compacted to 23616/24616"' \
            'time="2026-10-31T00:13:48Z" level=info msg="COMPACT deleted 511 rows from 511 revisions in 46.330374ms - compacted to 24127/25127"' \
            'time="2026-10-31T00:18:48Z" level=info msg="COMPACT deleted 496 rows from 490 revisions in 11.032966ms - compacted to 24617/25617"' \
            'time="2026-10-31T00:23:48Z" level=info msg="COMPACT deleted 588 rows from 537 revisions in 12.636181ms - compacted to 25154/26154"' \
            'time="2026-10-31T00:28:48Z" level=info msg="COMPACT deleted 715 rows from 665 revisions in 13.376893ms - compacted to 25819/26819"' \
            'time="2026-10-31T00:33:48Z" level=info msg="COMPACT deleted 594 rows from 602 revisions in 60.554062ms - compacted to 26421/27421"'
          [[ "${STUB_KINE:-good}" != error ]] || echo 'time="2026-10-30T08:36:00Z" level=error msg="Compact failed: failed to record compact revision: sql: transaction has already been committed or rolled back"'
        fi ;;
      exec) echo 4096 ;;
    esac ;;
  kubectl)
    case "$*" in
      *'get applications -o json'*)
        if [[ "${VERIFY_BAD_APP:-0}" == 1 ]]; then echo '{"items":[{"status":{"sync":{"status":"OutOfSync"},"health":{"status":"Degraded"}}}]}';
        else echo '{"items":[{"status":{"sync":{"status":"Synced"},"health":{"status":"Healthy"}}}]}'; fi ;;
      *'get externalsecret argocd-oidc-secret'*) [[ "${STUB_NO_OIDC:-0}" != 1 ]] || exit 1 ;;
      *'get externalsecrets -A -o json'*) echo '{"items":[{"status":{"conditions":[{"type":"Ready","status":"True","reason":"SecretSynced"}]}}]}' ;;
      *'vault status'*) echo 'Sealed          false' ;;
      *'get clustersecretstore'*'-o json'*) echo '{"status":{"conditions":[{"type":"Ready","status":"True"}]}}' ;;
      *'get application shopping-cart-identity -o json'*) [[ "${STUB_NO_IDENTITY:-0}" == 1 ]] && exit 1; echo '{"status":{"health":{"status":"Healthy"}}}' ;;
      *'describe secret platform-ops-notifications'*) echo 'slack-incoming-webhook-url:  120 bytes' ;;
    esac ;;
  launchctl)
    if [[ "${1:-}" == list && -n "${LOADED_LABEL:-}" ]]; then printf -- '- 0 com.k3d-manager.%s\n' "$LOADED_LABEL"; fi ;;
  make)
    case "$1" in
      install-cleanup) plist cleanup ;;
      install-node-health-watch) plist node-health-watch ;;
      install-sandbox-reaper) plist sandbox-reaper ;;
      install-cloud-bridge) plist cloud-bridge ;;
      install-prometheus-credential-rotator) plist prometheus-credential-rotator ;;
      install-test-metrics) plist test-metrics ;;
      snapshot-schedule) plist hub-snapshot ;;
      hub-data-export-schedule) plist hub-data-export ;;
    esac ;;
esac
exit 0
STUB
    chmod +x "$WORK/stub/$cmd"
  done

  for script in bin/hub-up bin/hub-restore bin/k3dm-webhook-setup bin/k3dm-hermes-setup scripts/k3d-manager; do
    cat > "$ROOT/$script" <<STUB
#!/usr/bin/env bash
source "$WORK/record"
STUB
    cat >> "$ROOT/$script" <<'STUB'
record "$(basename "$0")" "$* HUB_RESTORE_TUNNEL=${HUB_RESTORE_TUNNEL:-unset} HUB_RESTORE_PLATFORM=${HUB_RESTORE_PLATFORM:-unset} HUB_RESTORE_RECONCILE=${HUB_RESTORE_RECONCILE:-unset} KEYCLOAK_BASE_URL=${KEYCLOAK_BASE_URL:-unset} HUB_RECOVERY_ARGOCD_URL=${HUB_RECOVERY_ARGOCD_URL:-unset} TUNNEL_SSH_HOST=${TUNNEL_SSH_HOST:-unset}"
case "$(basename "$0") ${1:-}" in
  'k3dm-webhook-setup '*) plist webhook ;;
  'k3dm-hermes-setup '*) plist hermes ;;
  'k3d-manager vault_install_failover_watchdog') plist vault-failover ;;
  'k3d-manager acg_watch_start') plist acg-watch ;;
  'k3d-manager tunnel_start') plist ssh-tunnel; plist ssh-tunnel-vault ;;
esac
exit 0
STUB
    chmod +x "$ROOT/$script"
  done

  cat > "$ROOT/scripts/lib/cloudflare_tunnel.sh" <<STUB
source "$WORK/record"
STUB
  cat >> "$ROOT/scripts/lib/cloudflare_tunnel.sh" <<'STUB'
_ensure_cloudflare_tunnel_agent() { record _ensure_cloudflare_tunnel_agent "$*"; plist cloudflare-tunnel; }
STUB
}
teardown() { rm -rf "$WORK"; }

singleton_labels() { grep -v '^#' "$ROOT/scripts/etc/machine/hub-singletons.list" | cut -d'|' -f1; }

@test "M1: a full run passes every stage in order and writes a pass report" {
  run "$HUB_NEW_BIN"
  [ "$status" -eq 0 ]
  [ "$(grep -oE '^\[hub-new\] [a-z-]+: PASS' <<<"$output" | awk '{print $2}' | tr -d : | paste -sd' ' -)" = \
    'preflight machine-setup secrets-present hub-up hub-restore data reconcile prepare-singletons platform verify' ]
  jq -e '.status == "pass" and ([.stages[].stage] | length) == 10 and .checks.kine_compaction_cycles == 7 and .checks.kine_datastore_bytes == "4096"' \
    "$HUB_NEW_STATE_DIR/hub-new-report.json" >/dev/null
  grep -q '^make machine-setup ROLE=hub FROM=m4-air.local SECRETS=skip AGENTS=skip ' "$CALLS"
  grep -q '^hub-up ' "$CALLS"
  grep -q '^hub-restore .*HUB_RESTORE_TUNNEL=skip HUB_RESTORE_PLATFORM=skip' "$CALLS"
}

@test "hub-up builds only the cluster; observability and platform-ops wait for the data stage" {
  run "$HUB_NEW_BIN"
  [ "$status" -eq 0 ]
  grep -q '^hub-up ' "$CALLS"
  run grep -Eq '^make (hub-up|up)( |$)' "$CALLS"
  [ "$status" -eq 1 ]
  data_line="$(grep -n '^make hub-data-recover' "$CALLS" | head -1 | cut -d: -f1)"
  obs_line="$(grep -n '^make observability' "$CALLS" | head -1 | cut -d: -f1)"
  ops_line="$(grep -n '^make platform-ops' "$CALLS" | head -1 | cut -d: -f1)"
  [ -n "$data_line" ] && [ -n "$obs_line" ] && [ -n "$ops_line" ]
  [ "$obs_line" -gt "$data_line" ]
  [ "$ops_line" -gt "$data_line" ]
}

@test "the hub reconcile waits for the data restore and uses the new hub's own Keycloak and ArgoCD" {
  run "$HUB_NEW_BIN"
  [ "$status" -eq 0 ]
  grep -q '^hub-restore .*HUB_RESTORE_RECONCILE=skip' "$CALLS"
  rec="$(grep -n '^k3d-manager hub_recovery_reconcile --confirm ' "$CALLS")"
  [ "$(grep -c '^k3d-manager hub_recovery_reconcile' "$CALLS")" -eq 1 ]
  [[ "$rec" == *'KEYCLOAK_BASE_URL=http://localhost:8880 '* ]]
  [[ "$rec" == *'HUB_RECOVERY_ARGOCD_URL=http://localhost:8080 '* ]]
  rec_line="${rec%%:*}"
  data_line="$(grep -n '^make hub-data-recover' "$CALLS" | head -1 | cut -d: -f1)"
  reapply_line="$(grep -n '^make appsets-reapply' "$CALLS" | head -1 | cut -d: -f1)"
  [ -n "$data_line" ] && [ -n "$reapply_line" ]
  [ "$rec_line" -gt "$data_line" ]
  [ "$rec_line" -lt "$reapply_line" ]
}

@test "singleton plists are prepared after the reconcile writes the Cloudflare config" {
  run "$HUB_NEW_BIN"
  [ "$status" -eq 0 ]
  rec_line="$(grep -n '^k3d-manager hub_recovery_reconcile --confirm ' "$CALLS" | head -1 | cut -d: -f1)"
  tunnel_line="$(grep -n '^_ensure_cloudflare_tunnel_agent ' "$CALLS" | head -1 | cut -d: -f1)"
  cleanup_line="$(grep -n '^make install-cleanup' "$CALLS" | head -1 | cut -d: -f1)"
  [ -n "$rec_line" ] && [ -n "$tunnel_line" ] && [ -n "$cleanup_line" ]
  [ "$tunnel_line" -gt "$rec_line" ]
  [ "$cleanup_line" -gt "$rec_line" ]
}

@test "M1/N1: every child runs with K3DM_AGENT_LOAD=0 and every singleton plist is written" {
  run "$HUB_NEW_BIN"
  [ "$status" -eq 0 ]
  run grep -vE ' K3DM_AGENT_LOAD=0$' "$CALLS"
  [ "$status" -eq 1 ]
  local label
  for label in $(singleton_labels); do
    [ -f "$AGENTS_DIR/com.k3d-manager.${label}.plist" ] || { echo "missing plist: $label" >&2; return 1; }
  done
}

@test "N1: hub-new never runs ssh or a launchctl load, bootstrap, bootout or kickstart" {
  run "$HUB_NEW_BIN"
  [ "$status" -eq 0 ]
  run grep -E '^launchctl (load|bootstrap|bootout|kickstart|enable)' "$CALLS"
  [ "$status" -eq 1 ]
  run grep -Eq '(^|[;&|[:space:]])ssh[[:space:]]' "$HUB_NEW_BIN"
  [ "$status" -eq 1 ]
}

@test "M1: the Hostinger tunnel installer runs once against HOSTINGER_HOST" {
  run "$HUB_NEW_BIN"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^k3d-manager tunnel_start ' "$CALLS")" -eq 1 ]
  grep -q '^k3d-manager tunnel_start .*TUNNEL_SSH_HOST=ubuntu@vps.example.test' "$CALLS"
}

@test "without HOSTINGER_HOST the tunnel installer uses the tracked Hostinger default" {
  unset HOSTINGER_HOST HOSTINGER_SSH_USER
  expected="$(source "$REPO/scripts/etc/hostinger/vars.sh"; printf '%s@%s' "$HOSTINGER_SSH_USER" "$HOSTINGER_HOST")"
  [[ "$expected" == ?*@?* && "$expected" != *vps.example.test* ]]
  run "$HUB_NEW_BIN"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^k3d-manager tunnel_start ' "$CALLS")" -eq 1 ]
  grep -qF "TUNNEL_SSH_HOST=${expected} " "$CALLS"
}

@test "N2: preflight refuses to run on the old hub host before any mutating stage" {
  export HUB_NEW_HOST=m4-air STUB_HOSTNAME=m4-air
  run "$HUB_NEW_BIN"
  [ "$status" -ne 0 ]
  [[ "$output" == *'refusing to build on the old hub host'* ]]
  run grep -q '^make ' "$CALLS"
  [ "$status" -eq 1 ]
  grep -q '^preflight=fail ' "$HUB_NEW_STATE_DIR/state"
}

@test "N2: preflight refuses over a cluster it did not create" {
  export STUB_EXISTING_CLUSTER=1
  run "$HUB_NEW_BIN"
  [ "$status" -ne 0 ]
  [[ "$output" == *'cluster k3d-cluster exists but hub-new has no hub-up pass'* ]]
  run grep -q '^make ' "$CALLS"
  [ "$status" -eq 1 ]
}

@test "N2: preflight refuses when any singleton label is already loaded" {
  export LOADED_LABEL=webhook
  run "$HUB_NEW_BIN"
  [ "$status" -ne 0 ]
  [[ "$output" == *'singleton webhook is already loaded'* ]]
  run grep -q '^make ' "$CALLS"
  [ "$status" -eq 1 ]
}

@test "secrets-present refuses without the Cloudflare tunnel credentials after machine-setup and before hub-up" {
  [[ "$HOME" == "$WORK/home" ]]
  rm "$HOME/.cloudflared/$TUNNEL_CREDS"
  run "$HUB_NEW_BIN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Cloudflare tunnel file missing: ~/.cloudflared/$TUNNEL_CREDS"* ]]
  [[ "$output" == *"scp m4-air.local:.cloudflared/$TUNNEL_CREDS"* ]]
  grep -q '^secrets-present=fail ' "$HUB_NEW_STATE_DIR/state"
  grep -q '^make machine-setup ROLE=hub FROM=m4-air.local' "$CALLS"
  run grep -q '^hub-up ' "$CALLS"
  [ "$status" -eq 1 ]
}

@test "secrets-present refuses without the Cloudflare origin cert" {
  rm "$HOME/.cloudflared/cert.pem"
  run "$HUB_NEW_BIN"
  [ "$status" -ne 0 ]
  [[ "$output" == *'Cloudflare tunnel file missing: ~/.cloudflared/cert.pem'* ]]
  grep -q '^secrets-present=fail ' "$HUB_NEW_STATE_DIR/state"
}

@test "preflight passes without k3d installed so hub-up can install it" {
  rm "$WORK/stub/k3d"
  run command -v k3d
  [ "$status" -ne 0 ]
  run "$HUB_NEW_BIN"
  [ "$status" -eq 0 ]
  [[ "$output" != *'cannot query local k3d clusters'* ]]
  grep -q '^make ' "$CALLS"
}

@test "preflight reads macOS pmset output: SleepDisabled 1 passes, 0 fails" {
  export HUB_NEW_FROM=preflight STUB_SLEEP_DISABLED=0
  run "$HUB_NEW_BIN"
  [ "$status" -ne 0 ]
  [[ "$output" == *'sleep is not disabled'* ]]
  export STUB_SLEEP_DISABLED=1
  run "$HUB_NEW_BIN"
  [ "$status" -eq 0 ]
}

@test "N7: sudo appears only as the printed sleep remediation" {
  [ "$(grep -c 'sudo pmset -a disablesleep 1' "$HUB_NEW_BIN")" -eq 1 ]
  run grep -E '^[[:space:]]*sudo[[:space:]]' "$HUB_NEW_BIN"
  [ "$status" -eq 1 ]
}

@test "N4: source has no secret reads, bare make up, or datastore copy" {
  run grep -Eq 'security[[:space:]].*-w|make[[:space:]]+up([[:space:]]|$)|(cp|docker cp)[[:space:]].*state\.db' "$HUB_NEW_BIN"
  [ "$status" -eq 1 ]
}

@test "M2: resume reruns the first failed stage and skips passed stages" {
  mkdir -p "$HUB_NEW_STATE_DIR"
  printf 'preflight=pass 1\nmachine-setup=pass 2\nsecrets-present=fail 3\n' > "$HUB_NEW_STATE_DIR/state"
  run "$HUB_NEW_BIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'preflight: already passed; skipping'* ]]
  [[ "$output" == *'secrets-present: running'* ]]
  [[ "$output" != *'preflight: running'* ]]
  run grep -q '^make machine-setup' "$CALLS"
  [ "$status" -eq 1 ]
}

@test "M2: HUB_NEW_FROM restarts at that stage and reruns the stages after it" {
  mkdir -p "$HUB_NEW_STATE_DIR"
  printf '%s=pass 1\n' preflight machine-setup secrets-present hub-up hub-restore data reconcile prepare-singletons platform verify > "$HUB_NEW_STATE_DIR/state"
  export HUB_NEW_FROM=platform
  run "$HUB_NEW_BIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'platform: running'* ]]
  [[ "$output" == *'verify: running'* ]]
  [[ "$output" != *'data: running'* ]]
  grep -q '^make appsets-reapply ' "$CALLS"
  run grep -q '^hub-up ' "$CALLS"
  [ "$status" -eq 1 ]
}

@test "M2: an unknown HUB_NEW_FROM stage is refused" {
  export HUB_NEW_FROM=nope
  run "$HUB_NEW_BIN"
  [ "$status" -ne 0 ]
  [[ "$output" == *'unknown stage nope'* ]]
}

@test "M3: verify fails when an ArgoCD application is unhealthy" {
  export HUB_NEW_FROM=verify VERIFY_BAD_APP=1
  run "$HUB_NEW_BIN"
  [ "$status" -ne 0 ]
  [[ "$output" == *'one or more cicd Applications are not Synced and Healthy'* ]]
  grep -q '^verify=fail ' "$HUB_NEW_STATE_DIR/state"
  [ ! -f "$HUB_NEW_STATE_DIR/hub-new-report.json" ]
}

@test "M3: verify checks the shopping-cart-identity Application" {
  export HUB_NEW_FROM=verify STUB_NO_IDENTITY=1
  run "$HUB_NEW_BIN"
  [ "$status" -ne 0 ]
  [[ "$output" == *'shopping-cart-identity Application is missing or unhealthy'* ]]
}

@test "M3: verify reads Kine from the k3d server container and fails on a compaction error" {
  export HUB_NEW_FROM=verify STUB_KINE=error
  run "$HUB_NEW_BIN"
  [ "$status" -ne 0 ]
  [[ "$output" == *'Kine compaction error found'* ]]
  grep -q '^docker logs --since 2h k3d-k3d-cluster-server-0 ' "$CALLS"
}

@test "M3: verify fails with a retry time when fewer than six compaction cycles are logged" {
  export HUB_NEW_FROM=verify STUB_KINE=few
  run "$HUB_NEW_BIN"
  [ "$status" -ne 0 ]
  [[ "$output" == *'Kine: 1 of 6 compaction cycles over 30 minutes; rerun make hub-new after'* ]]
}

@test "M3: verify fails when six compaction cycles span less than 30 minutes" {
  export HUB_NEW_FROM=verify STUB_KINE=short
  run "$HUB_NEW_BIN"
  [ "$status" -ne 0 ]
  [[ "$output" == *'Kine: 6 of 6 compaction cycles over 30 minutes; rerun make hub-new after'* ]]
}

@test "M3: verify passes on seven real five-minute compaction cycles spanning 30 minutes" {
  export HUB_NEW_FROM=verify
  run "$HUB_NEW_BIN"
  [ "$status" -eq 0 ]
  jq -e '.checks.kine_compaction_cycles == 7' "$HUB_NEW_STATE_DIR/hub-new-report.json" >/dev/null
}

@test "M3: verify fails when a singleton is loaded" {
  mkdir -p "$HUB_NEW_STATE_DIR"
  printf '%s=pass 1\n' preflight > "$HUB_NEW_STATE_DIR/state"
  export HUB_NEW_FROM=verify LOADED_LABEL=hermes
  run "$HUB_NEW_BIN"
  [ "$status" -ne 0 ]
  [[ "$output" == *'singleton hermes is loaded'* ]]
}

@test "M5: Makefile singleton installers write the plist and never load it with K3DM_AGENT_LOAD=0" {
  local target label
  for target in cleanup node-health-watch sandbox-reaper test-metrics; do
    K3DM_AGENT_LOAD=0 /usr/bin/make -s -C "$REPO" "install-${target}" >/dev/null
    [ -s "$AGENTS_DIR/com.k3d-manager.${target}.plist" ] || { echo "no plist for $target" >&2; return 1; }
  done
  run grep -E '^launchctl (bootstrap|load|kickstart)' "$CALLS"
  [ "$status" -eq 1 ]
}

@test "M5: Makefile singleton installers still load the agent when K3DM_AGENT_LOAD is unset" {
  /usr/bin/make -s -C "$REPO" install-test-metrics >/dev/null
  grep -q "^launchctl bootstrap gui/501 $AGENTS_DIR/com.k3d-manager.test-metrics.plist " "$CALLS"
}

@test "M5: webhook and hermes setup write their plists and never load or rotate with K3DM_AGENT_LOAD=0" {
  K3DM_AGENT_LOAD=0 K3DM_PYTHON3_PATH=/bin/sh "$REPO/bin/k3dm-webhook-setup" >/dev/null
  K3DM_AGENT_LOAD=0 "$REPO/bin/k3dm-hermes-setup" >/dev/null
  [ -s "$AGENTS_DIR/com.k3d-manager.webhook.plist" ]
  [ -s "$AGENTS_DIR/com.k3d-manager.hermes.plist" ]
  run grep -E '^launchctl (bootstrap|bootout|load|kickstart)|^security (add|delete)-generic-password|^gh secret' "$CALLS"
  [ "$status" -eq 1 ]
  run grep -E '^security .* -w' "$CALLS"
  [ "$status" -eq 1 ]
}

@test "preflight requires the infra manifest" {
  rm "$HOME/src/gitrepo/personal/shopping-carts/shopping-cart-infra/argocd/config/argocd-secret.yaml"
  run "$HUB_NEW_BIN"
  [ "$status" -ne 0 ]
  [[ "$output" == *'shopping-cart-infra ArgoCD secret manifest is missing'* ]]
}

@test "verify requires the OIDC ExternalSecret" {
  export HUB_NEW_FROM=verify STUB_NO_OIDC=1
  run "$HUB_NEW_BIN"
  [ "$status" -ne 0 ]
  [[ "$output" == *'ArgoCD OIDC ExternalSecret cicd/argocd-oidc-secret is missing'* ]]
}
