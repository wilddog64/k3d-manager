#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/istio_ambient.sh"
}

@test "_istio_ambient_cni_dirs returns k3d paths" {
  run _istio_ambient_cni_dirs k3d
  [ "$status" -eq 0 ]
  [ "$output" = "/var/lib/rancher/k3s/agent/etc/cni/net.d /bin" ]
}

@test "_istio_ambient_cni_dirs returns k3s-hostinger paths" {
  run _istio_ambient_cni_dirs k3s-hostinger
  [ "$status" -eq 0 ]
  [ "$output" = "/var/lib/rancher/k3s/agent/etc/cni/net.d /var/lib/rancher/k3s/data/cni" ]
}

@test "_istio_ambient_cni_dirs defaults unknown providers to Cilium paths" {
  run _istio_ambient_cni_dirs ""
  [ "$status" -eq 0 ]
  [ "$output" = "/etc/cni/net.d /opt/cni/bin" ]

  run _istio_ambient_cni_dirs k3s-aws
  [ "$status" -eq 0 ]
  [ "$output" = "/etc/cni/net.d /opt/cni/bin" ]
}

@test "deploy_istio_ambient skips provider lookup when CNI dirs are preset" {
  local marker="${BATS_TEST_TMPDIR}/target-provider-called"
  _istio_ambient_target_provider() { : > "${marker}"; }
  AMBIENT_CNI_CONF_DIR=/preset/conf AMBIENT_CNI_BIN_DIR=/preset/bin run deploy_istio_ambient
  [ "$status" -eq 0 ]
  [ ! -e "${marker}" ]
}
