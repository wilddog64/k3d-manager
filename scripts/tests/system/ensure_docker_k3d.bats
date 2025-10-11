#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  source "${BATS_TEST_DIRNAME}/../../lib/system.sh"
  init_test_env
}

@test "_ensure_docker succeeds when docker already exists" {
  _command_exist() {
    if [[ "$1" == "docker" ]]; then
      return 0
    fi
    return 1
  }
  export -f _command_exist
  export_stubs

  run _ensure_docker
  [ "$status" -eq 0 ]
}

@test "_ensure_docker installs docker when missing" {
  DOCKER_PRESENT=0
  _command_exist() {
    if [[ "$1" == "docker" ]]; then
      (( DOCKER_PRESENT )) && return 0 || return 1
    fi
    return 1
  }
  _install_docker() {
    echo "install_docker" >>"$RUN_LOG"
    DOCKER_PRESENT=1
    return 0
  }
  export -f _command_exist _install_docker
  export_stubs

  run _ensure_docker
  [ "$status" -eq 0 ]
  grep -q 'install_docker' "$RUN_LOG"
}

@test "_ensure_docker fails when installer fails" {
  _command_exist() { return 1; }
  _install_docker() {
    echo "install_docker" >>"$RUN_LOG"
    return 1
  }
  export -f _command_exist _install_docker
  export_stubs

  run _ensure_docker
  [ "$status" -eq 1 ]
  grep -q 'install_docker' "$RUN_LOG"
  [[ "$output" == *"Docker installation helper failed"* ]]
}

@test "_ensure_k3d succeeds when k3d already exists" {
  _command_exist() {
    if [[ "$1" == "k3d" ]]; then
      return 0
    fi
    return 1
  }
  export -f _command_exist
  export_stubs

  run _ensure_k3d
  [ "$status" -eq 0 ]
}

@test "_ensure_k3d installs k3d when missing" {
  K3D_PRESENT=0
  _command_exist() {
    if [[ "$1" == "k3d" ]]; then
      (( K3D_PRESENT )) && return 0 || return 1
    fi
    return 1
  }
  _install_k3d() {
    echo "install_k3d" >>"$RUN_LOG"
    K3D_PRESENT=1
    return 0
  }
  export -f _command_exist _install_k3d
  export_stubs

  run _ensure_k3d
  [ "$status" -eq 0 ]
  grep -q 'install_k3d' "$RUN_LOG"
}

@test "_ensure_k3d fails when installer fails" {
  _command_exist() { return 1; }
  _install_k3d() {
    echo "install_k3d" >>"$RUN_LOG"
    return 1
  }
  export -f _command_exist _install_k3d
  export_stubs

  run _ensure_k3d
  [ "$status" -eq 1 ]
  grep -q 'install_k3d' "$RUN_LOG"
  [[ "$output" == *"k3d installation attempted but binary still missing"* ]]
}
