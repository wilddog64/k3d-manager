#!/usr/bin/env bats
# Black-box acceptance tests for sandbox auto-provisioning in e2e_verify_sandbox.
# Contract IDs: M1 M2 M3 / N1 N2 N3 N4.
bats_require_minimum_version 1.5.0

REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"

setup() {
  FAKE_BIN="$BATS_TEST_TMPDIR/bin"
  CALL_LOG="$BATS_TEST_TMPDIR/calls.log"
  CTX_STATE="$BATS_TEST_TMPDIR/ctx.state"
  mkdir -p "$FAKE_BIN"
  : > "$CALL_LOG"
  rm -f "$CTX_STATE"

  cat > "$FAKE_BIN/kubectl" <<'FAKE'
#!/usr/bin/env bash
printf 'kubectl %s\n' "$*" >> "$CALL_LOG"
if [[ "$1" == "config" ]]; then
  [[ -e "$CTX_STATE" ]] && printf 'ubuntu-k3s\n'
  printf 'k3d-k3d-cluster\n'
  exit 0
fi
if [[ "$*" == *"--raw=/readyz"* ]]; then
  if [[ "$*" == *"--context ubuntu-k3s"* || "$*" == *"--context=ubuntu-k3s"* ]]; then
    [[ -e "$CTX_STATE" ]] || exit 1
    [[ "$(cat "$CTX_STATE")" == "ready" ]] || exit 1
  fi
  exit 0
fi
exit 0
FAKE
  cat > "$FAKE_BIN/make" <<'FAKE'
#!/usr/bin/env bash
printf 'make %s\n' "$*" >> "$CALL_LOG"
if [[ "${MAKE_RC:-0}" -eq 0 && "${MAKE_CREATES:-1}" == "1" ]]; then
  printf 'ready' > "$CTX_STATE"
fi
exit "${MAKE_RC:-0}"
FAKE
  chmod +x "$FAKE_BIN/kubectl" "$FAKE_BIN/make"

  cat > "$BATS_TEST_TMPDIR/driver.sh" <<'DRV'
set -euo pipefail
export SCRIPT_DIR="$REPO/scripts"
export PLUGINS_DIR="$SCRIPT_DIR/plugins"
source "$SCRIPT_DIR/lib/system.sh"
source "$SCRIPT_DIR/lib/provider.sh"
source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/plugins/e2e.sh"
set -euo pipefail

_info() { printf '%s\n' "$*"; }
_warn() { printf '%s\n' "$*" >&2; }
_err() { printf '%s\n' "$*" >&2; return 1; }
_e2e_load_deps() { :; }
_e2e_sandbox_preflight_auth() { echo "auth" >> "$CALL_LOG"; return "${AUTH_RC:-0}"; }
_e2e_sandbox_preflight_hub() { echo "hub" >> "$CALL_LOG"; return "${HUB_RC:-0}"; }
acg_extend_playwright() { echo "phase:extend" >> "$CALL_LOG"; }
_e2e_sandbox_hub_apps_ready() { echo "phase:hub-apps" >> "$CALL_LOG"; }
_e2e_sandbox_provision_secrets() { echo "phase:secrets" >> "$CALL_LOG"; }
_e2e_sandbox_provision_keycloak_credentials() { echo "phase:keycloak" >> "$CALL_LOG"; }
_e2e_sandbox_enable_stripe() { echo "phase:stripe" >> "$CALL_LOG"; }
_e2e_sandbox_job_manifest() { echo "kind: Job"; }
_e2e_sandbox_wait_job() { echo "phase:playwright" >> "$CALL_LOG"; return 0; }
_e2e_sandbox_clear_profile() { echo "phase:cleanup" >> "$CALL_LOG"; }
_e2e_write_summary() { echo "summary rc=${3:-} phase=${4:-}" >> "$CALL_LOG"; }
_e2e_write_result_event() { echo "phase:record" >> "$CALL_LOG"; }
_run_command() {
  while [[ "${1:-}" == --* && "${1:-}" != "--" ]]; do shift; done
  [[ "${1:-}" == "--" ]] && shift
  "$@"
}
export E2E_REPORT_DIR="$BATS_TEST_TMPDIR/report"
E2E_SANDBOX_PROBE_TIMEOUT=1
e2e_verify_sandbox sha256:deadbeef
DRV
  export REPO CALL_LOG CTX_STATE BATS_TEST_TMPDIR
  export PATH="$FAKE_BIN:$PATH"
  export E2E_REPORT_DIR="$BATS_TEST_TMPDIR/report"
  export _ACG_SANDBOX_URL="https://example.test/sandbox"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  unset E2E_SANDBOX_PROVISION CLUSTER_PROVIDER MAKE_RC MAKE_CREATES AUTH_RC HUB_RC
}

drive() { run -- bash "$BATS_TEST_TMPDIR/driver.sh"; }

provision_calls() { grep -c '^make ' "$CALL_LOG" || true; }

@test "M1: authorized run with absent context provisions with exact command, then continues" {
  export E2E_SANDBOX_PROVISION=1 CLUSTER_PROVIDER=k3s-aws
  drive
  [ "$status" -eq 0 ]
  run grep -Ex -- "make (.* )?up CLUSTER_PROVIDER=k3s-aws" "$CALL_LOG"
  [ "$status" -eq 0 ]
  [ "$(provision_calls)" -eq 1 ]
  run grep -c '^phase:extend$' "$CALL_LOG"
  [ "$output" -ge 1 ]
  make_line="$(grep -n '^make ' "$CALL_LOG" | head -1 | cut -d: -f1)"
  ext_line="$(grep -n '^phase:extend$' "$CALL_LOG" | head -1 | cut -d: -f1)"
  [ "$make_line" -lt "$ext_line" ]
  run grep -Fx -- "phase:playwright" "$CALL_LOG"
  [ "$status" -eq 0 ]
}

@test "M1b: authorized run with context present but failing /readyz also provisions" {
  export E2E_SANDBOX_PROVISION=1 CLUSTER_PROVIDER=k3s-aws
  printf 'dead' > "$CTX_STATE"
  drive
  [ "$status" -eq 0 ]
  run grep -Ex -- "make (.* )?up CLUSTER_PROVIDER=k3s-aws" "$CALL_LOG"
  [ "$status" -eq 0 ]
  run grep -Fx -- "phase:extend" "$CALL_LOG"
  [ "$status" -eq 0 ]
}

@test "M2: healthy ubuntu-k3s is reused and nothing is provisioned" {
  export E2E_SANDBOX_PROVISION=1 CLUSTER_PROVIDER=k3s-aws
  printf 'ready' > "$CTX_STATE"
  drive
  [ "$status" -eq 0 ]
  [ "$(provision_calls)" -eq 0 ]
  run grep -Fx -- "phase:extend" "$CALL_LOG"
  [ "$status" -eq 0 ]
  run grep -Fx -- "phase:playwright" "$CALL_LOG"
  [ "$status" -eq 0 ]
}

@test "M3: provisioning failure is recorded as phase provisioning-sandbox, not preflight" {
  export E2E_SANDBOX_PROVISION=1 CLUSTER_PROVIDER=k3s-aws MAKE_RC=2
  drive
  [ "$status" -ne 0 ]
  run grep -Ex -- "make (.* )?up CLUSTER_PROVIDER=k3s-aws" "$CALL_LOG"
  [ "$status" -eq 0 ]
  run grep -F -- "summary rc=" "$CALL_LOG"
  [[ "$output" == *"phase=provisioning-sandbox"* ]]
  [[ "$output" != *"phase=preflight"* ]]
  run grep -c '^phase:extend$' "$CALL_LOG"
  [ "$output" -eq 0 ]
}

@test "N1: no E2E_SANDBOX_PROVISION means no provisioning" {
  export CLUSTER_PROVIDER=k3s-aws
  drive
  [ "$status" -ne 0 ]
  [ "$(provision_calls)" -eq 0 ]
  run grep -c '^phase:extend$' "$CALL_LOG"
  [ "$output" -eq 0 ]
}

@test "N1b: E2E_SANDBOX_PROVISION=0 and empty do not authorize provisioning" {
  export CLUSTER_PROVIDER=k3s-aws
  E2E_SANDBOX_PROVISION=0 drive
  [ "$status" -ne 0 ]
  [ "$(provision_calls)" -eq 0 ]
  : > "$CALL_LOG"
  E2E_SANDBOX_PROVISION='' drive
  [ "$status" -ne 0 ]
  [ "$(provision_calls)" -eq 0 ]
}

@test "N2a: credential preflight failure means no provisioning" {
  export E2E_SANDBOX_PROVISION=1 CLUSTER_PROVIDER=k3s-aws AUTH_RC=1
  drive
  [ "$status" -ne 0 ]
  [ "$(provision_calls)" -eq 0 ]
}

@test "N2b: hub preflight failure means no provisioning" {
  export E2E_SANDBOX_PROVISION=1 CLUSTER_PROVIDER=k3s-aws HUB_RC=1
  drive
  [ "$status" -ne 0 ]
  [ "$(provision_calls)" -eq 0 ]
}

@test "N3: no provisioning on a CLUSTER_PROVIDER other than k3s-aws" {
  export E2E_SANDBOX_PROVISION=1
  local p
  for p in k3d orbstack k3s; do
    : > "$CALL_LOG"
    rm -f "$CTX_STATE"
    CLUSTER_PROVIDER="$p" drive
    [ "$status" -ne 0 ]
    [ "$(provision_calls)" -eq 0 ]
  done
}

@test "N4: failed provisioning step is never reported as success" {
  export E2E_SANDBOX_PROVISION=1 CLUSTER_PROVIDER=k3s-aws MAKE_RC=1 MAKE_CREATES=1
  drive
  [ "$status" -ne 0 ]
  run grep -Fx -- "phase:playwright" "$CALL_LOG"
  [ "$status" -ne 0 ]
  run grep -F -- "phase=recording-result" "$CALL_LOG"
  [ "$status" -ne 0 ]
}
