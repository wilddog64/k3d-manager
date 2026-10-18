#!/usr/bin/env bats
# Independent black-box acceptance tests for bin/cluster-down teardown verification.
bats_require_minimum_version 1.5.0
# Contract IDs: M1-M4, N1-N3.

REPO="${REPO:-$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)}"

setup() {
  REAL_BASH="$(command -v bash)"
  T="$(mktemp -d)"
  export HOME="${T}/home"
  mkdir -p "${HOME}" "${T}/bin" "${T}/log"
  export STUB_LOG="${T}/log"
  : > "${STUB_LOG}/aws.log"; : > "${STUB_LOG}/kubectl.log"; : > "${STUB_LOG}/other.log"

  cat > "${T}/bin/aws" <<'STUB'
#!/bin/bash
echo "aws $*" >> "${STUB_LOG}/aws.log"
case "$1 $2" in
  "sts get-caller-identity")
    [[ "${AWS_STS_FAIL:-0}" == 1 ]] && { echo "ExpiredToken" >&2; exit 254; }
    echo "arn:aws:sts::000000000000:assumed-role/stub/stub"; exit 0 ;;
  "cloudformation describe-stacks")
    case "${AWS_DESCRIBE_MODE:-ok}" in
      ok) echo "CREATE_COMPLETE"; exit 0 ;;
      absent) echo "An error occurred (ValidationError) when calling the DescribeStacks operation: Stack with id k3d-manager-cluster does not exist" >&2; exit 254 ;;
      throttle) echo "An error occurred (Throttling) when calling the DescribeStacks operation: Rate exceeded" >&2; exit 254 ;;
    esac ;;
  "cloudformation delete-stack")
    [[ "${AWS_DELETE_FAIL:-0}" == 1 ]] && { echo "AccessDenied" >&2; exit 254; }
    exit 0 ;;
  "cloudformation wait")
    [[ "${AWS_WAIT_FAIL:-0}" == 1 ]] && { echo "Waiter failed" >&2; exit 255; }
    exit 0 ;;
esac
exit 0
STUB
  cat > "${T}/bin/kubectl" <<'STUB'
#!/bin/bash
echo "kubectl $*" >> "${STUB_LOG}/kubectl.log"
exit 0
STUB
  for c in docker launchctl lsof k3d sudo gcloud az autossh ssh security osascript open; do
    printf '#!/bin/bash\necho "%s $*" >> "${STUB_LOG}/other.log"\nexit 0\n' "$c" > "${T}/bin/$c"
  done
  chmod +x "${T}"/bin/*
  ln -s "${REAL_BASH}" "${T}/bin/bash"
  export PATH="${T}/bin:/usr/bin:/bin"
  export ACG_REGION="us-west-2"
  export CLUSTER_PROVIDER="k3s-aws"
  unset K3DM_DEPLOY_DRY_RUN DRY_RUN KEEP_LOCAL
  STATE="${HOME}/.local/share/k3d-manager/k3s-aws"
  mkdir -p "${STATE}/run"
  sleep 300 &
  SLEEP_PID=$!
  echo "${SLEEP_PID}" > "${STATE}/run/vault-pf.pid"
}

teardown() {
  [[ -n "${SLEEP_PID:-}" ]] && kill "${SLEEP_PID}" 2>/dev/null || true
  # N3: only stubs were ever on PATH for aws/kubectl
  [[ "$(command -v aws)" == "${T}/bin/aws" ]]
  [[ "$(command -v kubectl)" == "${T}/bin/kubectl" ]]
  rm -rf "${T}"
}

summary_line() { printf '%s\n' "$1" | grep 'cloud teardown:' | tail -n 1; }

assert_no_bare_verified() {
  local line stripped
  line="$(summary_line "$1")"
  [ -n "${line}" ]
  stripped="$(printf '%s' "${line}" | sed -E 's/[Uu][Nn][Vv][Ee][Rr][Ii][Ff][Ii][Ee][Dd]//g')"
  run !  grep -qi 'verified' <<<"${stripped}"
}

assert_cleanup_ran() {
  grep -q 'delete secret cluster-ubuntu-k3s' "${STUB_LOG}/kubectl.log"
  [ ! -e "${STATE}/run/vault-pf.pid" ]
}

@test "M1: rc0 (stack present, delete+wait ok) exits 0 and prints verified naming stack and region" {
  run "${REAL_BASH}" "${REPO}/bin/cluster-down" --confirm
  [ "$status" -eq 0 ]
  line="$(summary_line "$output")"
  [[ "$line" == *"cloud teardown: verified"* ]]
  [[ "$line" == *"k3d-manager-cluster"* ]]
  [[ "$line" == *"us-west-2"* ]]
  grep -q 'cloudformation delete-stack' "${STUB_LOG}/aws.log"
  grep -q 'cloudformation wait stack-delete-complete' "${STUB_LOG}/aws.log"
}

@test "M1: absent stack ('does not exist') is rc0 and verified, exit 0" {
  AWS_DESCRIBE_MODE=absent run "${REAL_BASH}" "${REPO}/bin/cluster-down" --confirm
  [ "$status" -eq 0 ]
  [[ "$(summary_line "$output")" == *"cloud teardown: verified"* ]]
}

@test "M1: region from ACG_REGION is named in summary" {
  ACG_REGION=eu-west-1 run "${REAL_BASH}" "${REPO}/bin/cluster-down" --confirm
  [ "$status" -eq 0 ]
  [[ "$(summary_line "$output")" == *"eu-west-1"* ]]
}

@test "M2/N1/N2: acg_teardown rc2 (lookup throttled) exits 1, UNVERIFIED, cleanup still ran" {
  AWS_DESCRIBE_MODE=throttle run "${REAL_BASH}" "${REPO}/bin/cluster-down" --confirm
  st="$status"; out="$output"
  [ "$st" -eq 1 ]
  [[ "$(summary_line "$out")" == *"cloud teardown: UNVERIFIED"* ]]
  output="$out"; assert_no_bare_verified "$out"
  assert_cleanup_ran
  run !  grep -q 'delete-stack' "${STUB_LOG}/aws.log"
}

@test "M2/N1/N2: acg_teardown rc3 (delete-stack fails) exits 1, UNVERIFIED, cleanup still ran" {
  AWS_DELETE_FAIL=1 run "${REAL_BASH}" "${REPO}/bin/cluster-down" --confirm
  st="$status"; out="$output"
  [ "$st" -eq 1 ]
  [[ "$(summary_line "$out")" == *"cloud teardown: UNVERIFIED"* ]]
  assert_no_bare_verified "$out"
  assert_cleanup_ran
}

@test "M2/N1/N2: acg_teardown rc3 (wait fails) exits 1, UNVERIFIED, cleanup still ran" {
  AWS_WAIT_FAIL=1 run "${REAL_BASH}" "${REPO}/bin/cluster-down" --confirm
  st="$status"; out="$output"
  [ "$st" -eq 1 ]
  [[ "$(summary_line "$out")" == *"cloud teardown: UNVERIFIED"* ]]
  assert_no_bare_verified "$out"
  assert_cleanup_ran
}

@test "M2: UNVERIFIED summary carries a cause (non-empty text after the label)" {
  AWS_DESCRIBE_MODE=throttle run "${REAL_BASH}" "${REPO}/bin/cluster-down" --confirm
  line="$(summary_line "$output")"
  rest="${line#*UNVERIFIED}"
  [ -n "$(printf '%s' "$rest" | tr -d '[:space:]')" ]
}

@test "M3/N2: invalid credentials: acg_teardown not called, warning, UNVERIFIED (credentials invalid), exit 0" {
  AWS_STS_FAIL=1 run "${REAL_BASH}" "${REPO}/bin/cluster-down" --confirm
  st="$status"; out="$output"
  [ "$st" -eq 0 ]
  [[ "$(summary_line "$out")" == *"cloud teardown: UNVERIFIED"* ]]
  [[ "$(summary_line "$out")" == *"credentials invalid"* ]]
  assert_no_bare_verified "$out"
  grep -qi 'NOT verified' <<<"$out"
  grep -qi 'skipped' <<<"$out"
  run !  grep -q 'cloudformation' "${STUB_LOG}/aws.log"
  grep -q 'sts get-caller-identity' "${STUB_LOG}/aws.log"
}

@test "M4/N2: dry run prints 'cloud teardown: dry-run', no acg_teardown/aws calls, exit 0" {
  K3DM_DEPLOY_DRY_RUN=1 run "${REAL_BASH}" "${REPO}/bin/cluster-down" --confirm
  st="$status"; out="$output"
  [ "$st" -eq 0 ]
  [[ "$(summary_line "$out")" == *"cloud teardown: dry-run"* ]]
  assert_no_bare_verified "$out"
  [ ! -s "${STUB_LOG}/aws.log" ]
  run !  grep -q 'delete secret' "${STUB_LOG}/kubectl.log"
}

@test "M4/N2: non-AWS provider prints 'not applicable (<provider>)', exits 0, no aws calls" {
  CLUSTER_PROVIDER=somethingelse run "${REAL_BASH}" "${REPO}/bin/cluster-down" --confirm
  st="$status"; out="$output"
  [ "$st" -eq 0 ]
  [[ "$(summary_line "$out")" == *"cloud teardown: not applicable (somethingelse)"* ]]
  assert_no_bare_verified "$out"
  [ ! -s "${STUB_LOG}/aws.log" ]
}

@test "N3: stubs only - every aws/kubectl log line came from the stub dir binaries" {
  AWS_DESCRIBE_MODE=throttle run "${REAL_BASH}" "${REPO}/bin/cluster-down" --confirm
  [ "$status" -eq 1 ]
  [ -s "${STUB_LOG}/aws.log" ]
  run !  grep -qv '^aws ' "${STUB_LOG}/aws.log"
  run !  grep -qv '^kubectl ' "${STUB_LOG}/kubectl.log"
  [[ "$(command -v aws)" == "${T}/bin/aws" ]]
}
