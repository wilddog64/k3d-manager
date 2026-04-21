#!/usr/bin/env bats
# scripts/tests/plugins/gcp.bats — unit tests for gcp.sh

setup() {
  _info() { :; }
  export -f _info

  # Stub gcloud — records calls to BATS_TEST_TMPDIR/gcloud.log
  gcloud() {
    printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/gcloud.log"
    return 0
  }
  export -f gcloud

  # Stub node — succeeds silently
  node() { return 0; }
  export -f node

  export SCRIPT_DIR="${BATS_TEST_TMPDIR}/scripts"
  mkdir -p "${SCRIPT_DIR}/etc/playwright"
  cat > "${SCRIPT_DIR}/etc/playwright/vars.sh" <<'EOF'
PLAYWRIGHT_CDP_HOST="127.0.0.1"
PLAYWRIGHT_CDP_PORT="9222"
PLAYWRIGHT_AUTH_DIR="${HOME}/.local/share/k3d-manager/profile"
EOF

  source "scripts/plugins/gcp.sh"
}

# gcp_login --help

@test "gcp_login --help exits 0" {
  run gcp_login --help
  [ "$status" -eq 0 ]
}

# gcp_login — already authenticated as target account

@test "gcp_login skips gcloud when already active account" {
  gcloud() {
    case "$*" in
      "auth list --filter=status:ACTIVE --format=value(account)")
        printf '%s\n' "cloud_user@example.com" ;;
      *) printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/gcloud.log" ;;
    esac
    return 0
  }
  export -f gcloud

  run gcp_login "cloud_user@example.com"
  [ "$status" -eq 0 ]
  # gcloud auth login must NOT have been called
  run grep "auth login" "${BATS_TEST_TMPDIR}/gcloud.log" 2>/dev/null
  [ "$status" -ne 0 ]
}

# gcp_login — account in store but not active → config set

@test "gcp_login uses config set when account in store but not active" {
  gcloud() {
    case "$*" in
      "auth list --filter=status:ACTIVE --format=value(account)")
        printf '%s\n' "other_user@example.com" ;;
      "auth list --format=value(account)")
        printf '%s\n' "cloud_user@example.com" ;;
      *) printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/gcloud.log" ;;
    esac
    return 0
  }
  export -f gcloud

  run gcp_login "cloud_user@example.com"
  [ "$status" -eq 0 ]
  run grep "config set account cloud_user@example.com" "${BATS_TEST_TMPDIR}/gcloud.log"
  [ "$status" -eq 0 ]
}

# gcp_login — new account, node+playwright available → background gcloud + node

@test "gcp_login runs gcloud in background and node when playwright available" {
  gcloud() {
    case "$*" in
      "auth list --filter=status:ACTIVE --format=value(account)") printf '' ;;
      "auth list --format=value(account)")                        printf '' ;;
      *) printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/gcloud.log" ;;
    esac
    return 0
  }
  export -f gcloud

  node() {
    printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/node.log"
    return 0
  }
  export -f node

  run gcp_login "cloud_user@example.com"
  [ "$status" -eq 0 ]
  run grep "auth login --account cloud_user@example.com" "${BATS_TEST_TMPDIR}/gcloud.log"
  [ "$status" -eq 0 ]
  run grep "gcp_login.js cloud_user@example.com" "${BATS_TEST_TMPDIR}/node.log"
  [ "$status" -eq 0 ]
}

# gcp_login — node unavailable → manual fallback

@test "gcp_login falls back to manual gcloud when node unavailable" {
  gcloud() {
    case "$*" in
      "auth list --filter=status:ACTIVE --format=value(account)") printf '' ;;
      "auth list --format=value(account)")                        printf '' ;;
      *) printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/gcloud.log" ;;
    esac
    return 0
  }
  export -f gcloud

  # Override command to make node appear missing
  command() {
    if [[ "$*" == "-v node" ]]; then return 1; fi
    builtin command "$@"
  }
  export -f command

  run gcp_login "cloud_user@example.com"
  [ "$status" -eq 0 ]
  run grep "auth login --account cloud_user@example.com" "${BATS_TEST_TMPDIR}/gcloud.log"
  [ "$status" -eq 0 ]
}

# gcp_login — no account arg and GCP_USERNAME unset → returns 1

@test "gcp_login returns 1 when account not set" {
  unset GCP_USERNAME
  run gcp_login
  [ "$status" -eq 1 ]
}

# gcp_login — gcloud not found → returns 1

@test "gcp_login returns 1 when gcloud not found" {
  command() {
    if [[ "$*" == "-v gcloud" ]]; then return 1; fi
    builtin command "$@"
  }
  export -f command

  run gcp_login "cloud_user@example.com"
  [ "$status" -eq 1 ]
}

# gcp_login.js parse check

@test "gcp_login.js passes node --check" {
  run node --check scripts/playwright/gcp_login.js
  [ "$status" -eq 0 ]
}
