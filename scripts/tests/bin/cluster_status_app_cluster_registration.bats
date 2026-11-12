#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

setup() {
  export REAL_HOME="$HOME"
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$HOME"
  export STUB_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${STUB_BIN}"
  export LAUNCHCTL_LOG="${BATS_TEST_TMPDIR}/launchctl.log"
  : > "$LAUNCHCTL_LOG"
  cat >"${STUB_BIN}/launchctl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$LAUNCHCTL_LOG"
exit 0
STUB
  cat >"${STUB_BIN}/lsof" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  cat >"${STUB_BIN}/security" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  cat >"${STUB_BIN}/kubectl" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"get secret cluster-ubuntu-k3s"* ]]; then
  exit 0
fi
if [[ "$*" == *"get secret cluster-"* && "$*" != *"cluster-ubuntu-k3s"* ]]; then
  [[ "${APP_SECRET_PRESENT:-false}" == "true" ]]
  exit
fi
if [[ "$*" == *"config get-contexts ubuntu-hostinger"* ]]; then
  [[ "${APP_CONTEXT_PRESENT:-false}" == "true" ]]
  exit
fi
if [[ "$*" == *"get applications.argoproj.io"* ]]; then
  printf 'NAME\tSTATUS\n'
fi
exit 0
STUB
  cat >"${STUB_BIN}/aws" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  cat >"${STUB_BIN}/curl" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "${STUB_BIN}"/*
  export PATH="${STUB_BIN}:${PATH}"
  export CLUSTER_PROVIDER=k3s-aws APP_CONTEXT=ubuntu-k3s INFRA_CONTEXT=k3d-k3d-cluster
  export ARGOCD_NAMESPACE=cicd
}

@test "cluster-status restore path bootstraps launch agents under the test HOME" {
  [[ "$(uname -s)" == Darwin ]] || skip "macOS only"
  run bin/cluster-status
  [ "$status" -eq 0 ]
  grep -F "bootstrap gui/" "$LAUNCHCTL_LOG" | grep -F "$HOME/Library/LaunchAgents/com.k3d-manager.alertmanager-port-forward.plist"
  run ! grep -F "$REAL_HOME/Library/LaunchAgents" "$LAUNCHCTL_LOG"
}

@test "cluster-status reports a present app-cluster registration" {
  APP_SECRET_PRESENT=true run bin/cluster-status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Registered: ubuntu-hostinger"* ]]
}

@test "cluster-status reports a registration gap for a reachable app context" {
  APP_CONTEXT_PRESENT=true run bin/cluster-status
  [ "$status" -eq 0 ]
  [[ "$output" == *"REGISTRATION GAP:"* ]]
  [[ "$output" == *"make refresh-registration"* ]]
}

@test "cluster-status reports an absent retired app context without a gap" {
  run bin/cluster-status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Not present: ubuntu-hostinger"* ]]
  [[ "$output" != *"REGISTRATION GAP:"* ]]
}
