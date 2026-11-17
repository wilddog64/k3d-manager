#!/usr/bin/env bash
# Select BATS files deterministically, placing the two known long poles first.
set -euo pipefail

mode="${1:-}"
shard="${2:-}"
if [[ ! "$shard" =~ ^([1-9][0-9]*)/([1-9][0-9]*)$ ]]; then
  echo "usage: $0 list|run i/N" >&2
  exit 2
fi
index=${BASH_REMATCH[1]}
total=${BASH_REMATCH[2]}
if (( index > total )); then
  echo "shard index exceeds shard count" >&2
  exit 2
fi
if [[ "$mode" != list && "$mode" != run ]]; then
  echo "usage: $0 list|run i/N" >&2
  exit 2
fi

files=()
while IFS= read -r file; do
  files+=("$file")
done < <(find scripts/tests/lib scripts/tests/core scripts/tests/plugins scripts/tests/etc scripts/tests/bin \
  -maxdepth 1 -type f -name '*.bats' | LC_ALL=C sort)
ordered=()
for long_pole in scripts/tests/bin/codex_dispatch.bats scripts/tests/bin/makefile_test_all.bats; do
  for file in "${files[@]}"; do
    [[ "$file" != "$long_pole" ]] || ordered+=("$file")
  done
done
for file in "${files[@]}"; do
  case "$file" in
    scripts/tests/bin/codex_dispatch.bats|scripts/tests/bin/makefile_test_all.bats) ;;
    *) ordered+=("$file") ;;
  esac
done

position=0
result=0
for file in "${ordered[@]}"; do
  if (( position % total == index - 1 )); then
    if [[ "$mode" == list ]]; then
      printf '%s\n' "$file"
    else
      printf '[shard %s] %s\n' "$shard" "$file"
      case "$file" in
        scripts/tests/bin/*) scripts/tests/tripwire.sh bats "$file" || result=1 ;;
        *) scripts/tests/tripwire.sh ./scripts/k3d-manager test "${file#scripts/tests/}" || result=1 ;;
      esac
    fi
  fi
  position=$((position + 1))
done
exit "$result"
