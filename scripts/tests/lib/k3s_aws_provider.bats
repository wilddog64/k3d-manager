#!/usr/bin/env bats
# shellcheck shell=bash

@test "_provider_k3s_aws_deploy_cluster --help prints k3s-aws usage" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/lib/provider.sh
    # stub sourced plugins to avoid side-effects
    acg_provision() { return 0; }
    deploy_app_cluster() { return 0; }
    tunnel_start() { return 0; }
    source scripts/lib/providers/k3s-aws.sh
    _provider_k3s_aws_deploy_cluster --help
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"k3s-aws"* ]]
}

@test "_provider_k3s_aws_destroy_cluster --help prints k3s-aws usage" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/lib/provider.sh
    acg_teardown() { return 0; }
    tunnel_stop() { return 0; }
    source scripts/lib/providers/k3s-aws.sh
    _provider_k3s_aws_destroy_cluster --help
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"k3s-aws"* ]]
}

@test "_provider_k3s_aws_destroy_cluster without --confirm fails" {
  run bash -c '
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/lib/provider.sh
    acg_teardown() { return 0; }
    tunnel_stop() { return 0; }
    source scripts/lib/providers/k3s-aws.sh
    _provider_k3s_aws_destroy_cluster
  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"--confirm"* ]]
}
