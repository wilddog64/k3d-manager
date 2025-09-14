#!/usr/bin/env bats

load '../test_helpers.bash'

setup() {
  init_test_env
  ip() { echo "8.8.8.8 via 0.0.0.0 dev eth0 src 127.0.0.1 uid 1000"; }
  export -f ip
  source "${BATS_TEST_DIRNAME}/../../lib/core.sh"
  _cleanup_on_success() { :; }
  export -f _cleanup_on_success
}

@test "_create_k3d_cluster -h shows usage" {
  run _create_k3d_cluster -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: create_k3d_cluster"* ]]
}

@test "destroy_k3d_cluster -h shows usage" {
  run destroy_k3d_cluster -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: destroy_k3d_cluster"* ]]
}

@test "creates cluster with default ports" {
  _create_k3d_cluster() { cp "$1" "$BATS_TMPDIR/cluster.yaml"; }
  _list_k3d_cluster() { :; }
  export -f _create_k3d_cluster _list_k3d_cluster

  _create_k3d_cluster testcluster

  [ "$HTTP_PORT" = "8000" ]
  [ "$HTTPS_PORT" = "8443" ]
  grep -q "port: ${HTTP_PORT}:80" "$BATS_TMPDIR/cluster.yaml"
  grep -q "port: ${HTTPS_PORT}:443" "$BATS_TMPDIR/cluster.yaml"
}

@test "creates cluster with custom ports" {
  _create_k3d_cluster() { cp "$1" "$BATS_TMPDIR/cluster.yaml"; }
  _list_k3d_cluster() { :; }
  export -f _create_k3d_cluster _list_k3d_cluster

  _create_k3d_cluster altcluster 9090 9443

  [ "$HTTP_PORT" = "9090" ]
  [ "$HTTPS_PORT" = "9443" ]
  [[ -f "$BATS_TMPDIR/cluster.yaml" ]]
  grep -q "port: ${HTTP_PORT}:80" "$BATS_TMPDIR/cluster.yaml"
  grep -q "port: ${HTTPS_PORT}:443" "$BATS_TMPDIR/cluster.yaml"
}
