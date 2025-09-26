#!/usr/bin/env bats

load '../test_helpers.bash'

setup() {
  init_test_env
  export CLUSTER_PROVIDER=k3d
  source "${BATS_TEST_DIRNAME}/../../lib/system.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/core.sh"
}

@test "_install_k3d exports INSTALL_DIR" {
  _command_exist() { return 1; }
  _install_docker() { :; }
  _install_helm() { :; }
  _install_istioctl() { :; }
  _is_mac() { return 1; }
  _curl() {
    echo "$*" > "$BATS_TMPDIR/curl_cmd"
    cat <<EOF2
echo "INSTALL_DIR=\$INSTALL_DIR" > "$BATS_TMPDIR/install_dir"
EOF2
  }
  export -f _command_exist _install_docker _install_helm _install_istioctl _is_mac _curl

  _install_k3d /tmp/k3d-bin

  [ "$(cat "$BATS_TMPDIR/curl_cmd")" = "-f -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh" ]

  run cat "$BATS_TMPDIR/install_dir"
  [ "$status" -eq 0 ]
  [ "$output" = "INSTALL_DIR=/tmp/k3d-bin" ]
}
