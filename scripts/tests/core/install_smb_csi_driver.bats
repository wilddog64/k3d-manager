#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  source "${BATS_TEST_DIRNAME}/../../lib/core.sh"
  init_test_env
}

@test "_install_smb_csi_driver installs chart with k3s defaults" {
  _is_mac() { return 1; }
  _ensure_helm() { echo "ensure_helm" >>"$RUN_LOG"; return 0; }
  _ensure_cifs_utils() { echo "ensure_cifs_utils" >>"$RUN_LOG"; return 0; }
  export -f _is_mac _ensure_helm _ensure_cifs_utils
  export_stubs

  KUBECTL_EXIT_CODES=(1 0)

  run _install_smb_csi_driver
  [ "$status" -eq 0 ]

  grep -q 'ensure_helm' "$RUN_LOG"
  grep -q 'ensure_cifs_utils' "$RUN_LOG"
  grep -q 'repo add --force-update smb-csi-driver https://kubernetes-sigs.github.io/smb-csi-driver' "$HELM_LOG"
  grep -q 'repo update smb-csi-driver' "$HELM_LOG"
  grep -q "upgrade --install smb-csi-driver smb-csi-driver/smb-csi-driver --namespace kube-system --create-namespace --wait --timeout 5m --values ${SCRIPT_DIR}/etc/k3s/smb-csi-driver-values.yaml" "$HELM_LOG"
  grep -q 'get csidriver smb.csi.k8s.io' "$KUBECTL_LOG"
  grep -q "${SCRIPT_DIR}/etc/k3s/smb-csi-driver-csidriver.yaml" "$KUBECTL_LOG"
}

@test "_install_smb_csi_driver aborts when cifs-utils unavailable" {
  _is_mac() { return 1; }
  _ensure_helm() { echo "ensure_helm" >>"$RUN_LOG"; return 0; }
  _ensure_cifs_utils() { return 1; }
  export -f _is_mac _ensure_helm _ensure_cifs_utils
  export_stubs

  run _install_smb_csi_driver
  [ "$status" -eq 1 ]
  [[ "$output" == *"cifs-utils installation failed"* ]]
  ! grep -q 'upgrade --install smb-csi-driver' "$HELM_LOG"
}

@test "_install_smb_csi_driver skips install on macOS" {
  _is_mac() { return 0; }
  export -f _is_mac
  export_stubs

  run _install_smb_csi_driver
  [ "$status" -eq 0 ]
  [[ "$output" == *"SMB CSI driver is not supported on macOS"* ]]
  [ ! -s "$HELM_LOG" ]
}
