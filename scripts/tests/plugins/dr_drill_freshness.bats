#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() { mkdir -p "$BATS_TEST_TMPDIR/results"; }

@test "freshness: newest successful run passes" {
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  printf '{"run_timestamp":"%s","success":true}\n' "$stamp" > "$BATS_TEST_TMPDIR/results/old-name.json"
  run scripts/etc/dr/drill-freshness.sh "$BATS_TEST_TMPDIR/results"
  [ "$status" -eq 0 ]
}

@test "freshness: nine-day-old run fails" {
  stamp="$(date -u -d '9 days ago' +%Y%m%dT%H%M%SZ 2>/dev/null || date -u -v-9d +%Y%m%dT%H%M%SZ)"
  printf '{"run_timestamp":"%s","success":true}\n' "$stamp" > "$BATS_TEST_TMPDIR/results/old.json"
  run scripts/etc/dr/drill-freshness.sh "$BATS_TEST_TMPDIR/results"
  [ "$status" -eq 1 ]
}

@test "freshness: newest failed run fails" {
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  printf '{"run_timestamp":"%s","success":false}\n' "$stamp" > "$BATS_TEST_TMPDIR/results/bad.json"
  run scripts/etc/dr/drill-freshness.sh "$BATS_TEST_TMPDIR/results"
  [ "$status" -eq 1 ]
}

@test "freshness: empty results fails" {
  run scripts/etc/dr/drill-freshness.sh "$BATS_TEST_TMPDIR/results"
  [ "$status" -eq 1 ]
}

@test "freshness: chooses newest run timestamp instead of filename order" {
  printf '%s\n' '{"run_timestamp":"20261008T120000Z","success":false}' > "$BATS_TEST_TMPDIR/results/a.json"
  printf '%s\n' '{"run_timestamp":"20261009T120000Z","success":true}' > "$BATS_TEST_TMPDIR/results/z.json"
  run scripts/etc/dr/drill-freshness.sh "$BATS_TEST_TMPDIR/results"
  [ "$status" -eq 0 ]
}
