#!/usr/bin/env bats

@test "make help advertises guarded stale cleanup" {
  run make help
  [ "$status" -eq 0 ]
  [[ "$output" == *"make cleanup-stale-sandbox"* ]]
  [[ "$output" == *"make cleanup-stale-clusters"* ]]
  [[ "$output" == *"CLEANUP_STALE=1"* ]]
}

@test "make down gates stale cleanup behind CLEANUP_STALE" {
  run make -pn
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLEANUP_STALE = 0"* ]]
  [[ "$output" == *'$(MAKE) --no-print-directory cleanup-stale-clusters CONFIRM=1'* ]]
  [[ "$output" == *'cleanup-stale-sandbox CLUSTER_PROVIDER=k3s-aws CONFIRM=1'* ]]
}
