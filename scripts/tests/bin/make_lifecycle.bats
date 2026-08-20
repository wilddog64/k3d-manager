#!/usr/bin/env bats

@test "make help advertises guarded stale cleanup" {
  run make help
  [ "$status" -eq 0 ]
  [[ "$output" == *"make cleanup-stale-sandbox"* ]]
  [[ "$output" == *"make cleanup-stale-clusters"* ]]
  [[ "$output" == *"make cleanup-stale-resources"* ]]
  [[ "$output" == *"CLEANUP_STALE=1"* ]]
}

@test "make down gates stale cleanup behind CLEANUP_STALE" {
  run make -pn
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLEANUP_STALE = 0"* ]]
  [[ "$output" == *'$(MAKE) --no-print-directory cleanup-stale-resources CLUSTER_PROVIDER="$(CLUSTER_PROVIDER)" CONFIRM=1'* ]]
  [[ "$output" == *'_keep_hub_flag=--keep-hub'* ]]
  [[ "$output" == *'if [ "$(KEEP_LOCAL)" = "1" ] || [ "$(CLEANUP_STALE)" = "1" ]; then'* ]]
}

@test "cleanup-stale-resources dispatches both paths for AWS" {
  run make -pn
  [ "$status" -eq 0 ]
  [[ "$output" == *'cleanup-stale-clusters CONFIRM="$(CONFIRM)"'* ]]
  [[ "$output" == *'cleanup-stale-sandbox CLUSTER_PROVIDER=k3s-aws CONFIRM="$(if $(filter 1 true yes,$(CONFIRM)),1,0)"'* ]]
}
