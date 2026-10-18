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
  older="$(date -u -d '2 days ago' +%Y%m%dT%H%M%SZ 2>/dev/null || date -u -v-2d +%Y%m%dT%H%M%SZ)"
  newer="$(date -u -d '1 day ago' +%Y%m%dT%H%M%SZ 2>/dev/null || date -u -v-1d +%Y%m%dT%H%M%SZ)"
  printf '{"run_timestamp":"%s","success":false}\n' "$older" > "$BATS_TEST_TMPDIR/results/a.json"
  printf '{"run_timestamp":"%s","success":true}\n' "$newer" > "$BATS_TEST_TMPDIR/results/z.json"
  run scripts/etc/dr/drill-freshness.sh "$BATS_TEST_TMPDIR/results"
  [ "$status" -eq 0 ]
}

@test "freshness: workflow runs the script from the data repo main checkout, where the how-to installs it" {
  run grep -E '^ +- run: bash k3dm-manager/drill-freshness\.sh results$' scripts/etc/dr/drill-freshness.yml
  [ "$status" -eq 0 ]
  run grep -c 'scripts/etc/dr/drill-freshness.sh' scripts/etc/dr/drill-freshness.yml
  [ "$output" = "0" ]
  run grep -c 'drill-freshness.sh` to the root of the data repository' docs/howto/hub-dr-drill.md
  [ "$output" = "1" ]
}
