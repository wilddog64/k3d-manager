#!/usr/bin/env bats

load '../test_helpers.bash'

setup() {
  init_test_env
  ip() { echo "8.8.8.8 via 0.0.0.0 dev eth0 src 127.0.0.1 uid 1000"; }
  export -f ip
  export CLUSTER_PROVIDER=k3d
  source "${BATS_TEST_DIRNAME}/../../lib/system.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/core.sh"
  _ensure_cluster_provider
  _cleanup_on_success() { :; }
  export -f _cleanup_on_success
}

@test "create_cluster -h shows usage" {
  run create_cluster -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: create_cluster"* ]]
}

@test "destroy_cluster -h shows usage" {
  run destroy_cluster -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: destroy_cluster"* ]]
}

@test "creates cluster with default ports" {
  _provider_k3d_apply_cluster_config() { cp "$1" "$BATS_TMPDIR/cluster.yaml"; }
  _provider_k3d_list_clusters() { :; }
  export -f _provider_k3d_apply_cluster_config _provider_k3d_list_clusters

  _provider_k3d_create_cluster testcluster

  [ "$HTTP_PORT" = "8000" ]
  [ "$HTTPS_PORT" = "8443" ]
  grep -q "port: ${HTTP_PORT}:80" "$BATS_TMPDIR/cluster.yaml"
  grep -q "port: ${HTTPS_PORT}:443" "$BATS_TMPDIR/cluster.yaml"
}

@test "creates cluster with custom ports" {
  _provider_k3d_apply_cluster_config() { cp "$1" "$BATS_TMPDIR/cluster.yaml"; }
  _provider_k3d_list_clusters() { :; }
  export -f _provider_k3d_apply_cluster_config _provider_k3d_list_clusters

  _provider_k3d_create_cluster altcluster 9090 9443

  [ "$HTTP_PORT" = "9090" ]
  [ "$HTTPS_PORT" = "9443" ]
  [[ -f "$BATS_TMPDIR/cluster.yaml" ]]
  grep -q "port: ${HTTP_PORT}:80" "$BATS_TMPDIR/cluster.yaml"
  grep -q "port: ${HTTPS_PORT}:443" "$BATS_TMPDIR/cluster.yaml"
}

@test "cluster template mounts Jenkins home directory" {
  _provider_k3d_apply_cluster_config() { cp "$1" "$BATS_TMPDIR/cluster.yaml"; }
  _provider_k3d_list_clusters() { :; }
  export -f _provider_k3d_apply_cluster_config _provider_k3d_list_clusters

  _provider_k3d_create_cluster testcluster

  grep -F "volume: \"${SCRIPT_DIR}/storage/jenkins_home:/data/jenkins\"" "$BATS_TMPDIR/cluster.yaml"
  grep -F 'nodeFilters: ["agent:*","server:*"]' "$BATS_TMPDIR/cluster.yaml"
}
