#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/e2e.sh"
  export _ACG_SANDBOX_URL="https://example.test/sandbox"
  export PLAYWRIGHT_AUTH_DIR="$BATS_TEST_TMPDIR/no-pw-profile"
  SECURITY_ARGS="$BATS_TEST_TMPDIR/security.args"
  EXTEND_CALLED="$BATS_TEST_TMPDIR/extend.called"
  CALL_LOG="$BATS_TEST_TMPDIR/calls.log"
  : > "$SECURITY_ARGS"
  : > "$CALL_LOG"
  rm -f "$EXTEND_CALLED"
  unset K3DM_ACG_REQUIRE_CREDENTIALS

  FAKE_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$FAKE_BIN"
  export SECURITY_ARGS
  export CALL_LOG
  export ACG_FAKE_VALUE="${ACG_FAKE_VALUE:-tr0ubadour}"
  PATH="$FAKE_BIN:$PATH"
  export PATH

  _is_mac() { return 0; }
  _info() { printf '%s\n' "$*"; }
  _warn() { printf '%s\n' "$*"; }
  _err() { printf '%s\n' "$*"; return 1; }
  acg_extend_playwright() { : > "$EXTEND_CALLED"; }
  preflight_probe() {
    _e2e_sandbox_preflight_auth
    acg_extend_playwright "$_ACG_SANDBOX_URL"
  }
}

install_security() {
  cat > "$FAKE_BIN/security" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SECURITY_ARGS"
mode="${ACG_SECURITY_MODE:-readable}"
wants_value=0
for arg in "$@"; do
  [ "$arg" = "-w" ] && wants_value=1
done
case "$mode" in
  absent)
    exit 1
    ;;
  locked)
    if [ "$wants_value" -eq 1 ]; then
      printf 'security: SecKeychainSearchCopyNext: User interaction is not allowed.\n' >&2
      exit 1
    fi
    exit 0
    ;;
  empty)
    exit 0
    ;;
  password_only)
    case "$*" in
      *"-a password"*) exit 1 ;;
    esac
    ;;
esac
if [ "$wants_value" -eq 1 ]; then
  printf '%s' "$ACG_FAKE_VALUE"
fi
exit 0
FAKE
  chmod +x "$FAKE_BIN/security"
}

@test "preflight fails when _ACG_SANDBOX_URL is empty" {
  install_security
  unset _ACG_SANDBOX_URL
  run _e2e_sandbox_preflight_auth
  [ "$status" -ne 0 ]
  [[ "$output" == *"_ACG_SANDBOX_URL"* ]]
  run test -e "$EXTEND_CALLED"
  [ "$status" -ne 0 ]
}

@test "preflight refuses to run when K3DM_ACG_SKIP_SESSION_CHECK is set" {
  install_security
  export K3DM_ACG_SKIP_SESSION_CHECK=1
  run _e2e_sandbox_preflight_auth
  [ "$status" -ne 0 ]
  [[ "$output" == *"K3DM_ACG_SKIP_SESSION_CHECK=1"* ]]
}

@test "preflight reads no credential when it refuses on K3DM_ACG_SKIP_SESSION_CHECK" {
  install_security
  export K3DM_ACG_SKIP_SESSION_CHECK=1
  run _e2e_sandbox_preflight_auth
  [ "$status" -ne 0 ]
  run wc -c < "$SECURITY_ARGS"
  [ "$output" -eq 0 ]
}

@test "preflight fails when the credential entry is absent" {
  install_security
  export ACG_SECURITY_MODE=absent
  run _e2e_sandbox_preflight_auth
  [ "$status" -ne 0 ]
  [[ "$output" == *"k3dm-acg-pluralsight"* ]]
  [[ "$output" == *"unreadable=username,password"* ]]
}

@test "preflight fails when the entry exists but the login keychain is locked" {
  install_security
  export ACG_SECURITY_MODE=locked
  run _e2e_sandbox_preflight_auth
  [ "$status" -ne 0 ]
  [[ "$output" == *"credentials_loadable=false"* ]]
  [[ "$output" == *"unreadable=username,password"* ]]
  run test -e "$EXTEND_CALLED"
  [ "$status" -ne 0 ]
}

@test "preflight fails when the entry exists but the stored value is empty" {
  install_security
  export ACG_SECURITY_MODE=empty
  run _e2e_sandbox_preflight_auth
  [ "$status" -ne 0 ]
  [[ "$output" == *"credentials_loadable=false"* ]]
  [[ "$output" == *"unreadable=username,password"* ]]
}

@test "preflight still fails when the credential is unreadable but the profile dir EXISTS" {
  install_security
  export ACG_SECURITY_MODE=locked
  export PLAYWRIGHT_AUTH_DIR="$BATS_TEST_TMPDIR/live-pw-profile"
  mkdir -p "$PLAYWRIGHT_AUTH_DIR"
  run _e2e_sandbox_preflight_auth
  [ "$status" -ne 0 ]
  [[ "$output" == *"k3dm-acg-pluralsight"* ]]
  run test -e "$EXTEND_CALLED"
  [ "$status" -ne 0 ]
}

@test "preflight fails when only the username account is readable" {
  install_security
  export ACG_SECURITY_MODE=password_only
  run _e2e_sandbox_preflight_auth
  [ "$status" -ne 0 ]
  [[ "$output" == *"unreadable=password"* ]]
  [[ "$output" != *"unreadable=username"* ]]
}

@test "preflight loads both credential accounts by name" {
  install_security
  run _e2e_sandbox_preflight_auth
  [ "$status" -eq 0 ]
  run grep -F -- "-a username" "$SECURITY_ARGS"
  [ "$status" -eq 0 ]
  run grep -F -- "-a password" "$SECURITY_ARGS"
  [ "$status" -eq 0 ]
}

@test "preflight leaks no credential value into its output" {
  install_security
  run _e2e_sandbox_preflight_auth
  [ "$status" -eq 0 ]
  [[ "$output" != *"$ACG_FAKE_VALUE"* ]]
}

@test "preflight prints no placeholder credential command" {
  install_security
  export ACG_SECURITY_MODE=absent
  run _e2e_sandbox_preflight_auth
  [ "$status" -ne 0 ]
  [[ "$output" != *"add-generic-password"* ]]
  [[ "$output" != *"<"* ]]
}

@test "preflight arms the fail-closed credential gate for the session check" {
  install_security
  _e2e_sandbox_preflight_auth
  [ "$K3DM_ACG_REQUIRE_CREDENTIALS" = "1" ]
}

@test "preflight arms the fail-closed gate as an exported variable" {
  install_security
  _e2e_sandbox_preflight_auth
  run bash -c 'printf "%s" "$K3DM_ACG_REQUIRE_CREDENTIALS"'
  [ "$output" = "1" ]
}

@test "preflight passes when url, credentials and env are all sane" {
  install_security
  export K3DM_ACG_SKIP_SESSION_CHECK=0
  run _e2e_sandbox_preflight_auth
  [ "$status" -eq 0 ]
  run preflight_probe
  [ "$status" -eq 0 ]
  [ -e "$EXTEND_CALLED" ]
}

@test "make e2e-sandbox wires to the sandbox dispatcher and passes DIGEST through" {
  run grep -F -- 'e2e_verify_sandbox $(DIGEST)' Makefile
  [ "$status" -eq 0 ]
  run grep -F -- 'make e2e-sandbox' Makefile
  [ "$status" -eq 0 ]
}

_stub_kubectl() {
  kubectl() {
    printf 'kubectl %s\n' "$*" >> "$CALL_LOG"
    if [[ "$1" == "config" ]]; then
      printf '%s\n' ${KUBECTL_CONTEXTS:-}
      return 0
    fi
    if [[ "$*" == *"--raw=/readyz"* ]]; then
      return "${KUBECTL_READYZ_RC:-0}"
    fi
    return 0
  }
}

_stub_preview_mutations() {
  make() { printf 'make %s\n' "$*" >> "$CALL_LOG"; }
  acg_extend_playwright() { printf 'acg_extend_playwright\n' >> "$CALL_LOG"; }
  _e2e_sandbox_provision_cluster() { printf '_e2e_sandbox_provision_cluster\n' >> "$CALL_LOG"; }
  _e2e_sandbox_provision_secrets() { printf '_e2e_sandbox_provision_secrets\n' >> "$CALL_LOG"; }
  _e2e_sandbox_provision_keycloak_credentials() { printf '_e2e_sandbox_provision_keycloak_credentials\n' >> "$CALL_LOG"; }
  _e2e_sandbox_enable_stripe() { printf '_e2e_sandbox_enable_stripe\n' >> "$CALL_LOG"; }
}

@test "sandbox preview reports a ready cluster without making changes" {
  install_security
  _stub_kubectl
  _stub_preview_mutations
  KUBECTL_CONTEXTS="ubuntu-k3s k3d-k3d-cluster"
  KUBECTL_READYZ_RC=0
  run e2e_sandbox_preview "sha256:$(printf 'a%.0s' {1..64})"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[e2e-preview] acg login: ok"* ]]
  [[ "$output" == *"ubuntu-k3s: ready — would reuse it"* ]]
  [[ "$output" == *"[e2e-preview] hub: ok"* ]]
  [[ "$output" == *"digest: sha256:"* ]]
  [[ "$output" == *"no changes made"* ]]
  [ ! -s "$CALL_LOG" ] || ! grep -Eq '(^| )make |acg_extend_playwright|_e2e_sandbox_provision|_e2e_sandbox_enable_stripe| kubectl .* (apply|patch|delete)( |$)' "$CALL_LOG"
}

@test "sandbox preview reports an absent cluster without making changes" {
  install_security
  _stub_kubectl
  _stub_preview_mutations
  KUBECTL_CONTEXTS="k3d-k3d-cluster"
  KUBECTL_READYZ_RC=0
  run e2e_sandbox_preview
  [ "$status" -eq 0 ]
  [[ "$output" == *"ubuntu-k3s: absent or not ready — would run make up CLUSTER_PROVIDER=k3s-aws"* ]]
  [[ "$output" == *"digest: default (none given)"* ]]
  [[ "$output" == *"no changes made"* ]]
  [ ! -s "$CALL_LOG" ] || ! grep -Eq '(^| )make |acg_extend_playwright|_e2e_sandbox_provision|_e2e_sandbox_enable_stripe| kubectl .* (apply|patch|delete)( |$)' "$CALL_LOG"
}

@test "sandbox preview loads the ACG plugin for the sandbox URL" {
  install_security
  _stub_kubectl
  _stub_preview_mutations
  KUBECTL_CONTEXTS="ubuntu-k3s"
  KUBECTL_READYZ_RC=0
  unset _ACG_SANDBOX_URL
  unset -f acg_extend_playwright
  PLUGINS_DIR="$BATS_TEST_TMPDIR/plugins"
  mkdir -p "$PLUGINS_DIR"
  printf '%s\n' '_ACG_SANDBOX_URL="https://example.test/from-plugin"' 'acg_extend_playwright() { :; }' > "$PLUGINS_DIR/acg.sh"
  run e2e_sandbox_preview
  [ "$status" -eq 0 ]
  [[ "$output" == *"[e2e-preview] acg login: ok"* ]]
  [[ "$output" != *"_ACG_SANDBOX_URL is empty"* ]]
}

@test "sandbox preview stops on ACG auth failure" {
  install_security
  _stub_kubectl
  _stub_preview_mutations
  export ACG_SECURITY_MODE=absent
  run e2e_sandbox_preview
  [ "$status" -ne 0 ]
  [[ "$output" == *"[e2e-preview]"*"ACG preflight"* ]]
  [[ "$output" != *"hub: ok"* ]]
  [ ! -s "$CALL_LOG" ]
}

@test "sandbox preview stops on hub failure" {
  install_security
  _stub_kubectl
  _stub_preview_mutations
  KUBECTL_CONTEXTS="ubuntu-k3s"
  KUBECTL_READYZ_RC=1
  run e2e_sandbox_preview
  [ "$status" -ne 0 ]
  [[ "$output" == *"[e2e-preview] acg login: ok"* ]]
  [[ "$output" == *"hub preflight"* ]]
  [[ "$output" != *"no changes made"* ]]
  [ ! -s "$CALL_LOG" ] || ! grep -Eq '(^| )make |acg_extend_playwright|_e2e_sandbox_provision|_e2e_sandbox_enable_stripe| kubectl .* (apply|patch|delete)( |$)' "$CALL_LOG"
}

@test "cluster preflight fails when the sandbox kubecontext is absent" {
  _stub_kubectl
  KUBECTL_CONTEXTS="k3d-k3d-cluster ubuntu-hostinger"
  run _e2e_sandbox_preflight_cluster
  [ "$status" -ne 0 ]
  [[ "$output" == *"ubuntu-k3s"* ]]
  [[ "$output" == *"is absent"* ]]
  [[ "$output" == *"make up"* ]]
  [[ "$output" == *"make e2e-sandbox-provision"* ]]
}

@test "cluster preflight does not match a context by prefix" {
  _stub_kubectl
  KUBECTL_CONTEXTS="ubuntu-k3s-old"
  run _e2e_sandbox_preflight_cluster
  [ "$status" -ne 0 ]
  [[ "$output" == *"is absent"* ]]
}

@test "cluster preflight fails when the context exists but the API server is dead" {
  _stub_kubectl
  KUBECTL_CONTEXTS="ubuntu-k3s"
  KUBECTL_READYZ_RC=1
  run _e2e_sandbox_preflight_cluster
  [ "$status" -ne 0 ]
  [[ "$output" == *"readyz"* ]]
  [[ "$output" == *"4h"* ]]
}

@test "cluster preflight passes when the context exists and answers readyz" {
  _stub_kubectl
  KUBECTL_CONTEXTS="ubuntu-k3s"
  KUBECTL_READYZ_RC=0
  run _e2e_sandbox_preflight_cluster
  [ "$status" -eq 0 ]
  [[ "$output" == *"readyz=ok"* ]]
}

@test "cluster preflight runs before the sandbox extension burns a browser step" {
  local auth_line cluster_line extend_line
  auth_line="$(grep -n -- '_e2e_sandbox_preflight_auth$' "${BATS_TEST_DIRNAME}/../../plugins/e2e.sh" | tail -1 | cut -d: -f1)"
  cluster_line="$(grep -n -- '_e2e_sandbox_preflight_cluster$' "${BATS_TEST_DIRNAME}/../../plugins/e2e.sh" | tail -1 | cut -d: -f1)"
  extend_line="$(grep -n -- 'acg_extend_playwright "\${_ACG_SANDBOX_URL' "${BATS_TEST_DIRNAME}/../../plugins/e2e.sh" | cut -d: -f1)"
  [ "$auth_line" -lt "$cluster_line" ]
  [ "$cluster_line" -lt "$extend_line" ]
}

@test "hub preflight uses the default context and rejects an unavailable hub" {
  _stub_kubectl
  KUBECTL_READYZ_RC=1
  run _e2e_sandbox_preflight_hub
  [ "$status" -ne 0 ]
  [[ "$output" == *"k3d-k3d-cluster"* ]]
  [[ "$output" == *"readyz"* ]]
}

@test "hub preflight honors E2E_HUB_CONTEXT" {
  _stub_kubectl
  export E2E_HUB_CONTEXT=custom-hub
  run _e2e_sandbox_preflight_hub
  [ "$status" -eq 0 ]
  [[ "$output" == *"context=custom-hub"* ]]
}

@test "provision readiness reuses a healthy sandbox without calling make" {
  _stub_kubectl
  KUBECTL_CONTEXTS="ubuntu-k3s"
  KUBECTL_READYZ_RC=0
  run _e2e_sandbox_cluster_ready
  [ "$status" -eq 0 ]
  run ! grep -Eq '(^| )make ' "$CALL_LOG"
}

@test "provisioning calls make up only for the k3s-aws provider" {
  _run_command() {
    printf '%s\n' "$*" >> "$CALL_LOG"
  }
  export SCRIPT_DIR="$BATS_TEST_DIRNAME/../.."
  unset CLUSTER_PROVIDER
  run _e2e_sandbox_provision_cluster
  [ "$status" -eq 0 ]
  grep -F -- '--soft -- make -C' "$CALL_LOG"
  grep -F -- 'up CLUSTER_PROVIDER=k3s-aws' "$CALL_LOG"
}

@test "provisioning refuses a non-k3s-aws provider before make" {
  _run_command() {
    printf '%s\n' "$*" >> "$CALL_LOG"
  }
  _err() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
  }
  export CLUSTER_PROVIDER=k3d
  run _e2e_sandbox_provision_cluster
  [ "$status" -ne 0 ]
  [ ! -s "$CALL_LOG" ]
  [[ "$output" == *"only k3s-aws"* ]]
}

@test "provisioning failure is reported by the provisioning step" {
  _run_command() {
    printf '%s\n' "$*" >> "$CALL_LOG"
    return 1
  }
  _err() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
  }
  export SCRIPT_DIR="$BATS_TEST_DIRNAME/../.."
  run _e2e_sandbox_provision_cluster
  [ "$status" -ne 0 ]
  [[ "$output" == *"make up CLUSTER_PROVIDER=k3s-aws failed"* ]]
}

@test "provisioning orchestration checks auth and hub before provisioning" {
  local source_file="${BATS_TEST_DIRNAME}/../../plugins/e2e.sh"
  local auth_line hub_line provision_line
  auth_line="$(grep -n -- '^[[:space:]]*_e2e_sandbox_preflight_auth' "$source_file" | tail -1 | cut -d: -f1)"
  hub_line="$(grep -n -- '^[[:space:]]*_e2e_sandbox_preflight_hub' "$source_file" | head -1 | cut -d: -f1)"
  provision_line="$(grep -n -- '^[[:space:]]*_e2e_sandbox_provision_cluster' "$source_file" | tail -1 | cut -d: -f1)"
  [ "$auth_line" -lt "$hub_line" ]
  [ "$hub_line" -lt "$provision_line" ]
}

_stub_kubectl_slow_context_list() {
  kubectl() {
    if [[ "$1" == "config" ]]; then
      printf 'ubuntu-k3s\n'
      sleep 0.3
      printf 'k3d-k3d-cluster\n'
      return 0
    fi
    return 0
  }
}

@test "cluster preflight finds ubuntu-k3s when more contexts follow it in the listing" {
  _stub_kubectl_slow_context_list
  run _e2e_sandbox_preflight_cluster
  [ "$status" -eq 0 ]
}

@test "provision readiness finds ubuntu-k3s when more contexts follow it in the listing" {
  _stub_kubectl_slow_context_list
  run _e2e_sandbox_cluster_ready
  [ "$status" -eq 0 ]
}

@test "hub app convergence recovers frontend after product-catalog becomes healthy" {
  local listing_state="$BATS_TEST_TMPDIR/hub-listing.calls"
  printf '0\n' > "$listing_state"
  _e2e_hub_kc() {
    local listing_calls
    listing_calls=$(( $(<"$listing_state") + 1 ))
    printf '%s\n' "$listing_calls" > "$listing_state"
    case "$listing_calls" in
      1)
        printf '%s\n' \
          'ubuntu-k3s-shopping-cart-frontend Synced Degraded' \
          'ubuntu-k3s-shopping-cart-product-catalog OutOfSync Healthy'
        ;;
      2)
        printf '%s\n' \
          'ubuntu-k3s-shopping-cart-frontend Synced Degraded' \
          'ubuntu-k3s-shopping-cart-product-catalog Synced Healthy'
        ;;
      *)
        printf '%s\n' \
          'ubuntu-k3s-shopping-cart-frontend Synced Healthy' \
          'ubuntu-k3s-shopping-cart-product-catalog Synced Healthy'
        ;;
    esac
  }
  _e2e_sandbox_kc() {
    printf 'sandbox kubectl %s\n' "$*" >> "$CALL_LOG"
  }
  export E2E_HUB_APPS_TIMEOUT=5 E2E_HUB_APPS_INTERVAL=0

  run _e2e_sandbox_hub_apps_ready
  [ "$status" -eq 0 ]
  [[ "$output" == *"frontend upstream recovery"* ]]
  [ "$(grep -c -- 'rollout restart deployment/frontend' "$CALL_LOG")" -eq 1 ]
}
