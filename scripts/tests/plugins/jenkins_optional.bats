#!/usr/bin/env bats
# shellcheck shell=bash

@test "deploy_jenkins skips when ENABLE_JENKINS unset" {
  run env -i HOME="$HOME" PATH="$PATH" \
    bash -c 'SCRIPT_DIR="$(pwd)/scripts"; PLUGINS_DIR="$SCRIPT_DIR/plugins"; \
      source scripts/lib/system.sh; source scripts/lib/core.sh; source scripts/plugins/jenkins.sh; deploy_jenkins'
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped"* ]]
}

@test "deploy_jenkins skips when ENABLE_JENKINS=0" {
  run env -i HOME="$HOME" PATH="$PATH" ENABLE_JENKINS=0 \
    bash -c 'SCRIPT_DIR="$(pwd)/scripts"; PLUGINS_DIR="$SCRIPT_DIR/plugins"; \
      source scripts/lib/system.sh; source scripts/lib/core.sh; source scripts/plugins/jenkins.sh; deploy_jenkins'
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped"* ]]
}
