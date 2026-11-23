#!/usr/bin/env bats
setup() {
  source <(sed '/^_load_access$/,$d' "$BATS_TEST_DIRNAME/../../etc/argocd/platform-ops/cve-remediation-verify.sh")
  log="$BATS_TEST_TMPDIR/patches"
  [[ "$log" == "$BATS_TEST_TMPDIR/patches" ]]
  sync='Synced|Healthy'; ready=1; image=repo@old; minimum=10
  _hub() {
    case "$*" in
      *'patch configmap'*) echo "$*" >>"$log";;
      *'.data.state}'*) echo promotion_requested;;
      *'.data.service}'*) echo shopping-cart-frontend;;
      *'.data.to_digest}'*) echo sha256:fixture;;
      *'.data.created_at}'*) echo 2024-02-29T00:00:00Z;;
      *'.status.sync.status}'*) echo "$sync";;
      *) return 1;;
    esac
  }
  _app() {
    case "$*" in
      *'.spec.minReadySeconds}'*) echo "$minimum";;
      *'.status.readyReplicas}'*) echo "$ready";;
      *'containers[0].image}'*) echo "$image";;
      *) echo 1;;
    esac
  }
}
@test "convergence failures stay pending until the bounded interval expires" {
  for reason in deployment_digest_mismatch deployment_not_fully_ready argocd_not_synced_or_healthy; do
    case "$reason" in deployment_not_fully_ready) ready=0;; argocd_not_synced_or_healthy) sync=Progressing;; esac
    : >"$log"
    VERIFY_NOW=1709165100 run _verify_event example
    [ "$status" = 0 ]; [[ "$output" == "pending example $reason" ]]; [ ! -s "$log" ]
    VERIFY_NOW=1709166100 run _verify_event example
    [ "$status" = 0 ]; grep -F "\"state\":\"failed\"" "$log"; grep -F "$reason" "$log"
  done
}
@test "a converged pin is applied immediately and manual review is immediate" {
  image=repo@sha256:fixture
  VERIFY_NOW=1709165100 _verify_event example
  grep -F verified_synced_healthy_digest "$log"
  minimum=0
  VERIFY_NOW=1709165100 _verify_event example
  grep -F min_ready_seconds_not_configured "$log"
}

@test "access loader writes a complete private kubeconfig and _app uses it" {
  local tmp="$BATS_TEST_TMPDIR/kubeconfig-tmp" capture="$BATS_TEST_TMPDIR/captured" log="$BATS_TEST_TMPDIR/kubectl-argv"
  [[ "$tmp" == "$BATS_TEST_TMPDIR/kubeconfig-tmp" ]]
  mkdir -p "$tmp"
  cat >"$BATS_TEST_TMPDIR/kubectl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$KUBECTL_TEST_LOG"
cp "$2" "$KUBECONFIG_CAPTURE"
EOF
  chmod +x "$BATS_TEST_TMPDIR/kubectl"
  KUBECTL_TEST_LOG="$log" KUBECONFIG_CAPTURE="$capture" APP_KUBECONFIG_TMPDIR="$tmp" \
    TEST_SERVER_B64="$(printf '%s' 'https://192.0.2.20:6443' | base64)" \
    TEST_CONFIG_B64="$(printf '%s' '{"bearerToken":"verify-token","tlsClientConfig":{"caData":"QUJD"}}' | base64)" \
    run bash -c '
      source <(sed '\''/^_load_access$/,$d'\'' "$1")
      _hub() { case "$*" in *jsonpath*=*server*) printf %s "$TEST_SERVER_B64";; *) printf %s "$TEST_CONFIG_B64";; esac; }
      KUBECTL_BIN="$2"
      _load_access
      before="$(umask)"
      _app get ns
      [ "$(umask)" = "$before" ]
    ' _ "$BATS_TEST_DIRNAME/../../etc/argocd/platform-ops/cve-remediation-verify.sh" "$BATS_TEST_TMPDIR/kubectl"
  [ "$status" -eq 0 ]
  grep -q '^current-context: app-cluster-context$' "$capture"
  grep -q 'certificate-authority-data: "QUJD"' "$capture"
  grep -q 'token: "verify-token"' "$capture"
  grep -q -- '--kubeconfig ' "$log"
  run grep -q 'verify-token' "$log"
  [ "$status" -eq 1 ]
  [ -z "$(find "$tmp" -mindepth 1 -print -quit)" ]
}

_make_verify_access_probe() {
  local dir="$1" script="${VERIFY_SCRIPT:-$BATS_TEST_DIRNAME/../../etc/argocd/platform-ops/cve-remediation-verify.sh}"
  mkdir -p "$dir/wrappers"
  sed '/^_load_access$/,$d' "$script" >"$dir/functions.sh"
  for _cmd in base64 sed mktemp rm cp; do
    _real="$(command -v "$_cmd")"
    cat >"$dir/wrappers/$_cmd" <<EOF
#!/bin/sh
printf '%s %s\\n' '$_cmd' "\$*" >>"\$ARGV_LOG"
exec "$_real" "\$@"
EOF
    chmod +x "$dir/wrappers/$_cmd"
  done
  cat >"$dir/kubectl" <<'EOF'
#!/bin/sh
printf 'kubectl %s\n' "$*" >>"$ARGV_LOG"
case "$1" in
  --kubeconfig)
    printf '%s\n' "$2" >"$OBSERVED_FILE"
    cp "$2" "$CAPTURE_FILE"
    case "${PROBE_MODE:-ok}" in
      fail) exit 7 ;;
      term) kill -TERM "$PPID"; exit 0 ;;
    esac
    ;;
esac
exit 0
EOF
  chmod +x "$dir/kubectl"
  cat >"$dir/run.sh" <<'EOF'
#!/bin/bash
set -eu
. "$VERIFY_FUNCTIONS"
KUBECTL_BIN="$VERIFY_KUBECTL_BIN"
_hub() {
  case "$*" in
    *server*) printf '%s' "$TEST_SERVER_B64" ;;
    *) printf '%s' "$TEST_CONFIG_B64" ;;
  esac
}
_before="$(umask)"
_load_access
[ "$(umask)" = "$_before" ] || exit 90
if [ -n "${APP_KUBECONFIG_DIR:-}" ]; then
  printf '%s\n' "$APP_KUBECONFIG_DIR" >"$OBSERVED_DIR"
  find "$APP_KUBECONFIG_DIR" -prune -perm 700 | grep -q . || exit 91
  find "$APP_KUBECONFIG_FILE" -prune -perm 600 | grep -q . || exit 92
fi
_app get ns
EOF
  chmod +x "$dir/run.sh"
}

_run_verify_access_probe() {
  local probe="$1" mode="$2" server="$3" config="$4"
  local server_b64
  if [ "$server" = __newline__ ]; then server_b64="$(printf 'https://192.0.2.30:6443\n' | base64)"; else server_b64="$(printf '%s' "$server" | base64)"; fi
  run env -i TMPDIR="${TMPDIR:-/tmp}" PATH="$probe/wrappers:$PATH" \
    VERIFY_FUNCTIONS="$probe/functions.sh" VERIFY_KUBECTL_BIN="$probe/kubectl" \
    APP_KUBECONFIG_TMPDIR="$BATS_TEST_TMPDIR/kubeconfig-tmp" \
    TEST_SERVER_B64="$server_b64" TEST_CONFIG_B64="$(printf '%s' "$config" | base64)" \
    PROBE_MODE="$mode" ARGV_LOG="$probe/argv.log" OBSERVED_DIR="$probe/dir" OBSERVED_FILE="$probe/file" CAPTURE_FILE="$probe/config" \
    /bin/bash "$probe/run.sh"
}

@test "verifier loader preserves umask and creates mode 0700/0600 files" {
  local probe="$BATS_TEST_TMPDIR/verify-mode"
  [[ "$BATS_TEST_TMPDIR/kubeconfig-tmp" == "$BATS_TEST_TMPDIR/kubeconfig-tmp" ]]
  mkdir -p "$BATS_TEST_TMPDIR/kubeconfig-tmp"
  _make_verify_access_probe "$probe"
  _run_verify_access_probe "$probe" ok https://192.0.2.30:6443 '{"bearerToken":"verify-argv-token"}'
  [ "$status" -eq 0 ]
  local dir file
  dir="$(cat "$probe/dir")"
  file="$(cat "$probe/file")"
  [[ "$file" == "$dir/config" ]]
  [ ! -e "$dir" ]
}

@test "verifier access directory is removed after failure and TERM exits 143" {
  local probe="$BATS_TEST_TMPDIR/verify-cleanup" mode expected
  mkdir -p "$BATS_TEST_TMPDIR/kubeconfig-tmp"
  _make_verify_access_probe "$probe"
  for mode in fail term; do
    _run_verify_access_probe "$probe" "$mode" https://192.0.2.30:6443 '{"bearerToken":"verify-argv-token","insecure":true}'
    if [ "$mode" = fail ]; then expected=7; else expected=143; fi
    [ "$status" -eq "$expected" ] || { printf 'mode=%s status=%s output=%s\n' "$mode" "$status" "$output"; return 1; }
    [ ! -e "$(cat "$probe/dir")" ]
  done
}

@test "verifier loader external argv never contains the bearer token" {
  local probe="$BATS_TEST_TMPDIR/verify-argv"
  mkdir -p "$BATS_TEST_TMPDIR/kubeconfig-tmp"
  _make_verify_access_probe "$probe"
  _run_verify_access_probe "$probe" ok https://192.0.2.30:6443 '{"bearerToken":"verify-argv-token"}'
  [ "$status" -eq 0 ]
  run grep -F 'verify-argv-token' "$probe/argv.log"
  [ "$status" -eq 1 ]
}

@test "verifier rejects malformed server and token values before writing kubeconfig" {
  local probe="$BATS_TEST_TMPDIR/verify-malformed" config failures=0
  mkdir -p "$BATS_TEST_TMPDIR/kubeconfig-tmp"
  _make_verify_access_probe "$probe"
  for config in '{"bearerToken":"valid-token"}' '{"bearerToken":"bad token"}' '{"bearerToken":"bad$token"}'; do
    : >"$probe/argv.log"
    local server=https://192.0.2.30:6443
    if [ "$config" = '{"bearerToken":"valid-token"}' ]; then server=__newline__; fi
    _run_verify_access_probe "$probe" ok "$server" "$config"
    if [ "$status" -ne 1 ] || [[ "$output" != *malformed* ]]; then failures=1; fi
    run grep -q '^kubectl --kubeconfig ' "$probe/argv.log"
    if [ "$status" -ne 1 ]; then failures=1; fi
    [ -z "$(find "$BATS_TEST_TMPDIR/kubeconfig-tmp" -mindepth 1 -print -quit)" ] || failures=1
  done
  [ "$failures" -eq 0 ]
}

@test "verifier insecure secret produces the insecure kubeconfig shape" {
  if ! sed --version >/dev/null 2>&1; then skip "insecure secret parsing needs GNU sed alternation; this host has BSD sed"; fi
  local probe="$BATS_TEST_TMPDIR/verify-insecure"
  mkdir -p "$BATS_TEST_TMPDIR/kubeconfig-tmp"
  _make_verify_access_probe "$probe"
  _run_verify_access_probe "$probe" ok https://192.0.2.30:6443 '{"bearerToken":"verify-argv-token","insecure":true}'
  [ "$status" -eq 0 ]
  grep -q '^    insecure-skip-tls-verify: true$' "$(cat "$probe/file")"
  grep -q '^current-context: app-cluster-context$' "$(cat "$probe/file")"
}

@test "verifier plain secret leaves cluster TLS fields unset" {
  local probe="$BATS_TEST_TMPDIR/verify-plain"
  mkdir -p "$BATS_TEST_TMPDIR/kubeconfig-tmp"
  _make_verify_access_probe "$probe"
  _run_verify_access_probe "$probe" ok https://192.0.2.30:6443 '{"bearerToken":"verify-argv-token"}'
  [ "$status" -eq 0 ]
  run grep -E 'certificate-authority-data|insecure-skip-tls-verify' "$probe/config"
  [ "$status" -eq 1 ]
  grep -q '^current-context: app-cluster-context$' "$probe/config"
}
