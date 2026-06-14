#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  export HOME="${BATS_TEST_TMPDIR}/home"
  export PATH="${BATS_TEST_TMPDIR}/bin:$PATH"
  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${HOME}/.local/share/k3d-manager" "${HOME}/Library/LaunchAgents"
  : > "${BATS_TEST_TMPDIR}/aws.log"
  : > "${BATS_TEST_TMPDIR}/kubectl.log"
  : > "${BATS_TEST_TMPDIR}/k3d.log"
  : > "${BATS_TEST_TMPDIR}/launchctl.log"
  : > "${BATS_TEST_TMPDIR}/pgrep.log"
  : > "${BATS_TEST_TMPDIR}/pkill.log"
  : > "${BATS_TEST_TMPDIR}/kill.log"
  : > "${BATS_TEST_TMPDIR}/lsof.log"
  : > "${BATS_TEST_TMPDIR}/docker.log"

  cat <<'STUB' > "${BATS_TEST_TMPDIR}/bin/aws"
#!/usr/bin/env bash
set -euo pipefail
echo "aws $*" >> "${BATS_TEST_TMPDIR}/aws.log"
case "$*" in
  *"sts get-caller-identity"*)
    printf '%s\n' "arn:aws:sts::123456789012:assumed-role/test"
    ;;
  *"cloudformation describe-stacks"*)
    printf '%s\n' "None"
    ;;
esac
exit 0
STUB
  chmod +x "${BATS_TEST_TMPDIR}/bin/aws"

  cat <<'STUB' > "${BATS_TEST_TMPDIR}/bin/kubectl"
#!/usr/bin/env bash
set -euo pipefail
echo "kubectl $*" >> "${BATS_TEST_TMPDIR}/kubectl.log"
case "$*" in
  *"config get-contexts ubuntu-k3s"*)
    exit 0
    ;;
  *"config delete-context ubuntu-k3s"*)
    exit 0
    ;;
esac
exit 0
STUB
  chmod +x "${BATS_TEST_TMPDIR}/bin/kubectl"

  cat <<'STUB' > "${BATS_TEST_TMPDIR}/bin/k3d"
#!/usr/bin/env bash
set -euo pipefail
echo "k3d $*" >> "${BATS_TEST_TMPDIR}/k3d.log"
case "$*" in
  *"cluster list"*)
    printf '%s\n' "k3d-cluster   running"
    ;;
  *"cluster delete"*)
    printf '%s\n' "deleted"
    touch "${BATS_TEST_TMPDIR}/k3d-delete-called"
    ;;
esac
exit 0
STUB
  chmod +x "${BATS_TEST_TMPDIR}/bin/k3d"

  cat <<'STUB' > "${BATS_TEST_TMPDIR}/bin/launchctl"
#!/usr/bin/env bash
set -euo pipefail
echo "launchctl $*" >> "${BATS_TEST_TMPDIR}/launchctl.log"
if [[ "${STUB_LAUNCHCTL_BOOTOUT_FAIL:-0}" == "1" && "$*" == *"bootout system"* ]]; then
  echo "Boot-out failed: 5: Input/output error" >&2
  exit 5
fi
exit 0
STUB
  chmod +x "${BATS_TEST_TMPDIR}/bin/launchctl"

  cat <<'STUB' > "${BATS_TEST_TMPDIR}/bin/sudo"
#!/usr/bin/env bash
set -euo pipefail
args=()
for arg in "$@"; do
  case "$arg" in
    -n|--)
      continue
      ;;
    *)
      args+=("$arg")
      ;;
  esac
done
exec "${args[@]}"
STUB
  chmod +x "${BATS_TEST_TMPDIR}/bin/sudo"

  cat <<'STUB' > "${BATS_TEST_TMPDIR}/bin/pgrep"
#!/usr/bin/env bash
set -euo pipefail
echo "pgrep $*" >> "${BATS_TEST_TMPDIR}/pgrep.log"
exit 1
STUB
  chmod +x "${BATS_TEST_TMPDIR}/bin/pgrep"

  cat <<'STUB' > "${BATS_TEST_TMPDIR}/bin/pkill"
#!/usr/bin/env bash
set -euo pipefail
echo "pkill $*" >> "${BATS_TEST_TMPDIR}/pkill.log"
exit 0
STUB
  chmod +x "${BATS_TEST_TMPDIR}/bin/pkill"

  cat <<'STUB' > "${BATS_TEST_TMPDIR}/bin/kill"
#!/usr/bin/env bash
set -euo pipefail
echo "kill $*" >> "${BATS_TEST_TMPDIR}/kill.log"
exit 0
STUB
  chmod +x "${BATS_TEST_TMPDIR}/bin/kill"

  cat <<'STUB' > "${BATS_TEST_TMPDIR}/bin/lsof"
#!/usr/bin/env bash
set -euo pipefail
echo "lsof $*" >> "${BATS_TEST_TMPDIR}/lsof.log"
exit 0
STUB
  chmod +x "${BATS_TEST_TMPDIR}/bin/lsof"

  cat <<'STUB' > "${BATS_TEST_TMPDIR}/bin/docker"
#!/usr/bin/env bash
set -euo pipefail
echo "docker $*" >> "${BATS_TEST_TMPDIR}/docker.log"
exit 0
STUB
  chmod +x "${BATS_TEST_TMPDIR}/bin/docker"
}

@test "acg-down keeps the local hub when --keep-hub is set" {
  run bash -c 'bin/cluster-down --confirm --keep-hub 2>&1'
  [ "$status" -eq 0 ]
  [[ "$output" == *"keep-hub=1 hub-cluster=k3d-cluster"* ]]
  [[ "$output" == *"--keep-hub set — local Hub cluster preserved"* ]]
  [[ "$output" == *"Done. Remote cluster deleted; local Hub preserved."* ]]
  [ ! -f "${BATS_TEST_TMPDIR}/k3d-delete-called" ]
}

@test "acg-down deletes the local hub by default" {
  run bash -c 'bin/cluster-down --confirm 2>&1'
  [ "$status" -eq 0 ]
  [[ "$output" == *"keep-hub=0 hub-cluster=k3d-cluster"* ]]
  [[ "$output" == *"Local Hub cluster deleted"* ]]
  [[ "$output" == *"Done. Remote cluster and local Hub deleted."* ]]
  [ -f "${BATS_TEST_TMPDIR}/k3d-delete-called" ]
}

@test "acg-down removes the ArgoCD browser HTTPS listener" {
  mkdir -p "${HOME}/.local/share/k3d-manager/argocd-browser-https-tls"
  touch \
    "${HOME}/.local/share/k3d-manager/argocd-browser-https-tls/fullchain.crt" \
    "${HOME}/.local/share/k3d-manager/argocd-browser-https-tls/tls.key" \
    "${HOME}/.local/share/k3d-manager/argocd-browser-https-tls/ca.crt" \
    "${HOME}/.local/share/k3d-manager/argocd-browser-https-tls/tls.crt"
  run bash -c 'bin/cluster-down --confirm --keep-hub 2>&1'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Stopping ArgoCD browser HTTPS listener launchd daemon"* ]]
  run grep -F 'launchctl bootout system /Library/LaunchDaemons/com.k3d-manager.argocd-browser-https.plist' "${BATS_TEST_TMPDIR}/launchctl.log"
  [ "$status" -eq 0 ]
  [ ! -e "${HOME}/.local/share/k3d-manager/argocd-browser-https-tls/fullchain.crt" ]
  [ ! -e "${HOME}/.local/share/k3d-manager/argocd-browser-https-tls/tls.key" ]
  [ ! -e "${HOME}/.local/share/k3d-manager/argocd-browser-https-tls/ca.crt" ]
  [ ! -e "${HOME}/.local/share/k3d-manager/argocd-browser-https-tls/tls.crt" ]
}

@test "acg-down warns and continues when the ArgoCD browser listener is not loaded" {
  export STUB_LAUNCHCTL_BOOTOUT_FAIL=1
  run bash -c 'bin/cluster-down --confirm --keep-hub 2>&1'
  [ "$status" -eq 0 ]
  [[ "$output" == *"existing ArgoCD browser HTTPS listener was not loaded; continuing"* ]]
}

@test "acg-down removes the Keycloak browser HTTP listener" {
  touch \
    "${HOME}/.local/share/k3d-manager/keycloak-browser-http.sh" \
    "${HOME}/.local/share/k3d-manager/keycloak-browser-http.log" \
    "${HOME}/.local/share/k3d-manager/keycloak-browser-http-launchctl.log"
  run bash -c 'bin/cluster-down --confirm --keep-hub 2>&1'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Stopping Keycloak browser HTTP listener launchd daemon"* ]]
  run grep -F '_keycloak_browser_plist="${KEYCLOAK_BROWSER_LISTENER_PLIST:-/Library/LaunchDaemons/${_keycloak_browser_label}.plist}"' bin/cluster-down
  [ "$status" -eq 0 ]
  [ ! -e "${HOME}/.local/share/k3d-manager/keycloak-browser-http.sh" ]
  [ -e "${HOME}/.local/share/k3d-manager/keycloak-browser-http.log" ]
  [ -e "${HOME}/.local/share/k3d-manager/keycloak-browser-http-launchctl.log" ]
}
