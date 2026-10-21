#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  mkdir -p "$BATS_TEST_TMPDIR/results"
  export DR_FRESHNESS_NOW_EPOCH=1792540800
}

@test "freshness: fresh successful run passes" {
  printf '{"run_timestamp":"20261021T000000Z","success":true}\n' > "$BATS_TEST_TMPDIR/results/latest.json"
  run scripts/etc/dr/drill-freshness.sh "$BATS_TEST_TMPDIR/results"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "freshness: exact eight-day boundary passes" {
  printf '{"run_timestamp":"20261013T000000Z","success":true}\n' > "$BATS_TEST_TMPDIR/results/latest.json"
  run scripts/etc/dr/drill-freshness.sh "$BATS_TEST_TMPDIR/results"
  [ "$status" -eq 0 ]
}

@test "freshness: stale successful run fails with timestamp, age, cutoff and next steps" {
  printf '{"run_timestamp":"20261012T000000Z","success":true}\n' > "$BATS_TEST_TMPDIR/results/latest.json"
  run scripts/etc/dr/drill-freshness.sh "$BATS_TEST_TMPDIR/results"
  [ "$status" -eq 1 ]
  [[ "$output" == *"20261012T000000Z"* ]]
  [[ "$output" == *"age 9d 0h"* ]]
  [[ "$output" == *"8-day threshold"* ]]
  [[ "$output" == *"cutoff was 2026-10-13T00:00:00Z"* ]]
  [[ "$output" == *"make dr-drill on M2"* ]]
  [[ "$output" == *"make dr-drill-publish on M4"* ]]
  [[ "$output" == *"stale evidence, not a failed recovery drill"* ]]
}

@test "freshness: latest failed result has distinct diagnostic" {
  printf '{"run_timestamp":"20261021T000000Z","success":false}\n' > "$BATS_TEST_TMPDIR/results/latest.json"
  run scripts/etc/dr/drill-freshness.sh "$BATS_TEST_TMPDIR/results"
  [ "$status" -eq 1 ]
  [[ "$output" == *"latest drill failed"* ]]
  [[ "$output" == *"20261021T000000Z"* ]]
  [[ "$output" == *"success=false"* ]]
  [[ "$output" == *"make dr-drill on M2"* ]]
}

@test "freshness: no valid result has distinct diagnostic without payload" {
  printf '{"run_timestamp":"not-a-date","success":true,"secret":"do-not-print"}\n' > "$BATS_TEST_TMPDIR/results/invalid.json"
  printf 'not json\n' > "$BATS_TEST_TMPDIR/results/broken.json"
  run scripts/etc/dr/drill-freshness.sh "$BATS_TEST_TMPDIR/results"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no valid results"* ]]
  [[ "$output" == *"make dr-drill-publish on M4"* ]]
  [[ "$output" != *"do-not-print"* ]]
}

@test "freshness: chooses newest valid run timestamp instead of filename order" {
  printf '{"run_timestamp":"20261020T000000Z","success":false}\n' > "$BATS_TEST_TMPDIR/results/a.json"
  printf '{"run_timestamp":"20261021T000000Z","success":true}\n' > "$BATS_TEST_TMPDIR/results/z.json"
  run scripts/etc/dr/drill-freshness.sh "$BATS_TEST_TMPDIR/results"
  [ "$status" -eq 0 ]
}

@test "freshness: workflow uses installed data-repo script and how-to documents synchronization" {
  run grep -E '^ +- run: bash k3dm-manager/drill-freshness\.sh results$' scripts/etc/dr/drill-freshness.yml
  [ "$status" -eq 0 ]
  run grep -c 'scripts/etc/dr/drill-freshness.sh' scripts/etc/dr/drill-freshness.yml
  [ "$output" = "0" ]
  run grep -c 'scripts/etc/dr/drill-freshness.sh` to the root of the data repository' docs/howto/hub-dr-drill.md
  [ "$output" = "1" ]
}
